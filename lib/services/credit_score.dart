import 'dart:math' as math;

import '../models/transaction.dart';

/// A customer's payment behaviour, derived only from the ledger.
///
/// The score is deliberately rule-based rather than a language-model output:
/// every point can be explained to the customer ("you were late on two bills"),
/// the result is reproducible, and it works offline. The weights are a product
/// decision, not a mathematical truth, and are documented in the report.
class CustomerCredit {
  const CustomerCredit({
    required this.score,
    required this.band,
    required this.label,
    required this.openBills,
    required this.overdueBills,
    required this.outstanding,
    required this.paidRatio,
    required this.worstOverdueDays,
    required this.punctualityPercent,
  });

  /// 0–100.
  final double score;

  /// A (reliable), B (fair), C (watch), D (high risk).
  final String band;

  /// Short human label used in the badge.
  final String label;

  final int openBills;
  final int overdueBills;
  final double outstanding;
  final double paidRatio;
  final int worstOverdueDays;
  final int punctualityPercent;

  bool get hasHistory => openBills > 0 || paidRatio > 0;

  static CustomerCredit compute(List<Transaction> transactions) {
    if (transactions.isEmpty) {
      return const CustomerCredit(
        score: 0,
        band: '—',
        label: 'No history',
        openBills: 0,
        overdueBills: 0,
        outstanding: 0,
        paidRatio: 0,
        worstOverdueDays: 0,
        punctualityPercent: 0,
      );
    }

    var totalAmount = 0.0;
    var paidAmount = 0.0;
    var outstanding = 0.0;
    var openBills = 0;
    var overdueBills = 0;
    var worstOverdue = 0;
    var paidBills = 0;
    var paidOnTime = 0;
    DateTime? lastActivity;

    for (final txn in transactions) {
      totalAmount += txn.totalAmount;
      paidAmount += txn.advancePaid.clamp(0, txn.totalAmount);
      final balance = txn.balanceDue;
      outstanding += balance;
      if (balance > 0.005) {
        openBills++;
        if (txn.isOverdue) {
          overdueBills++;
          worstOverdue = math.max(worstOverdue, txn.daysOverdue);
        }
      } else {
        paidBills++;
        final finished = txn.finishDate ?? txn.updatedAt;
        if (!finished.isAfter(txn.dueDate)) paidOnTime++;
      }
      final activity = txn.updatedAt;
      if (lastActivity == null || activity.isAfter(lastActivity)) {
        lastActivity = activity;
      }
    }

    final paidRatio = totalAmount <= 0
        ? 0.0
        : (paidAmount / totalAmount).clamp(0.0, 1.0);
    final punctuality = paidBills == 0
        ? (overdueBills == 0 ? 70.0 : 30.0)
        : paidOnTime / paidBills * 100;

    // 1. Punctuality (40%): how often bills were paid by their due date, and how
    //    far the worst open bill has slipped.
    var punctualityScore = punctuality - math.min(40, worstOverdue * 0.5);
    punctualityScore = punctualityScore.clamp(0.0, 100.0);

    // 2. Settlement (30%): share of the money that has actually been collected.
    final settlementScore = (paidRatio * 100).clamp(0.0, 100.0);

    // 3. Recency (20%): a customer who paid recently is behaving better than one
    //    who has been silent for months.
    double recencyScore;
    final daysSince = lastActivity == null
        ? 999
        : DateTime.now().difference(lastActivity).inDays;
    if (daysSince <= 7) {
      recencyScore = 100;
    } else if (daysSince <= 30) {
      recencyScore = 80;
    } else if (daysSince <= 90) {
      recencyScore = 60;
    } else {
      recencyScore = 40;
    }

    // 4. Exposure (10%): a large open balance is a larger risk than a small one.
    final exposureScore = outstanding <= 0.005
        ? 100.0
        : (100 - math.min(50, outstanding / 1000 * 10)).clamp(0.0, 100.0);

    final score = (punctualityScore * 0.40 +
            settlementScore * 0.30 +
            recencyScore * 0.20 +
            exposureScore * 0.10)
        .clamp(0.0, 100.0);

    final (band, label) = switch (score) {
      >= 80 => ('A', 'Reliable'),
      >= 60 => ('B', 'Fair'),
      >= 40 => ('C', 'Watch'),
      _ => ('D', 'High risk'),
    };

    return CustomerCredit(
      score: score,
      band: band,
      label: label,
      openBills: openBills,
      overdueBills: overdueBills,
      outstanding: outstanding,
      paidRatio: paidRatio,
      worstOverdueDays: worstOverdue,
      punctualityPercent: punctuality.round(),
    );
  }

  /// One sentence that explains the score without a language model.
  String get explanation {
    final parts = <String>[];
    if (punctualityPercent >= 80) {
      parts.add('usually pays on time');
    } else if (punctualityPercent >= 50) {
      parts.add('sometimes pays late');
    } else {
      parts.add('has a history of late payment');
    }
    if (worstOverdueDays > 0) {
      parts.add('$worstOverdueDays days behind on the oldest bill');
    }
    if (paidRatio >= 0.7) {
      parts.add('${(paidRatio * 100).round()}% of the value settled');
    } else if (paidRatio > 0) {
      parts.add('only ${(paidRatio * 100).round()}% of the value settled');
    } else {
      parts.add('nothing settled yet');
    }
    return parts.join(', ');
  }
}
