import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart'; 

import '../data/firebase_config.dart';
import '../data/firestore_transaction_repository.dart';
import '../data/transaction_repository.dart';
import '../models/payment.dart';
import '../models/reminder.dart';
import '../models/transaction.dart';
import '../models/customer.dart'; 
import '../services/cloud_sync_service.dart';
import '../services/reminder_service.dart';
import '../services/payment_service.dart';
import '../services/statement_service.dart';
import 'auth_provider.dart';

/// Overridden in main() after SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final transactionRepositoryProvider =
    Provider<LocalTransactionRepository>((ref) {
  return LocalTransactionRepository(ref.watch(sharedPreferencesProvider));
});

final syncStatusProvider = StateProvider<SyncStatus>((ref) {
  return FirebaseRuntime.initialized && FirebaseConfig.configured
      ? SyncStatus.syncing
      : SyncStatus.localOnly;
});

/// Who owns the Firestore data: the signed-in Firebase user, otherwise the
/// test-mode fallback (`APP_USER_ID`, default `demo-agent`).
///
/// This has to be watched, not read once: signing in or out must move the
/// repository to the new uid. Capturing the uid at provider-creation time was
/// why records created after login kept landing under `users/demo-agent`.
final dataOwnerProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user != null && user.uid.isNotEmpty) return user.uid;
  return FirebaseConfig.demoUserId;
});

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final local = ref.watch(transactionRepositoryProvider);
  final owner = ref.watch(dataOwnerProvider);
  final remote = FirebaseRuntime.initialized && FirebaseConfig.configured
      ? FirestoreTransactionRepository(userId: owner)
      : null;
  return CloudSyncService(
    local: local,
    remote: remote,
    onStatus: (status) {
      ref.read(syncStatusProvider.notifier).state = status;
    },
  );
});

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  TransactionRepository get _repo => ref.read(transactionRepositoryProvider);

  CloudSyncService get _cloud => ref.read(cloudSyncServiceProvider);

  StreamSubscription<List<Transaction>>? _subscription;
  bool _disposed = false;

  @override
  Future<List<Transaction>> build() async {
    // Rebuild (and re-subscribe) whenever the signed-in user changes, so the
    // ledger follows the account instead of the uid captured at startup.
    ref.watch(dataOwnerProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
      _subscription = null;
    });
    final initial = await _repo.getAll();
    Future.microtask(_startCloud);
    return initial;
  }

  void _startCloud() {
    final cloud = _cloud;
    if (!cloud.enabled) return;

    _subscription = cloud.watch().listen(
      (items) async {
        await cloud.local.replaceAll(items);
        if (_disposed) return;
        state = AsyncData(await cloud.local.getAll());
      },
      onError: (_) {
        if (_disposed) return;
        ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      },
    );

    cloud.pull().then((items) {
      if (_disposed) return;
      state = AsyncData(items);
    });
  }

  Future<void> refresh() async {
    final cloud = _cloud;
    if (cloud.enabled) {
      state = AsyncData(await cloud.pull());
    } else {
      state = AsyncData(await _repo.getAll());
    }
  }

  Future<void> save(Transaction transaction) async {
    await _repo.save(transaction);
    state = AsyncData(await _repo.getAll());
    unawaited(_cloud.push(transaction));
    // The customer page is a published snapshot: republish it so a bill added
    // after the link was sent shows up without pressing Collect again.
    unawaited(_syncStatement(transaction.customerName));
  }

  Future<void> delete(String id) async {
    final removed = state.valueOrNull?.where((t) => t.id == id).firstOrNull;
    await _repo.delete(id);
    state = AsyncData(await _repo.getAll());
    unawaited(_cloud.delete(id));
    if (removed != null) unawaited(_syncStatement(removed.customerName));
  }

  /// Refreshes the public statement for one customer, ignoring failures: a
  /// statement that cannot be refreshed must never block saving a bill.
  Future<void> _syncStatement(String customerName) async {
    if (!FirebaseRuntime.initialized) return;
    try {
      final items = state.valueOrNull ?? const <Transaction>[];
      final open = items
          .where((t) => t.customerName == customerName && t.isOpen)
          .toList();
      final owner = ref.read(dataOwnerProvider);
      final payments = ref.read(paymentServiceProvider);
      final byTransaction = <String, List<Payment>>{};
      for (final bill in open) {
        byTransaction[bill.id] = await payments.forTransaction(owner, bill.id);
      }
      await ref
          .read(statementServiceProvider)
          .publish(
            ownerUid: owner,
            customerName: customerName,
            openBills: open,
            paymentsByTransaction: byTransaction,
            settings: ref.read(settingsProvider),
            agentPhone: '',
          );
    } catch (_) {
      // Offline or rules not published: the link is refreshed next time.
    }
  }

  Future<void> clear() async {
    await _repo.clear();
    state = const AsyncData([]);
    unawaited(_cloud.clear());
  }

  Future<bool> seedDemo() async {
    final added = await _repo.seedDemo();
    final items = await _repo.getAll();
    state = AsyncData(items);
    if (added) unawaited(_cloud.pushAll(items));
    return added;
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
  TransactionsNotifier.new,
);

