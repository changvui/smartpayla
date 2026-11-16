import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/providers.dart';
import 'common.dart';

/// Shows the customer's payment behaviour on the transaction screen, with the
/// reason behind the score so the agent can act on it rather than trust a number.
class CustomerCreditCard extends ConsumerWidget {
  const CustomerCreditCard({super.key, required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credit = ref.watch(creditScoresProvider)[customerName];
    if (credit == null || !credit.hasHistory) return const SizedBox.shrink();

    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final money = NumberFormat('#,##0.00');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Customer reliability',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              CreditBadge(band: credit.band, score: credit.score),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            credit.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            credit.explanation,
            style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metric('Open bills', '${credit.openBills}', mutedColor, textColor),
              const SizedBox(width: 18),
              _metric(
                'Overdue',
                '${credit.overdueBills}',
                mutedColor,
                textColor,
              ),
              const SizedBox(width: 18),
              _metric(
                'Outstanding',
                'RM ${money.format(credit.outstanding)}',
                mutedColor,
                textColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    Color muted,
    Color textColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: muted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
