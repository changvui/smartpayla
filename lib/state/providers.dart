import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction; 

import '../data/firebase_config.dart';
import '../data/firestore_transaction_repository.dart';
import '../data/transaction_repository.dart';
import '../models/reminder.dart';
import '../models/transaction.dart';
import '../models/customer.dart'; 
import '../services/cloud_sync_service.dart';
import '../services/reminder_service.dart';
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
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    state = AsyncData(await _repo.getAll());
    unawaited(_cloud.delete(id));
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
  });

  final double commissionRate;
  final ReminderTone defaultTone;

  double get commissionPercent => commissionRate * 100;

  AppSettings copyWith({
    double? commissionRate,
    ReminderTone? defaultTone,
  }) {
    return AppSettings(
      commissionRate: commissionRate ?? this.commissionRate,
      defaultTone: defaultTone ?? this.defaultTone,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _commissionKey = 'smartpayla_commission_rate';
  static const _toneKey = 'smartpayla_default_tone';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      commissionRate: prefs.getDouble(_commissionKey) ?? 0.05,
      defaultTone:
          ReminderToneX.fromName(prefs.getString(_toneKey) ?? 'formal'),
    );
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

final reminderServiceProvider = Provider<ReminderService>((ref) {
  return ReminderService();
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
class CustomerNotifier extends AsyncNotifier<List<Customer>> {
  String get _userId => ref.read(dataOwnerProvider);

  CollectionReference get _customersRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_userId)
      .collection('customers');

  @override
  Future<List<Customer>> build() async {
    ref.watch(dataOwnerProvider);
    try {
      final snapshot = await _customersRef.get();
      return snapshot.docs
          .map((doc) => Customer.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint("Error fetching customers: $e");
      return [];
    }
  }

  Future<void> addCustomer(Customer customer) async {
    try {
      final docRef = await _customersRef.add(customer.toMap());
      final newCustomer = Customer(
        id: docRef.id,
        name: customer.name,
        phone: customer.phone,
        address: customer.address,
      );
      state = AsyncData([...(state.value ?? []), newCustomer]);
    } catch (e) {
      debugPrint("Error adding customer: $e");
      rethrow; 
    }
  }

  Future<void> updateCustomer(String id, Customer customer) async {
    try {
      await _customersRef.doc(id).update(customer.toMap());
      final updatedList = (state.value ?? []).map((c) => c.id == id ? customer : c).toList();
      state = AsyncData(updatedList);
    } catch (e) {
      debugPrint("Error updating customer: $e");
      rethrow;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await _customersRef.doc(id).delete();
      final updatedList = (state.value ?? []).where((c) => c.id != id).toList();
      state = AsyncData(updatedList);
    } catch (e) {
      debugPrint("Error deleting customer: $e");
      rethrow;
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