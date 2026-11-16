import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../data/firebase_config.dart';
import '../models/payment.dart';
import '../models/transaction.dart';
import 'payment_ledger.dart';

/// Writes payments and keeps the transaction cache in step.
///
/// The payment documents are the source of truth; `advancePaid` and `status` on
/// the transaction are a cache that is recomputed here every time a payment is
/// added or voided. Nothing in the interface may write those two fields.
class PaymentService {
  PaymentService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Firestore rules compare the path uid with `request.auth.uid`, so writes must
  /// use the live session uid rather than a cached fallback.
  String _owner(String fallback) {
    final live = FirebaseAuth.instance.currentUser?.uid;
    return (live == null || live.isEmpty) ? fallback : live;
  }

  CollectionReference<Map<String, dynamic>> _payments(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('payments');

  DocumentReference<Map<String, dynamic>> _txn(String ownerUid, String id) =>
      _db.collection('users').doc(ownerUid).collection('transactions').doc(id);

  Future<List<Payment>> forTransaction(String ownerUid, String txnId) async {
    if (!FirebaseRuntime.initialized) return [];
    ownerUid = _owner(ownerUid);
    final snapshot = await _payments(
      ownerUid,
    ).where('transactionId', isEqualTo: txnId).get();
    final items = snapshot.docs.map((d) => Payment.fromJson(d.data())).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return items;
  }

  /// Records a payment the agent has already received (cash, or a transfer the
  /// agent has checked). Writes the payment, then recomputes the transaction.
  Future<Payment?> record({
    required String ownerUid,
    required Transaction transaction,
    required double amount,
    required PaymentMethod method,
    String? note,
    String? reference,
    bool declaredByCustomer = false,
    String? proofImage,
  }) async {
    if (!FirebaseRuntime.initialized) return null;
    if (amount <= 0) return null;
    ownerUid = _owner(ownerUid);

    final existing = await forTransaction(ownerUid, transaction.id);

    // A record created before the ledger existed only has `advancePaid`. Turn
    // that number into an opening payment once, so the first real payment does
    // not wipe the history it represents.
    if (existing.isEmpty && transaction.advancePaid > 0) {
      final now = DateTime.now();
      final opening = Payment(
        id: const Uuid().v4(),
        transactionId: transaction.id,
        customerName: transaction.customerName,
        amount: transaction.advancePaid,
        method: PaymentMethod.cash,
        state: PaymentState.confirmed,
        receiptNo: PaymentLedger.newReceiptNo(now),
        paidAt: transaction.createdAt,
        createdAt: now,
        confirmedAt: now,
        note: 'Opening balance',
        openingBalance: true,
      );
      await _payments(ownerUid).doc(opening.id).set(opening.toJson());
      existing.add(opening);
    }

    final paid = PaymentLedger.paidTotal(existing);
    final balance = transaction.totalAmount - paid;
    if (amount > balance + 0.005) return null; // never overpay a bill

    final now = DateTime.now();
    final payment = Payment(
      id: const Uuid().v4(),
      transactionId: transaction.id,
      customerName: transaction.customerName,
      amount: amount,
      method: method,
      state: PaymentState.confirmed,
      receiptNo: PaymentLedger.newReceiptNo(now),
      paidAt: now,
      createdAt: now,
      confirmedAt: now,
      note: note,
      reference: reference,
      declaredByCustomer: declaredByCustomer,
      proofImage: proofImage,
    );

    await _payments(ownerUid).doc(payment.id).set(payment.toJson());
    await _applyBalance(ownerUid, transaction, [...existing, payment]);
    return payment;
  }

  /// Recomputes and stores the cached balance/status of a transaction.
  Future<void> _applyBalance(
    String ownerUid,
    Transaction transaction,
    List<Payment> payments,
  ) async {
    final totals = PaymentLedger.totals(payments, transaction.totalAmount);
    await _txn(ownerUid, transaction.id).update({
      'advancePaid': totals.paid,
      'status': totals.status.name,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Records an incoming transfer that the agent matched manually from the
  /// bank statement, allocating it oldest bill first.
  Future<bool> recordForCustomer({
    required String ownerUid,
    required List<Transaction> transactions,
    required String customerName,
    required double amount,
    String? proofImage,
    String? reference,
  }) async {
    if (amount <= 0) return false;
    ownerUid = _owner(ownerUid);
    final open = transactions
        .where((t) => t.customerName == customerName && t.balanceDue > 0.005)
        .toList();
    if (open.isEmpty) return false;

    final allocation = PaymentLedger.allocateOldestFirst(open, amount);
    final firstId = allocation.keys.isEmpty ? null : allocation.keys.first;
    for (final entry in allocation.entries) {
      final transaction = open.firstWhere((t) => t.id == entry.key);
      await record(
        ownerUid: ownerUid,
        transaction: transaction,
        amount: entry.value,
        method: PaymentMethod.bank,
        note: 'Matched from bank statement',
        reference: reference,
        proofImage: entry.key == firstId ? proofImage : null,
      );
    }
    return true;
  }

  /// Marks a payment as void. The document stays so the audit trail survives.
  Future<void> voidPayment({
    required String ownerUid,
    required Transaction transaction,
    required Payment payment,
    required String reason,
  }) async {
    if (!FirebaseRuntime.initialized) return;
    ownerUid = _owner(ownerUid);
    final now = DateTime.now();
    await _payments(ownerUid).doc(payment.id).update({
      'state': PaymentState.voided.name,
      'voidedAt': now.toIso8601String(),
      'voidReason': reason,
    });
    final remaining = (await forTransaction(ownerUid, transaction.id))
        .where((p) => p.id != payment.id)
        .toList();
    await _applyBalance(ownerUid, transaction, remaining);
  }

  /// Payments the customer declared from the statement page, newest first.
  Stream<List<Map<String, dynamic>>> pendingClaims(String ownerUid) {
    if (!FirebaseRuntime.initialized) {
      return Stream.value(const []);
    }
    ownerUid = _owner(ownerUid);
    return _db
        .collection('paymentClaims')
        .where('ownerUid', isEqualTo: ownerUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((d) => d.data()).toList()
            ..sort(
              (a, b) => (b['declaredAt'] ?? '')
                  .toString()
                  .compareTo((a['declaredAt'] ?? '').toString()),
            ),
        );
  }

  /// Turns a customer claim into a confirmed payment for the oldest open bill
  /// of that customer, then marks the claim as confirmed.
  Future<bool> confirmClaim({
    required String ownerUid,
    required List<Transaction> transactions,
    required Map<String, dynamic> claim,
  }) async {
    if (!FirebaseRuntime.initialized) return false;

    final customerName = (claim['customerName'] ?? '').toString();
    final amount = (claim['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return false;

    // The customer may have selected specific bills; fall back to every open
    // bill when no selection was sent.
    final selectedIds = (claim['billIds'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const <String>{};
    final open = transactions
        .where(
          (t) =>
              t.customerName == customerName &&
              t.balanceDue > 0.005 &&
              (selectedIds.isEmpty || selectedIds.contains(t.id)),
        )
        .toList();
    if (open.isEmpty) return false;

    final proof = claim['proofImage']?.toString();
    final allocation = PaymentLedger.allocateOldestFirst(open, amount);
    final firstId = allocation.keys.isEmpty ? null : allocation.keys.first;
    for (final entry in allocation.entries) {
      final transaction = open.firstWhere((t) => t.id == entry.key);
      await record(
        ownerUid: ownerUid,
        transaction: transaction,
        amount: entry.value,
        method: PaymentMethod.duitnow,
        note: (claim['note'] ?? '').toString(),
        reference: (claim['token'] ?? '').toString(),
        declaredByCustomer: true,
        // The customer's screenshot is stored once, on the first bill paid.
        proofImage: entry.key == firstId ? proof : null,
      );
    }

    await _db.collection('paymentClaims').doc(claim['id']).update({
      'status': 'confirmed',
      'confirmedAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  Future<void> rejectClaim(String claimId) async {
    if (!FirebaseRuntime.initialized) return;
    await _db.collection('paymentClaims').doc(claimId).update({
      'status': 'rejected',
      'confirmedAt': DateTime.now().toIso8601String(),
    });
  }
}
