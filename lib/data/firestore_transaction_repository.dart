import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../models/transaction.dart';

/// Firestore layout: users/{userId}/transactions/{transactionId}
///
/// Dates are stored as ISO strings so the same JSON can move between local
/// storage and Firestore without a second serialization format.
class FirestoreTransactionRepository {
  FirestoreTransactionRepository({
    FirebaseFirestore? firestore,
    required this.userId,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final String userId;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('users').doc(userId).collection('transactions');

  Future<List<Transaction>> getAll() async {
    final snapshot =
        await _collection.orderBy('updatedAt', descending: true).get();
    return snapshot.docs.map(_fromDoc).toList();
  }

  Stream<List<Transaction>> watchAll() {
    return _collection
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  Transaction _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] = data['id'] ?? doc.id;
    return Transaction.fromJson(data);
  }

  Future<void> save(Transaction transaction) async {
    await _collection.doc(transaction.id).set(
          transaction.toJson(),
          SetOptions(merge: true),
        );
  }

  Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }

  Future<void> replaceAll(List<Transaction> transactions) async {
    if (transactions.isEmpty) return;
    final batch = _db.batch();
    for (final transaction in transactions) {
      batch.set(
        _collection.doc(transaction.id),
        transaction.toJson(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> clear() async {
    final snapshot = await _collection.get();
    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
