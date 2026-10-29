import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';

abstract class TransactionRepository {
  Future<List<Transaction>> getAll();
  Future<void> save(Transaction transaction);
  Future<void> delete(String id);
  Future<void> clear();
  Future<bool> seedDemo();
}

/// Increment 1 stores data on the device. The rest of the app talks only to
/// [TransactionRepository], so Increment 2 can add a Firestore implementation
/// without changing the screens.
class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this._prefs);

  static const _storageKey = 'smartpayla_transactions_v1';
  final SharedPreferences _prefs;

  @override
  Future<List<Transaction>> getAll() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map>()
          .map((e) => Transaction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (_) {
      // A corrupt local cache should not brick the app.
      return [];
    }
  }

  @override
  Future<void> save(Transaction transaction) async {
    final items = await getAll();
    final index = items.indexWhere((e) => e.id == transaction.id);
    if (index >= 0) {
      items[index] = transaction;
    } else {
      items.add(transaction);
    }
    await _write(items);
  }

  @override
  Future<void> delete(String id) async {
    final items = await getAll();
    items.removeWhere((e) => e.id == id);
    await _write(items);
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_storageKey);
  }

  /// Replaces the local cache with the merged cloud/local list.
  Future<void> replaceAll(List<Transaction> items) async {
    await _write(items);
  }

  Future<void> _write(List<Transaction> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }

  @override
  Future<bool> seedDemo() async {
    final existing = await getAll();
    if (existing.isNotEmpty) return false;

    final now = DateTime.now();
    const uuid = Uuid();
    final demo = <Transaction>[
      Transaction(
        id: uuid.v4(),
        customerName: 'Ahmad Faizal',
        itemDescription: 'Catering order — 80 pax',
        totalAmount: 1200,
        advancePaid: 400,
        dueDate: now.subtract(const Duration(days: 12)),
        status: PaymentStatus.partial,
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      Transaction(
        id: uuid.v4(),
        customerName: 'Siti Nurhaliza',
        itemDescription: 'Tupperware set — 3 boxes',
        totalAmount: 350,
        advancePaid: 0,
        dueDate: now.subtract(const Duration(days: 45)),
        status: PaymentStatus.unpaid,
        createdAt: now.subtract(const Duration(days: 50)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      Transaction(
        id: uuid.v4(),
        customerName: 'Lim Wei Jie',
        itemDescription: 'Custom curtain — living room',
        totalAmount: 880,
        advancePaid: 880,
        dueDate: now.subtract(const Duration(days: 6)),
        status: PaymentStatus.paid,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 1)),
        finishDate: now.subtract(const Duration(days: 8)),
        invoiceNumber: 'INV-2026-041',
      ),
      Transaction(
        id: uuid.v4(),
        customerName: 'Rajesh Kumar',
        itemDescription: 'Event lighting package',
        totalAmount: 2400,
        advancePaid: 1000,
        dueDate: now.subtract(const Duration(days: 75)),
        status: PaymentStatus.partial,
        createdAt: now.subtract(const Duration(days: 90)),
        updatedAt: now.subtract(const Duration(days: 10)),
        cashBillNumber: 'CB-0912',
      ),
      Transaction(
        id: uuid.v4(),
        customerName: 'Nur Aisyah',
        itemDescription: 'Seminar package — 40 pax',
        totalAmount: 600,
        advancePaid: 0,
        dueDate: now.add(const Duration(days: 12)),
        status: PaymentStatus.unpaid,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    ];
    await _write(demo);
    return true;
  }
}
