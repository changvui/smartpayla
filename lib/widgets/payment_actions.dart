import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/payment.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../utils/whatsapp.dart';
import 'common.dart';

String _money(double value) => 'RM ${NumberFormat('#,##0.00').format(value)}';

/// Asks whether the proof comes from the camera or the gallery, then returns it
/// as a compressed data URI. Used for cash slips (camera) and for transfer
/// screenshots (gallery).
Future<String?> pickImageAsDataUri(
  BuildContext context, {
  int maxWidth = 600,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: maxWidth.toDouble(),
    imageQuality: 50,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return 'data:image/jpeg;base64,${base64Encode(bytes)}';
}

/// Re-publishes the customer's statement after a payment changed the balance, so
/// a link the customer already holds never shows a stale amount.
Future<void> refreshCustomerStatement(
  WidgetRef ref,
  String customerName,
) async {
  final transactions = ref.read(transactionsProvider).valueOrNull ??
      const <Transaction>[];
  final open = transactions
      .where((t) => t.customerName == customerName && t.isOpen)
      .toList();
  final owner = ref.read(dataOwnerProvider);
  final payments = ref.read(paymentServiceProvider);
  final settings = ref.read(settingsProvider);
  final byTransaction = <String, List<Payment>>{};
  for (final bill in open) {
    byTransaction[bill.id] = await payments.forTransaction(owner, bill.id);
  }
  await ref.read(statementServiceProvider).publish(
        ownerUid: owner,
        customerName: customerName,
        openBills: open,
        paymentsByTransaction: byTransaction,
        settings: settings,
        agentPhone: '',
      );
}

/// Publishes the customer's statement and offers the link for WhatsApp.
Future<void> collectStatement(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
) async {
  try {
    await _collectStatement(context, ref, transaction);
  } catch (error) {
    if (!context.mounted) return;
    final raw = error.toString();
    final message = raw.contains('permission-denied')
        ? 'Firestore rejected the write. Publish the rules from '
              'firestore.rules (Firestore → Rules) and make sure you are '
              'signed in.'
        : 'Could not create the payment link: $raw';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.red,
        duration: const Duration(seconds: 8),
      ),
    );
  }
}