class AppSettings {
  const AppSettings({
    required this.commissionRate,
    this.defaultTone = ReminderTone.formal,
    this.shopName = 'SmartPayLA',
    this.payeeName = '',
    this.bankNote = '',
    this.paymentQr,
  });

  final double commissionRate;
  final ReminderTone defaultTone;

  /// Shown at the top of the customer statement.
  final String shopName;

  /// Name that appears on the DuitNow transfer, e.g. "Kedai Ah Seng".
  final String payeeName;

  /// Free text such as "Maybank 1234-5678-9012".
  final String bankNote;

  /// The agent's DuitNow QR, stored as a data URI so it travels with the
  /// statement snapshot. Null until the agent uploads one.
  final String? paymentQr;

  double get commissionPercent => commissionRate * 100;

  bool get hasPaymentDetails =>
      (paymentQr != null && paymentQr!.isNotEmpty) || bankNote.isNotEmpty;

  AppSettings copyWith({
    double? commissionRate,
    ReminderTone? defaultTone,
    String? shopName,
    String? payeeName,
    String? bankNote,
    String? paymentQr,
    bool clearQr = false,
  }) {
    return AppSettings(
      commissionRate: commissionRate ?? this.commissionRate,
      defaultTone: defaultTone ?? this.defaultTone,
      shopName: shopName ?? this.shopName,
      payeeName: payeeName ?? this.payeeName,
      bankNote: bankNote ?? this.bankNote,
      paymentQr: clearQr ? null : (paymentQr ?? this.paymentQr),
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _commissionKey = 'smartpayla_commission_rate';
  static const _toneKey = 'smartpayla_default_tone';
  static const _shopKey = 'smartpayla_shop_name';
  static const _payeeKey = 'smartpayla_payee_name';
  static const _bankKey = 'smartpayla_bank_note';
  static const _qrKey = 'smartpayla_payment_qr';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // The payment details live in Firestore so the QR survives a new browser,
    // another device, or an app reinstall. Local storage stays as a cache.
    Future.microtask(_hydratePaymentFromCloud);
    return AppSettings(
      commissionRate: prefs.getDouble(_commissionKey) ?? 0.05,
      defaultTone:
          ReminderToneX.fromName(prefs.getString(_toneKey) ?? 'formal'),
      shopName: prefs.getString(_shopKey) ?? 'SmartPayLA',
      payeeName: prefs.getString(_payeeKey) ?? '',
      bankNote: prefs.getString(_bankKey) ?? '',
      paymentQr: prefs.getString(_qrKey),
    );
  }

  DocumentReference<Map<String, dynamic>>? get _paymentDoc {
    if (!FirebaseRuntime.initialized) return null;
    final owner = ref.read(dataOwnerProvider);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(owner)
        .collection('settings')
        .doc('payment');
  }

  /// Pulls the saved QR / payee details from Firestore into the local state.
  Future<void> _hydratePaymentFromCloud() async {
    final doc = _paymentDoc;
    if (doc == null) return;
    try {
      final snapshot = await doc.get();
      final data = snapshot.data();
      if (data == null) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final shop = (data['shopName'] ?? state.shopName).toString();
      final payee = (data['payeeName'] ?? state.payeeName).toString();
      final bank = (data['bankNote'] ?? state.bankNote).toString();
      final qr = data['paymentQr']?.toString();
      await prefs.setString(_shopKey, shop);
      await prefs.setString(_payeeKey, payee);
      await prefs.setString(_bankKey, bank);
      if (qr != null) await prefs.setString(_qrKey, qr);
      state = state.copyWith(
        shopName: shop,
        payeeName: payee,
        bankNote: bank,
        paymentQr: qr,
      );
    } catch (_) {
      // Offline or rules not published: the local cache is used.
    }
  }

  Future<void> setCommissionRate(double rate) async {
    final safe = rate.clamp(0.0, 1.0);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_commissionKey, safe);
    state = state.copyWith(commissionRate: safe);
  }

