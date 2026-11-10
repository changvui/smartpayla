import '../data/firestore_transaction_repository.dart';
import '../data/transaction_repository.dart';
import '../models/transaction.dart';

enum SyncStatus { localOnly, syncing, synced, error }

/// Offline-first sync for the transaction module.
///
/// Local storage is the cache. Firestore is the remote source when configured.
/// Pull merges by `updatedAt`; every local write is pushed in the background.
class CloudSyncService {
  CloudSyncService({
    required this.local,
    this.remote,
    this.onStatus,
  });

  final LocalTransactionRepository local;
  final FirestoreTransactionRepository? remote;
  final void Function(SyncStatus status)? onStatus;

  bool get enabled => remote != null;

  Future<List<Transaction>> pull() async {
    final cloud = remote;
    if (cloud == null) {
      onStatus?.call(SyncStatus.localOnly);
      return local.getAll();
    }

    onStatus?.call(SyncStatus.syncing);
    try {
      final remoteItems = await cloud.getAll();
      final localItems = await local.getAll();
      final merged = <String, Transaction>{};

      for (final item in localItems) {
        merged[item.id] = item;
      }
      for (final item in remoteItems) {
        final existing = merged[item.id];
        if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
          merged[item.id] = item;
        }
      }

      final values = merged.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await local.replaceAll(values);
      await cloud.replaceAll(values);
      onStatus?.call(SyncStatus.synced);
      return values;
    } catch (_) {
      onStatus?.call(SyncStatus.error);
      return local.getAll();
    }
  }

  Stream<List<Transaction>> watch() {
    final cloud = remote;
    if (cloud == null) return const Stream.empty();
    return cloud.watchAll();
  }

  Future<void> push(Transaction transaction) async {
    final cloud = remote;
    if (cloud == null) return;
    onStatus?.call(SyncStatus.syncing);
    try {
      await cloud.save(transaction);
      onStatus?.call(SyncStatus.synced);
    } catch (_) {
      onStatus?.call(SyncStatus.error);
    }
  }

  Future<void> pushAll(List<Transaction> transactions) async {
    final cloud = remote;
    if (cloud == null) return;
    onStatus?.call(SyncStatus.syncing);
    try {
      await cloud.replaceAll(transactions);
      onStatus?.call(SyncStatus.synced);
    } catch (_) {
      onStatus?.call(SyncStatus.error);
    }
  }

  Future<void> delete(String id) async {
    final cloud = remote;
    if (cloud == null) return;
    onStatus?.call(SyncStatus.syncing);
    try {
      await cloud.delete(id);
      onStatus?.call(SyncStatus.synced);
    } catch (_) {
      onStatus?.call(SyncStatus.error);
    }
  }

  Future<void> clear() async {
    final cloud = remote;
    if (cloud == null) return;
    onStatus?.call(SyncStatus.syncing);
    try {
      await cloud.clear();
      onStatus?.call(SyncStatus.synced);
    } catch (_) {
      onStatus?.call(SyncStatus.error);
    }
  }
}