Future<void> _collectStatement(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
) async {
  // The statement is written to a public collection that only an authenticated
  // owner may create; without a session Firestore rejects it, so say why instead
  // of showing a permission error.
  if (FirebaseAuth.instance.currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sign in first — the payment link is stored under your account.',
        ),
        backgroundColor: AppColors.orange,
        duration: Duration(seconds: 6),
      ),
    );
    return;
  }

  final transactions = ref.read(transactionsProvider).valueOrNull ?? const [];
  final open = transactions
      .where(
        (t) => t.customerName == transaction.customerName && t.isOpen,
      )
      .toList();

  if (open.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nothing outstanding for this customer.'),
        backgroundColor: AppColors.green,
      ),
    );
    return;
  }

  final owner = ref.read(dataOwnerProvider);
  final settings = ref.read(settingsProvider);
  final payments = ref.read(paymentServiceProvider);
  final statements = ref.read(statementServiceProvider);

  final byTransaction = <String, List<Payment>>{};
  for (final bill in open) {
    byTransaction[bill.id] = await payments.forTransaction(owner, bill.id);
  }

  final token = await statements.publish(
    ownerUid: owner,
    customerName: transaction.customerName,
    openBills: open,
    paymentsByTransaction: byTransaction,
    settings: settings,
    agentPhone: '',
  );

  if (!context.mounted) return;
  if (token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not create the link. Check your connection.'),
        backgroundColor: AppColors.red,
      ),
    );
    return;
  }

  final link = statements.linkFor(token);
  // Browsers only allow a clipboard write inside a user gesture; the awaits
  // above lose it, so a failure here must not abort the share sheet.
  try {
    await Clipboard.setData(ClipboardData(text: link));
  } catch (_) {
    // The sheet below shows the link, so the agent can still copy it by hand.
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment link for ${transaction.customerName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              open.length == 1
                  ? '1 outstanding bill · ${_money(open.first.balanceDue)}'
                  : '${open.length} outstanding bills · ${_money(open.fold<double>(0, (s, t) => s + t.balanceDue))}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                link,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The link was copied to the clipboard.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final opened = await openWhatsApp(
                        'Hi ${transaction.customerName}, here is your statement '
                        'from ${settings.shopName}: $link',
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not open WhatsApp — the link is already '
                              'on your clipboard.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Records a payment the agent has already received (cash or a checked
/// transfer). The amount is capped at the outstanding balance, and a settled
/// bill cannot be "paid" twice.
Future<void> recordPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
) async {
  final balance = transaction.balanceDue;

  if (balance <= 0.005) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.green),
            SizedBox(width: 8),
            Text('This bill is settled'),
          ],
        ),
        content: Text(
          '${transaction.customerName} has no outstanding balance on this '
          'bill. To correct an earlier payment, open the payment history and '
          'void the wrong entry.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  final amountController = TextEditingController(
    text: balance.toStringAsFixed(2),
  );
  final noteController = TextEditingController();
  var method = PaymentMethod.cash;
  String? error;
  String? proof;
  bool proofMissing = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final typed = double.tryParse(amountController.text.trim()) ?? 0;
        final remaining = (balance - typed).clamp(0.0, double.infinity);
        return AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Balance',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const Spacer(),
                    Text(
                      _money(balance),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => error = null),
                decoration: InputDecoration(
                  labelText: 'Amount (RM)',
                  border: const OutlineInputBorder(),
                  errorText: error,
                  helperText: typed > 0
                      ? 'Balance after this payment: ${_money(remaining)}'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in [
                    PaymentMethod.cash,
                    PaymentMethod.duitnow,
                    PaymentMethod.bank,
                  ])
                    ChoiceChip(
                      label: Text(option.label),
                      selected: method == option,
                      onSelected: (_) => setState(() => method = option),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Proof that the money arrived (transfer screenshot or cash slip).
              // Separate from the bill photo, which proves what was sold.
              Row(
                children: [
                  if (proof != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(proof!.substring(proof!.indexOf(',') + 1)),
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (proof != null) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
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
                        proof == null
                            ? 'Attach payment proof *'
                            : 'Replace proof',
                      ),
                    ),
                  ),
                  if (proof != null)
                    IconButton(
                      onPressed: () => setState(() => proof = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
              if (proofMissing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'A photo of the receipt or transfer screenshot is required.',
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
                final amount =
                    double.tryParse(amountController.text.trim()) ?? 0;
                if (proof == null) {
                  setState(() => proofMissing = true);
                  return;
                }
                if (amount <= 0) {
                  setState(() => error = 'Enter an amount greater than zero');
                  return;
                }
                if (amount > balance + 0.005) {
                  setState(
                    () => error = 'At most ${_money(balance)} is outstanding',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop();
                final service = ref.read(paymentServiceProvider);
                final owner = ref.read(dataOwnerProvider);
                final payment = await service.record(
                  ownerUid: owner,
                  transaction: transaction,
                  amount: amount,
                  method: method,
                  note: noteController.text.trim(),
                  proofImage: proof,
                );
                await ref.read(transactionsProvider.notifier).refresh();
                if (payment != null) {
                  await refreshCustomerStatement(
                    ref,
                    transaction.customerName,
                  );
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      payment == null
                          ? 'Could not record the payment. Check the amount.'
                          : 'Payment recorded · ${payment.receiptNo}',
                    ),
                    backgroundColor: payment == null
                        ? AppColors.red
                        : AppColors.green,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

/// The append-only payment history for one transaction.
class PaymentHistoryCard extends ConsumerWidget {
  const PaymentHistoryCard({super.key, required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(dataOwnerProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return FutureBuilder<List<Payment>>(
      future: ref
          .read(paymentServiceProvider)
          .forTransaction(owner, transaction.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final payments = snapshot.data ?? const <Payment>[];
        if (payments.isEmpty) return const SizedBox.shrink();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payment history',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final payment in payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        payment.state == PaymentState.voided
                            ? Icons.block_rounded
                            : Icons.check_circle_rounded,
                        size: 16,
                        color: payment.state == PaymentState.voided
                            ? AppColors.red
                            : AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_money(payment.amount)} · ${payment.method.label}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: payment.state == PaymentState.voided
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            Text(
                              '${DateFormat('d MMM yyyy, h:mm a').format(payment.paidAt)} · ${payment.receiptNo}'
                              '${payment.state == PaymentState.voided ? ' · voided' : ''}',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                      if (payment.proofImage != null &&
                          payment.proofImage!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showProof(context, payment),
                            child: Tooltip(
                              message: 'Payment proof',
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      base64Decode(
                                        payment.proofImage!.substring(
                                          payment.proofImage!.indexOf(',') + 1,
                                        ),
                                      ),
                                      width: 34,
                                      height: 34,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(1),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Icon(
                                      Icons.zoom_in_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: 'No payment proof attached',
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 16,
                              color: muted.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      if (payment.state != PaymentState.voided)
                        IconButton(
                          tooltip: 'Void payment',
                          onPressed: () =>
                              _voidDialog(context, ref, payment),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showProof(BuildContext context, Payment payment) {
    final dataUri = payment.proofImage!;
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
                  Expanded(
                    child: Text(
                      'Payment proof · ${payment.receiptNo}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

  Future<void> _voidDialog(
    BuildContext context,
    WidgetRef ref,
    Payment payment,
  ) async {
    final reasonController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Void this payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The payment stays in the history but stops counting towards '
                'the balance. A reason is required: an unexplained void is the '
                'same as deleting the record.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                autofocus: true,
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'Wrong amount / duplicate / customer disputed',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final preset in const [
                    'Wrong amount',
                    'Duplicate entry',
                    'Wrong customer',
                    'Customer disputed',
                  ])
                    ActionChip(
                      label: Text(
                        preset,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () {
                        reasonController.text = preset;
                        setDialogState(() => error = null);
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => error = 'Explain why this payment is being voided',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop();
                await ref
                    .read(paymentServiceProvider)
                    .voidPayment(
                      ownerUid: ref.read(dataOwnerProvider),
                      transaction: transaction,
                      payment: payment,
                      reason: reason,
                    );
                await ref.read(transactionsProvider.notifier).refresh();
                await refreshCustomerStatement(ref, transaction.customerName);
              },
              child: const Text('Void'),
            ),
          ],
        ),
      ),
    );
  }
}