  Future<void> setDefaultTone(ReminderTone tone) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_toneKey, tone.name);
    state = state.copyWith(defaultTone: tone);
  }

  Future<void> setPaymentDetails({
    String? shopName,
    String? payeeName,
    String? bankNote,
    String? paymentQr,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (shopName != null) await prefs.setString(_shopKey, shopName);
    if (payeeName != null) await prefs.setString(_payeeKey, payeeName);
    if (bankNote != null) await prefs.setString(_bankKey, bankNote);
    if (paymentQr != null) await prefs.setString(_qrKey, paymentQr);
    state = state.copyWith(
      shopName: shopName,
      payeeName: payeeName,
      bankNote: bankNote,
      paymentQr: paymentQr,
    );
    await _pushPaymentToCloud();
    await _refreshAllStatements();
  }

  /// Re-publishes every open statement, so a QR uploaded now appears on links
  /// that were created before the upload.
  Future<void> _refreshAllStatements() async {
    try {
      final transactions =
          ref.read(transactionsProvider).valueOrNull ?? const <Transaction>[];
      final open = transactions.where((t) => t.isOpen).toList();
      if (open.isEmpty) return;

      final byCustomer = <String, List<Transaction>>{};
      for (final bill in open) {
        byCustomer.putIfAbsent(bill.customerName, () => []).add(bill);
      }

      final owner = ref.read(dataOwnerProvider);
      final payments = ref.read(paymentServiceProvider);
      final statements = ref.read(statementServiceProvider);
      for (final entry in byCustomer.entries) {
        final byTransaction = <String, List<Payment>>{};
        for (final bill in entry.value) {
          byTransaction[bill.id] = await payments.forTransaction(owner, bill.id);
        }
        await statements.publish(
          ownerUid: owner,
          customerName: entry.key,
          openBills: entry.value,
          paymentsByTransaction: byTransaction,
          settings: state,
          agentPhone: '',
        );
      }
    } catch (_) {
      // Offline or rules not published: links refresh on the next save.
    }
  }

  /// Mirrors the payment details into Firestore so every device (and every
  /// statement generated later) sees the same QR.
  Future<void> _pushPaymentToCloud() async {
    final doc = _paymentDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'shopName': state.shopName,
        'payeeName': state.payeeName,
        'bankNote': state.bankNote,
        'paymentQr': state.paymentQr,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Keep the local copy; the next save retries.
    }
  }

  Future<void> clearPaymentQr() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_qrKey);
    state = state.copyWith(clearQr: true);
    await _pushPaymentToCloud();
  }
}

