import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/payment.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/payment_actions.dart';

/// Payments a customer declared from the statement link. The agent checks the
/// bank record and confirms here, which writes the payment and clears the bill.
class ClaimsScreen extends ConsumerWidget {
  const ClaimsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(pendingClaimsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Payments to confirm')),
      body: PageWidth(
        child: Column(
          children: [
            const _ReconSearch(),
            Expanded(
              child: claims.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load claims',
            message: '$error',
          ),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing to confirm',
                message:
                    'When a customer taps “I have paid” on their statement, '
                    'the claim appears here.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),              itemBuilder: (context, index) => _ClaimCard(claim: items[index]),
            );
          },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard({required this.claim});

  final Map<String, dynamic> claim;

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _busy = false;

  /// The agent has to look at the customer's screenshot before confirming.
  bool _proofSeen = false;

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final amount = (claim['amount'] as num?)?.toDouble() ?? 0;
    final proof = claim['proofImage']?.toString();
    final hasProof = proof != null && proof.isNotEmpty;
    final declaredAt =
        DateTime.tryParse(claim['declaredAt']?.toString() ?? '') ??
        DateTime.now();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (claim['customerName'] ?? 'Customer').toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'RM ${NumberFormat('#,##0.00').format(amount)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if ((claim['reconCode'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: claim['reconCode'].toString()),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reference code copied')),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tag_rounded, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      claim['reconCode'].toString(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy_rounded, size: 12, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          if (((claim['billCount'] as num?)?.toInt() ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  const Text(
                    'Paying:',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  for (final label
                      in (claim['billLabels'] as List? ?? const [])
                          .map((e) => e.toString()))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Declared ${DateFormat('d MMM yyyy, h:mm a').format(declaredAt)}'
            '${(claim['note'] ?? '').toString().isEmpty ? '' : ' · ${claim['note']}'}',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          if (hasProof) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _showProof(proof);
                setState(() => _proofSeen = true);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        base64Decode(proof.substring(proof.indexOf(',') + 1)),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _proofSeen
                            ? 'Screenshot checked'
                            : 'Tap to check the transfer screenshot',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _proofSeen
                              ? AppColors.green
                              : AppColors.muted,
                        ),
                      ),
                    ),
                    Icon(
                      _proofSeen
                          ? Icons.check_circle_rounded
                          : Icons.visibility_outlined,
                      size: 18,
                      color: _proofSeen ? AppColors.green : AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'No screenshot attached — you will be asked to take one when '
              'you confirm.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy || (hasProof && !_proofSeen)
                      ? null
                      : () => _confirm(amount),
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm received'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await ref
                            .read(paymentServiceProvider)
                            .rejectClaim((claim['id'] ?? '').toString());
                      },
                child: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showProof(String dataUri) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Customer payment screenshot',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(
                  base64Decode(dataUri.substring(dataUri.indexOf(',') + 1)),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(double amount) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    // Every confirmed payment must carry its evidence. If the customer did not
    // attach a screenshot, the agent takes one here before confirming.
    var claim = widget.claim;
    final existingProof = claim['proofImage']?.toString();
    if (existingProof == null || existingProof.isEmpty) {
      final picked = await pickImageAsDataUri(context);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      claim = {...claim, 'proofImage': picked};
    }

    final transactions =
        ref.read(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final ok = await ref
        .read(paymentServiceProvider)
        .confirmClaim(
          ownerUid: ref.read(dataOwnerProvider),
          transactions: transactions,
          claim: claim,
        );
    await ref.read(transactionsProvider.notifier).refresh();
    if (ok) {
      await refreshCustomerStatement(
        ref,
        (widget.claim['customerName'] ?? '').toString(),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Payment confirmed — the bill has been updated.'
              : 'Could not match this claim to an open bill.',
        ),
        backgroundColor: ok ? AppColors.green : AppColors.red,
      ),
    );
  }
}


/// Looks up which customer owns a reference code seen on a bank statement, then
/// records the incoming transfer against their oldest open bill.
class _ReconSearch extends ConsumerStatefulWidget {
  const _ReconSearch();

  @override
  ConsumerState<_ReconSearch> createState() => _ReconSearchState();
}

class _ReconSearchState extends ConsumerState<_ReconSearch> {
  final _controller = TextEditingController();
  Map<String, dynamic>? _result;
  Transaction? _matchedBill;
  bool _searched = false;
  bool _busy = false;

