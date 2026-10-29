import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/firebase_config.dart';
import '../data/firestore_transaction_repository.dart';
import '../data/transaction_repository.dart';
import '../models/reminder.dart';
import '../models/transaction.dart';
import '../services/cloud_sync_service.dart';
import '../services/reminder_service.dart';

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

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final local = ref.watch(transactionRepositoryProvider);
  final remote = FirebaseRuntime.initialized && FirebaseConfig.configured
      ? FirestoreTransactionRepository(userId: FirebaseConfig.userId)
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
    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
    });
    final initial = await _repo.getAll();
    // Do not block the first paint on the network.
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

  /// 0.05 = 5%.
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
