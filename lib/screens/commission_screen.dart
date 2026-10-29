import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/commission_engine.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CommissionScreen extends ConsumerStatefulWidget {
  const CommissionScreen({super.key});

  @override
  ConsumerState<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends ConsumerState<CommissionScreen> {
  static const _allTime = 'all';
  String _monthKey = _allTime;

  @override
  Widget build(BuildContext context) {
    final transactions =
        ref.watch(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final settings = ref.watch(settingsProvider);
    final months = CommissionEngine.monthsIn(transactions);

    if (_monthKey != _allTime && !months.any((m) => _key(m) == _monthKey)) {
      _monthKey = _allTime;
    }

    final selectedMonth = _monthKey == _allTime
        ? null
        : months.firstWhere((m) => _key(m) == _monthKey);

    final report = const CommissionEngine().build(
      transactions: transactions,
      rate: settings.commissionRate,
      month: selectedMonth,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commission'),
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'COMMISSION EARNED',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      money(report.earned),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${percent(settings.commissionRate)} on ${report.paidCount} paid ${report.paidCount == 1 ? 'sale' : 'sales'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Potential',
                    value: money(report.potential),
                    hint: '${report.openCount} open sales',
                    icon: Icons.pending_actions_outlined,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(
                    label: 'Paid sales',
                    value: '${report.paidCount}',
                    hint: 'Fully paid only',
                    icon: Icons.verified_outlined,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: SectionHeader(title: 'Commission by month'),
                ),
                SizedBox(
                  width: 165,
                  child: DropdownButtonFormField<String>(
                    initialValue: _monthKey,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: _allTime,
                        child: Text('All time'),
                      ),
                      for (final month in months)
                        DropdownMenuItem(
                          value: _key(month),
                          child: Text(DateFormat('MMM yyyy').format(month)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _monthKey = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (report.lines.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.percent_rounded,
                      size: 34,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selectedMonth == null
                          ? 'No paid sales yet'
                          : 'No paid sales in ${DateFormat('MMMM yyyy').format(selectedMonth)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Commission is counted only when a transaction is fully paid.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              )
            else
              ...report.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor:
                              AppColors.green.withValues(alpha: 0.10),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: AppColors.green,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.transaction.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${money(line.transaction.totalAmount)} sale · ${shortDate(line.transaction.billDate)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              money(line.commission),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green,
                              ),
                            ),
                            Text(
                              percent(line.rate),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'The rate is configured in Settings. Change it there to recalculate every month instantly.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _key(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
