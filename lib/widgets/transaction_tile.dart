import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../theme.dart';
import 'common.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.compact = false,
  });

  final Transaction transaction;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool compact;

  String get _dueLabel {
    if (transaction.isPaid) return 'Settled';
    if (transaction.isOverdue) {
      final days = transaction.daysOverdue;
      return '$days ${days == 1 ? 'day' : 'days'} overdue';
    }
    return 'Due ${shortDate(transaction.dueDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final dueColor = transaction.isOverdue
        ? AppColors.red
        : transaction.isPaid
            ? AppColors.green
            : AppColors.muted;

    return AppCard(
      padding: EdgeInsets.all(compact ? 12 : 14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: compact ? 19 : 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.10),
            child: Text(
              initials(transaction.customerName),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 12 : 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transaction.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 13.5 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: transaction.displayStatus,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.itemDescription.isEmpty
                      ? 'No description'
                      : transaction.itemDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      money(transaction.balanceDue),
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'balance',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _dueLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: dueColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onEdit != null || onDelete != null) ...[
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, size: 19),
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
