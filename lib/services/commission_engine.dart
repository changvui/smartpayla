import '../models/transaction.dart';

class CommissionLine {
  const CommissionLine({
    required this.transaction,
    required this.rate,
    required this.commission,
  });

  final Transaction transaction;
  final double rate;
  final double commission;
}

class CommissionReport {
  const CommissionReport({
    required this.rate,
    required this.lines,
    required this.earned,
    required this.potential,
    required this.paidCount,
    required this.openCount,
  });

  final double rate;
  final List<CommissionLine> lines;

  /// Commission on fully paid transactions.
  final double earned;

  /// Commission that would be earned if every open transaction is paid.
  final double potential;

  final int paidCount;
  final int openCount;

  double get totalSales =>
      lines.fold<double>(0, (sum, line) => sum + line.transaction.totalAmount);
}

/// Pure commission calculation. Kept separate from widgets so the business
/// rule is testable and can be reused by the partner integration bridge.
class CommissionEngine {
  const CommissionEngine();

  CommissionReport build({
    required List<Transaction> transactions,
    required double rate,
    DateTime? month,
  }) {
    final safeRate = rate.clamp(0.0, 1.0);
    final filtered = transactions.where((t) {
      if (month == null) return true;
      final date = t.billDate;
      return date.year == month.year && date.month == month.month;
    }).toList();

    final paid = filtered.where((t) => t.isPaid).toList();
    final open = filtered.where((t) => t.isOpen).toList();

    final lines = paid
        .map(
          (t) => CommissionLine(
            transaction: t,
            rate: safeRate,
            commission: t.totalAmount * safeRate,
          ),
        )
        .toList()
      ..sort(
          (a, b) => b.transaction.billDate.compareTo(a.transaction.billDate));

    final earned = lines.fold<double>(0, (sum, line) => sum + line.commission);
    final potential =
        open.fold<double>(0, (sum, t) => sum + t.totalAmount * safeRate);

    return CommissionReport(
      rate: safeRate,
      lines: lines,
      earned: earned,
      potential: potential,
      paidCount: paid.length,
      openCount: open.length,
    );
  }

  /// Month keys (yyyy-MM) that contain at least one transaction, newest first.
  static List<DateTime> monthsIn(List<Transaction> transactions) {
    final map = <String, DateTime>{};
    for (final t in transactions) {
      final d = t.billDate;
      final month = DateTime(d.year, d.month);
      map['${d.year}-${d.month.toString().padLeft(2, '0')}'] = month;
    }
    final months = map.values.toList()..sort((a, b) => b.compareTo(a));
    return months;
  }
}