/// The month the dashboard reports on. `null` means "all time".
///
/// Defaults to the current month: an agent opening the app in the morning wants
/// this month's collections, not a lifetime total, and the selector is one tap
/// away when they need a different period.
final dashboardMonthProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

final reminderServiceProvider = Provider<ReminderService>((ref) {
  return ReminderService();
});

/// Builds the public statement snapshots the customer link points at.
final statementServiceProvider = Provider<StatementService>((ref) {
  return StatementService();
});

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService();
});

/// Payments a customer declared from the statement link. Drives the pending
/// badge on the dashboard and the confirmation queue.
final pendingClaimsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      final owner = ref.watch(dataOwnerProvider);
      return ref.watch(paymentServiceProvider).pendingClaims(owner);
    });

class ReminderHistoryNotifier extends AsyncNotifier<List<ReminderRecord>> {
  static const _key = 'smartpayla_reminders_v1';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Future<List<ReminderRecord>> build() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map>()
          .map((e) => ReminderRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> add(ReminderRecord record) async {
    final items = [...(state.valueOrNull ?? <ReminderRecord>[])];
    items.insert(0, record);
    final trimmed = items.take(50).toList();
    await _prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    state = const AsyncData([]);
  }
}

final reminderHistoryProvider =
    AsyncNotifierProvider<ReminderHistoryNotifier, List<ReminderRecord>>(
  ReminderHistoryNotifier.new,
);

// ==========================================
// KERRY'S MODULES
// ==========================================

// 1. Customer Management
/// Customer profiles, offline-first.
///
/// Customers were Firestore-only, which made the page look "not synced" in two
/// situations that both look identical to a user: signed out (writes denied by
/// the rules, read returns an empty list) and offline (the read throws, the
/// error was swallowed and an empty list was shown). The notifier now keeps a
/// local cache, applies every change to it immediately, and queues the cloud
/// write so it can be retried - the same shape the ledger already uses.
class CustomerNotifier extends AsyncNotifier<List<Customer>> {
  // Scoped to the owner: two accounts on one device must not see each other's
  // customers, and a queued write belongs to the account that made it.
  String get _cacheKey => 'customers_cache_v2_$_userId';
  String get _pendingKey => 'customers_pending_v2_$_userId';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  /// The live session uid: Firestore rules compare the path with
  /// `request.auth.uid`, so a cached fallback would write to users/demo-agent
  /// and be rejected.
  String get _userId {
    final live = FirebaseAuth.instance.currentUser?.uid;
    if (live != null && live.isNotEmpty) return live;
    return ref.read(dataOwnerProvider);
  }

  bool get _cloudEnabled =>
      FirebaseRuntime.initialized &&
      FirebaseConfig.configured &&
      (FirebaseAuth.instance.currentUser?.uid.isNotEmpty ?? false);

  CollectionReference get _customersRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_userId)
      .collection('customers');

