import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'transaction_form_screen.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    this.initial,
  });

  final String transactionId;
  final Transaction? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transactionsProvider);
    final transactions = async.valueOrNull ?? const <Transaction>[];
    Transaction? transaction;
    for (final t in transactions) {
      if (t.id == transactionId) {
        transaction = t;
        break;
      }
    }
    transaction ??= initial;

    if (transaction == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Transaction not found',
          message: 'It may have been deleted from this device.',
        ),
      );
    }

    final t = transaction;
    final paid = t.advancePaid.clamp(0.0, t.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TransactionFormScreen(transaction: t),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.10),
                        child: Text(
                          initials(t.customerName),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.customerName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.itemDescription.isEmpty
                                  ? 'No description'
                                  : t.itemDescription,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(label: t.displayStatus),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(t.totalAmount),
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: t.paidFraction,
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${money(paid)} paid',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${money(t.balanceDue)} balance',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _BreakdownCard(transaction: t),
            const SizedBox(height: 16),
            _DetailsCard(transaction: t),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _showPaymentSheet(context, ref, t),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Update payment'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransactionFormScreen(transaction: t),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit transaction'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _confirmDelete(context, ref, t),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete transaction'),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    WidgetRef ref,
    Transaction transaction,
  ) async {
    await ref.read(transactionsProvider.notifier).save(transaction);
  }

  Future<void> _showPaymentSheet(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Current balance: ${money(transaction.balanceDue)}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.green,
                ),
                title: const Text('Mark as fully paid'),
                subtitle: const Text('Close the balance and count commission.'),
                onTap: () => Navigator.pop(context, 'paid'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.timelapse_rounded,
                  color: AppColors.amber,
                ),
                title: const Text('Record a partial payment'),
                subtitle: const Text('Add an amount received today.'),
                onTap: () => Navigator.pop(context, 'partial'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.undo_rounded,
                  color: AppColors.blue,
                ),
                title: const Text('Mark as unpaid'),
                subtitle: const Text('Reset the paid amount to zero.'),
                onTap: () => Navigator.pop(context, 'unpaid'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    if (action == 'paid') {
      await _save(
        ref,
        transaction.copyWith(
          status: PaymentStatus.paid,
          advancePaid: transaction.totalAmount,
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as paid.')),
      );
      return;
    }

    if (action == 'unpaid') {
      await _save(
        ref,
        transaction.copyWith(
          status: PaymentStatus.unpaid,
          advancePaid: 0,
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as unpaid.')),
      );
      return;
    }

    if (action == 'partial') {
      await _recordPartial(context, ref, transaction);
    }
  }

  Future<void> _recordPartial(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final controller = TextEditingController(
      text: transaction.balanceDue.toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance due: ${money(transaction.balanceDue)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount received (RM)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.replaceAll(',', '').trim(),
              );
              if (value == null || value <= 0) return;
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (amount == null || !context.mounted) return;

    final newPaid = (transaction.advancePaid + amount).clamp(
      0.0,
      transaction.totalAmount,
    );
    final newStatus = newPaid >= transaction.totalAmount
        ? PaymentStatus.paid
        : PaymentStatus.partial;

    await _save(
      ref,
      transaction.copyWith(
        status: newStatus,
        advancePaid: newPaid,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus == PaymentStatus.paid
              ? 'Payment recorded — transaction is now paid.'
              : 'Payment recorded.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(transactionsProvider.notifier).delete(transaction.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Transaction deleted.')),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Balance breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          InfoRow(label: 'Total amount', value: money(transaction.totalAmount)),
          InfoRow(label: 'Amount paid', value: money(transaction.advancePaid)),
          const Divider(height: 18),
          InfoRow(
            label: 'Balance due',
            value: money(transaction.balanceDue),
            valueColor: transaction.balanceDue > 0
                ? AppColors.red
                : AppColors.green,
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final aging = transaction.isPaid
        ? 'Paid'
        : '${transaction.agingBucket.label}${transaction.isOverdue ? ' · ${transaction.daysOverdue} days overdue' : ''}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          InfoRow(label: 'Status', value: transaction.displayStatus),
          InfoRow(label: 'Aging', value: aging),
          InfoRow(label: 'Due date', value: shortDate(transaction.dueDate)),
          if (transaction.finishDate != null)
            InfoRow(
              label: 'Finish date',
              value: shortDate(transaction.finishDate),
            ),
          if (transaction.claimExpiry != null)
            InfoRow(
              label: 'Claim expiry',
              value: shortDate(transaction.claimExpiry),
            ),
          if ((transaction.invoiceNumber ?? '').isNotEmpty)
            InfoRow(
              label: 'Invoice no.',
              value: transaction.invoiceNumber!,
            ),
          if (transaction.invoiceDate != null)
            InfoRow(
              label: 'Invoice date',
              value: shortDate(transaction.invoiceDate),
            ),
          if ((transaction.cashBillNumber ?? '').isNotEmpty)
            InfoRow(
              label: 'Cash bill no.',
              value: transaction.cashBillNumber!,
            ),
          if (transaction.cashBillDate != null)
            InfoRow(
              label: 'Cash bill date',
              value: shortDate(transaction.cashBillDate),
            ),
          InfoRow(
            label: 'Last updated',
            value: shortDate(transaction.updatedAt),
          ),
        ],
      ),
    );
  }
}