  /// Collapsed by default: the claims below already show their own code, so
  /// this is only for a transfer that arrived without a claim.
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() => _busy = true);

    // The agent copies the number printed on the transfer, which is either
    // a bill number or the SPL reference. Try the ledger first.
    // The agent may type only the digits of the number, so compare the
    // alphanumeric core of both sides instead of requiring an exact match.
    String core(String value) =>
        value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final needle = core(query);
    final transactions =
        ref.read(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final bill = needle.length < 3
        ? null
        : transactions
              .where(
                (t) =>
                    core(t.cashBillNumber ?? '').contains(needle) ||
                    core(t.invoiceNumber ?? '').contains(needle),
              )
              .firstOrNull;

    if (bill != null) {
      if (!mounted) return;
      setState(() {
        _matchedBill = bill;
        _result = {'customerName': bill.customerName};
        _searched = true;
        _busy = false;
      });
      return;
    }

    final found = await ref
        .read(statementServiceProvider)
        .findByReconCode(
          ownerUid: ref.read(dataOwnerProvider),
          code: query,
        );
    if (!mounted) return;
    setState(() {
      _matchedBill = null;
      _result = found;
      _searched = true;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final customerName = (_result?['customerName'] ?? '').toString();
    final transactions =
        ref.watch(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final open = _matchedBill != null
        ? [_matchedBill!]
        : transactions
              .where((t) => t.customerName == customerName && t.isOpen)
              .toList();
    final outstanding =
        open.fold<double>(0, (sum, t) => sum + t.balanceDue);

    if (!_open) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text(
              'Received a transfer without a claim? Find it by code',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Find by reference code',
                    hintText: 'SPL-8F3A',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => setState(() {
                  _open = false;
                  _result = null;
                  _searched = false;
                  _controller.clear();
                }),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_searched && _result == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No customer uses that code.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          if (customerName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _matchedBill != null
                                ? 'Bill ${_matchedBill!.cashBillNumber ?? _matchedBill!.invoiceNumber ?? ''} · RM ${outstanding.toStringAsFixed(2)}'
                                : open.isEmpty
                                ? 'Nothing outstanding'
                                : '${open.length} open bill(s) · RM ${outstanding.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (open.isNotEmpty)
                      FilledButton(
                        onPressed: () => _record(customerName, outstanding),
                        child: const Text('Record'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _record(String customerName, double outstanding) async {
    final amountController = TextEditingController(
      text: outstanding.toStringAsFixed(2),
    );
    String? proof;
    bool proofMissing = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('Record for $customerName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (RM)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pickImageAsDataUri(context);
                  if (picked == null) return;
                  setState(() {
                    proof = picked;
                    proofMissing = false;
                  });
                },
                icon: const Icon(Icons.receipt_outlined, size: 18),
                label: Text(
                  proof == null ? 'Attach payment proof *' : 'Replace proof',
                ),
              ),
              if (proofMissing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'A receipt or transfer screenshot is required.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (proof == null) {
                  setState(() => proofMissing = true);
                  return;
                }
                final amount =
                    double.tryParse(amountController.text.trim()) ?? 0;
                if (amount <= 0) return;
                Navigator.of(dialogContext).pop();
                final bill = _matchedBill;
                final bool ok;
                if (bill != null) {
                  final payment = await ref
                      .read(paymentServiceProvider)
                      .record(
                        ownerUid: ref.read(dataOwnerProvider),
                        transaction: bill,
                        amount: amount,
                        method: PaymentMethod.bank,
                        note: 'Matched by bill number',
                        reference: _controller.text.trim().toUpperCase(),
                        proofImage: proof,
                      );
                  ok = payment != null;
                } else {
                  ok = await ref
                      .read(paymentServiceProvider)
                      .recordForCustomer(
                        ownerUid: ref.read(dataOwnerProvider),
                        transactions:
                            ref.read(transactionsProvider).valueOrNull ??
                            const <Transaction>[],
                        customerName: customerName,
                        amount: amount,
                        proofImage: proof,
                        reference: _controller.text.trim().toUpperCase(),
                      );
                }
                await ref.read(transactionsProvider.notifier).refresh();
                await refreshCustomerStatement(ref, customerName);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Payment recorded against the oldest bill.'
                          : 'Could not match this to an open bill.',
                    ),
                    backgroundColor: ok ? AppColors.green : AppColors.red,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
