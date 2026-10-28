import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/transaction_repository.dart';
import '../models/transaction.dart';

/// Overridden in main() after SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return LocalTransactionRepository(ref.watch(sharedPreferencesProvider));
});

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  TransactionRepository get _repo => ref.read(transactionRepositoryProvider);

  @override
  Future<List<Transaction>> build() => _repo.getAll();

  Future<void> refresh() async {
    state = AsyncData(await _repo.getAll());
  }

  Future<void> save(Transaction transaction) async {
    await _repo.save(transaction);
    state = AsyncData(await _repo.getAll());
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    state = AsyncData(await _repo.getAll());
  }

  Future<void> clear() async {
    await _repo.clear();
    state = const AsyncData([]);
  }

  Future<bool> seedDemo() async {
    final added = await _repo.seedDemo();
    state = AsyncData(await _repo.getAll());
    return added;
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
  TransactionsNotifier.new,
);

class AppSettings {
  const AppSettings({required this.commissionRate});

  /// 0.05 = 5%.
  final double commissionRate;

  double get commissionPercent => commissionRate * 100;
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _commissionKey = 'smartpayla_commission_rate';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getDouble(_commissionKey);
    return AppSettings(commissionRate: stored ?? 0.05);
  }

  Future<void> setCommissionRate(double rate) async {
    final safe = rate.clamp(0.0, 1.0);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_commissionKey, safe);
    state = AppSettings(commissionRate: safe);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
