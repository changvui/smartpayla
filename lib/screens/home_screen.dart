import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_badge.dart';
import '../widgets/transaction_tile.dart';
import 'commission_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    this.onOpenTransactions,
    this.onOpenReminders,
  });

  final VoidCallback? onOpenTransactions;
  final VoidCallback? onOpenReminders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTransactions = ref.watch(transactionsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            _LogoMark(),
            SizedBox(width: 10),
            Text('SmartPayLA'),
          ],
        ),
        actions: [
          const SyncBadge(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: asyncTransactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load your ledger',
          message: '$error',
          action: FilledButton(
            onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
            child: const Text('Try again'),
          ),
        ),
        data: (transactions) => _HomeContent(
          transactions: transactions,
          commissionRate: settings.commissionRate,
          onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
          onOpenTransactions: onOpenTransactions,
          onOpenReminders: onOpenReminders,
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.transactions,
    required this.commissionRate,
    required this.onRefresh,
    this.onOpenTransactions,
    this.onOpenReminders,
  });

  final List<Transaction> transactions;
  final double commissionRate;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenTransactions;
  final VoidCallback? onOpenReminders;

  @override
  Widget build(BuildContext context) {
    final open = transactions.where((t) => t.isOpen).toList();
    final paid = transactions.where((t) => t.isPaid).toList();

    final outstanding = open.fold<double>(0, (sum, t) => sum + t.balanceDue);
    final collected = paid.fold<double>(0, (sum, t) => sum + t.totalAmount);
    final commission =
        paid.fold<double>(0, (sum, t) => sum + t.totalAmount * commissionRate);

    final aging = <AgingBucket, double>{
      AgingBucket.current: 0,
      AgingBucket.days31to60: 0,
      AgingBucket.days60plus: 0,
    };
    for (final t in open) {
      aging[t.agingBucket] = (aging[t.agingBucket] ?? 0) + t.balanceDue;
    }

    final recent = transactions.take(3).toList();

    return PageWidth(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const _Greeting(),
            const SizedBox(height: 18),
            _OutstandingCard(
              amount: outstanding,
              openCount: open.length,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Commission earned',
                    value: money(commission),
                    hint: '${percent(commissionRate)} on paid sales',
                    icon: Icons.percent_rounded,
                    accent: AppColors.green,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CommissionScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'Collected',
                    value: money(collected),
                    hint: '${paid.length} paid transactions',
                    icon: Icons.check_circle_outline_rounded,
                    accent: AppColors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Debt aging'),
            _AgingCard(aging: aging, total: outstanding),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Quick actions'),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.add_rounded,
                    label: 'New transaction',
                    filled: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TransactionFormScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Generate reminder',
                    onTap: onOpenReminders ??
                        () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'AI reminders arrive in Increment 4. The transaction ledger is ready first.',
                                ),
                              ),
                            ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: 'Recent transactions',
              actionLabel: transactions.isEmpty ? null : 'See all',
              onAction: onOpenTransactions ??
                  () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Open the Transactions tab to see the full list.'),
                        ),
                      ),
            ),
            if (recent.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 34,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No transactions yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add your first cash bill to start tracking balances.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TransactionFormScreen(),
                        ),
                      ),
                      child: const Text('Add transaction'),
                    ),
                  ],
                ),
              )
            else
              ...recent.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransactionTile(
                    transaction: t,
                    compact: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TransactionDetailScreen(
                          transactionId: t.id,
                          initial: t,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.account_balance_wallet_rounded,
        size: 19,
        color: Colors.white,
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Your field ledger',
                style: TextStyle(
                  fontSize: 24,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const CircleAvatar(
          radius: 21,
          backgroundColor: Colors.white,
          child: Icon(Icons.person_outline_rounded, color: AppColors.primary),
        ),
      ],
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.amount, required this.openCount});

  final double amount;
  final int openCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TOTAL OUTSTANDING',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'MYR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(amount),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                '$openCount open ${openCount == 1 ? 'transaction' : 'transactions'}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AgingCard extends StatelessWidget {
  const _AgingCard({required this.aging, required this.total});

  final Map<AgingBucket, double> aging;
  final double total;

  @override
  Widget build(BuildContext context) {
    final entries = [
      (AgingBucket.current, AppColors.green),
      (AgingBucket.days31to60, AppColors.amber),
      (AgingBucket.days60plus, AppColors.red),
    ];

    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _AgingRow(
              label: entries[i].$1.label,
              amount: aging[entries[i].$1] ?? 0,
              total: total,
              color: entries[i].$2,
            ),
            if (i != entries.length - 1) const SizedBox(height: 12),
          ],
          if (total == 0)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No outstanding balance — nice work.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgingRow extends StatelessWidget {
  const _AgingRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String label;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              money(amount),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
      ],
    );

    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: AppColors.border),
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: child,
    );
  }
}