  List<Customer> _readCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((entry) {
        final map = Map<String, dynamic>.from(entry);
        return Customer.fromMap(
          (map['id'] ?? '').toString(),
          Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeCache(List<Customer> customers) async {
    await _prefs.setString(
      _cacheKey,
      jsonEncode(
        customers
            .map((c) => {'id': c.id, 'data': c.toMap()})
            .toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _readPending() {
    final raw = _prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePending(List<Map<String, dynamic>> pending) async {
    if (pending.isEmpty) {
      await _prefs.remove(_pendingKey);
    } else {
      await _prefs.setString(_pendingKey, jsonEncode(pending));
    }
  }

  Future<void> _enqueue(String op, String id, Map<String, dynamic> data) async {
    if (!_cloudEnabled) return;
    final pending = _readPending()
      ..add({'op': op, 'id': id, 'data': data, 'at': DateTime.now().toIso8601String()});
    await _writePending(pending);
  }

  /// Replays queued writes. Anything that still fails stays queued.
  Future<void> _flushPending() async {
    final pending = _readPending();
    if (pending.isEmpty || !_cloudEnabled) return;
    final remaining = <Map<String, dynamic>>[];
    for (final entry in pending) {
      final op = (entry['op'] ?? '').toString();
      final id = (entry['id'] ?? '').toString();
      try {
        if (op == 'delete') {
          await _customersRef.doc(id).delete();
        } else {
          final data = Map<String, dynamic>.from(entry['data'] as Map? ?? {});
          await _customersRef.doc(id).set(data, SetOptions(merge: true));
        }
      } catch (error) {
        debugPrint('Customer sync retry failed: $error');
        remaining.add(entry);
      }
    }
    await _writePending(remaining);
  }

  @override
  Future<List<Customer>> build() async {
    ref.watch(dataOwnerProvider);
    final cached = _readCache();
    if (!_cloudEnabled) return cached;

    try {
      await _flushPending();
      final snapshot = await _customersRef.get();
      final remote = snapshot.docs
          .map((doc) => Customer.fromMap(
              doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      await _writeCache(remote);
      return remote;
    } catch (error) {
      // Keep whatever the device already knows instead of showing an empty list.
      debugPrint('Customer fetch failed, using the cache: $error');
      return cached;
    }
  }

  Future<void> addCustomer(Customer customer) async {
    // A client id keeps the record stable across a retry: Firestore's auto id
    // would create a second row if the first write never arrived.
    final id = customer.id.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : customer.id;
    final created = Customer(
      id: id,
      name: customer.name,
      phone: customer.phone,
      address: customer.address,
    );

    final items = [...(state.valueOrNull ?? const <Customer>[]), created];
    state = AsyncData(items);
    await _writeCache(items);

    if (!_cloudEnabled) {
      await _enqueue('set', id, created.toMap());
      return;
    }
    try {
      await _customersRef.doc(id).set(created.toMap());
    } catch (error) {
      debugPrint('Customer save queued: $error');
      await _enqueue('set', id, created.toMap());
    }
  }

  Future<void> updateCustomer(String id, Customer customer) async {
    final items = (state.valueOrNull ?? const <Customer>[])
        .map((c) => c.id == id ? customer : c)
        .toList();
    state = AsyncData(items);
    await _writeCache(items);

    if (!_cloudEnabled) {
      await _enqueue('set', id, customer.toMap());
      return;
    }
    try {
      await _customersRef.doc(id).set(customer.toMap(), SetOptions(merge: true));
    } catch (error) {
      debugPrint('Customer update queued: $error');
      await _enqueue('set', id, customer.toMap());
    }
  }

  Future<void> deleteCustomer(String id) async {
    final items =
        (state.valueOrNull ?? const <Customer>[]).where((c) => c.id != id).toList();
    state = AsyncData(items);
    await _writeCache(items);

    if (!_cloudEnabled) {
      await _enqueue('delete', id, const {});
      return;
    }
    try {
      await _customersRef.doc(id).delete();
    } catch (error) {
      debugPrint('Customer delete queued: $error');
      await _enqueue('delete', id, const {});
    }
  }

  /// Pull the cloud copy again, e.g. from the refresh gesture.
  Future<void> refresh() async {
    final cached = _readCache();
    if (!_cloudEnabled) {
      state = AsyncData(cached);
      return;
    }
    try {
      await _flushPending();
      final snapshot = await _customersRef.get();
      final remote = snapshot.docs
          .map((doc) => Customer.fromMap(
              doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      await _writeCache(remote);
      state = AsyncData(remote);
    } catch (error) {
      debugPrint('Customer refresh failed: $error');
      state = AsyncData(cached);
    }
  }
}
final customerProvider = AsyncNotifierProvider<CustomerNotifier, List<Customer>>(() {
  return CustomerNotifier();
});

// 2. Theme Provider (Dark Mode)
final themeModeProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('smartpayla_theme_dark') ?? false;
});