import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../data/firebase_config.dart';
import '../models/payment.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../utils/image_bytes.dart';
import 'payment_ledger.dart';

/// Builds the read-only snapshot that a customer opens from a WhatsApp link.
///
/// The snapshot is written to `statements/{token}` and is the only thing an
/// unauthenticated visitor can read: it contains this customer's open bills,
/// never the rest of the ledger. Anyone holding the token can read it, so the
/// token is long and random and can be revoked by deleting the document.
class StatementService {
  StatementService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _alphabet = 'abcdefghijkmnopqrstuvwxyz23456789';

  String _randomToken([int length = 20]) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
  }

  String _customerKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  DocumentReference<Map<String, dynamic>> _indexDoc(String ownerUid, String customerName) =>
      _db.collection('statementIndex').doc('${ownerUid}__${_customerKey(customerName)}');

  DocumentReference<Map<String, dynamic>> _statementDoc(String token) =>
      _db.collection('statements').doc(token);

  /// Publishes (or refreshes) the statement for one customer and returns the
  /// token. The token is reused so the customer does not end up with several
  /// links for the same account.
  Future<String?> publish({
    required String ownerUid,
    required String customerName,
    required List<Transaction> openBills,
    required Map<String, List<Payment>> paymentsByTransaction,
    required AppSettings settings,
    required String agentPhone,
  }) async {
    if (!FirebaseRuntime.initialized) return null;

    // The rule compares this field with request.auth.uid, so it must be the
    // live session, not a cached fallback value.
    final liveUid = FirebaseAuth.instance.currentUser?.uid;
    if (liveUid == null || liveUid.isEmpty) return null;
    ownerUid = liveUid;

    final bills = <Map<String, dynamic>>[];
    var totalBalance = 0.0;
    var evidenceBudget = 2; // keep the snapshot well under the 1 MiB limit

    for (final txn in openBills) {
      final payments = paymentsByTransaction[txn.id] ?? const <Payment>[];
      final paid = PaymentLedger.paidTotal(payments);
      final balance = (txn.totalAmount - paid).clamp(0, double.infinity);
      if (balance <= 0.005) continue;

      String? evidence;
      if (evidenceBudget > 0 && txn.receiptImagePath != null) {
        evidence = await evidenceDataUri(txn.receiptImagePath);
        if (evidence != null) evidenceBudget--;
      }

      totalBalance += balance;
      bills.add({
        'id': txn.id,
        'billNo': txn.cashBillNumber ?? txn.invoiceNumber ?? '',
        'description': txn.itemDescription,
        'total': txn.totalAmount,
        'paid': paid,
        'balance': balance,
        'dueDate': txn.dueDate.toIso8601String(),
        'daysOverdue': txn.daysOverdue,
        'status': txn.displayStatus,
        'evidence': evidence,
        'evidenceNote': txn.evidenceReason,
      });
    }

    // Reuse the token (and therefore the customer's saved link) when one
    // already exists for this customer.
    String token;
    String reconCode;
    // A read of a document that does not exist yet can be rejected by the
    // rules engine (resource is null), so a failure here simply means "no
    // previous link for this customer".
    Map<String, dynamic>? existingData;
    try {
      existingData = (await _indexDoc(ownerUid, customerName).get()).data();
    } catch (_) {
      existingData = null;
    }
    final existingToken = existingData?['token']?.toString();
    if (existingToken != null && existingToken.isNotEmpty) {
      token = existingToken;
      String? previousCode;
      try {
        previousCode =
            (await _statementDoc(token).get()).data()?['reconCode']?.toString();
      } catch (_) {
        previousCode = null;
      }
      reconCode = previousCode ?? PaymentLedger.newReconCode();
    } else {
      token = _randomToken();
      reconCode = PaymentLedger.newReconCode();
    }

    final now = DateTime.now();
    await _statementDoc(token).set({
      'ownerUid': ownerUid,
      'shopName': settings.shopName,
      'payeeName': settings.payeeName,
      'bankNote': settings.bankNote,
      'paymentQr': settings.paymentQr,
      'customerName': customerName,
      'reconCode': reconCode,
      'agentPhone': agentPhone,
      'bills': bills,
      'totalBalance': totalBalance,
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
    });

    await _indexDoc(ownerUid, customerName).set({
      'token': token,
      'customerName': customerName,
      'ownerUid': ownerUid,
      'reconCode': reconCode,
      'updatedAt': now.toIso8601String(),
    });

    // A direct lookup by the code the customer typed into their bank transfer,
    // so the agent can find the owner of an unexplained credit in one step.
    await _db
        .collection('users')
        .doc(ownerUid)
        .collection('reconCodes')
        .doc(reconCode)
        .set({
      'customerName': customerName,
      'token': token,
      'updatedAt': now.toIso8601String(),
    });

    return token;
  }

  /// Reads a statement for the public customer page. Returns null when the
  /// token does not exist or has expired.
  Future<Map<String, dynamic>?> fetch(String token) async {
    if (!FirebaseRuntime.initialized) return null;
    if (token.isEmpty) return null;
    final snapshot = await _statementDoc(token).get();
    final data = snapshot.data();
    if (data == null) return null;

    final expires = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    if (expires != null && DateTime.now().isAfter(expires)) return null;
    return data;
  }

  /// The customer declares that the money has been sent. This never touches the
  /// balance: the agent confirms it first.
  Future<bool> declarePayment({
    required String token,
    required String ownerUid,
    required String customerName,
    required double amount,
    String? note,
    String? proofImage,
    String? reconCode,
    List<String>? billIds,
    List<String>? billLabels,
    /// Set by the demo gateway, and used only to label the receipt.
    bool simulated = false,

    /// A payment a gateway already verified. The agent does not approve it a
    /// second time, so the claim is written with `autoConfirm` and the agent
    /// client turns it into a payment entry by itself.
    bool autoConfirm = false,
  }) async {
    if (!FirebaseRuntime.initialized) return false;
    // The customer is anonymous, so the claim is owned by the agent named in the
    // statement snapshot, not by a session. Using the session uid here silently
    // dropped every claim made from a phone that was not signed in.
    if (ownerUid.isEmpty) return false;
    final id = const Uuid().v4();
    await _db.collection('paymentClaims').doc(id).set({
      'id': id,
      'token': token,
      'ownerUid': ownerUid,
      'customerName': customerName,
      'amount': amount,
      'note': note,
      'reconCode': reconCode,
      'proofImage': proofImage,
      'billIds': billIds ?? const <String>[],
      'billLabels': billLabels ?? const <String>[],
      'billCount': (billIds ?? const <String>[]).length,
      'status': 'pending',
      'simulated': simulated,
      'autoConfirm': autoConfirm,
      'declaredAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// Finds which customer a reference code belongs to.
  ///
  /// Statements published before the code index existed have no
  /// `reconCodes` document, so the lookup falls back to scanning the customer
  /// index and then the pending claims, and heals the index when it succeeds.
  Future<Map<String, dynamic>?> findByReconCode({
    required String ownerUid,
    required String code,
  }) async {
    if (!FirebaseRuntime.initialized) return null;
    final normalised = code.trim().toUpperCase();
    if (normalised.isEmpty) return null;

    try {
      final direct = await _db
          .collection('users')
          .doc(ownerUid)
          .collection('reconCodes')
          .doc(normalised)
          .get();
      if (direct.data() != null) return direct.data();
    } catch (_) {
      // Rules or network rejected the lookup; continue with the fallbacks.
    }

    List<QueryDocumentSnapshot<Map<String, dynamic>>> indexDocs = const [];
    try {
      final indexes = await _db
          .collection('statementIndex')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();
      indexDocs = indexes.docs;
    } catch (_) {
      indexDocs = const [];
    }
    for (final doc in indexDocs) {
      final data = doc.data();
      if ((data['reconCode'] ?? '').toString().toUpperCase() == normalised) {
        final found = {
          'customerName': data['customerName'],
          'token': data['token'],
        };
        await _healCodeIndex(ownerUid, normalised, found);
        return found;
      }
    }

    List<QueryDocumentSnapshot<Map<String, dynamic>>> claimDocs = const [];
    try {
      final claims = await _db
          .collection('paymentClaims')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();
      claimDocs = claims.docs;
    } catch (_) {
      claimDocs = const [];
    }
    for (final doc in claimDocs) {
      final data = doc.data();
      if ((data['reconCode'] ?? '').toString().toUpperCase() == normalised) {
        final found = {
          'customerName': data['customerName'],
          'token': data['token'],
        };
        await _healCodeIndex(ownerUid, normalised, found);
        return found;
      }
    }
    return null;
  }

  /// Writes the missing index entry so the next lookup is a single document
  /// read instead of a scan.
  Future<void> _healCodeIndex(
    String ownerUid,
    String code,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('users')
        .doc(ownerUid)
        .collection('reconCodes')
        .doc(code)
        .set({
      'customerName': data['customerName'],
      'token': data['token'],
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  String linkFor(String token) {
    const origin = String.fromEnvironment(
      'APP_ORIGIN',
      defaultValue: 'https://changvui.github.io/smartpayla/',
    );
    final base = origin.endsWith('/') ? origin : '$origin/';
    return '$base?s=$token';
  }
}
