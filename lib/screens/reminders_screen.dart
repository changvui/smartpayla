import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/payment.dart';
import '../models/reminder.dart';
import '../models/transaction.dart';
import '../services/reminder_log.dart';
import '../services/reminder_service.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../utils/names.dart';
import '../utils/whatsapp.dart';
import '../widgets/common.dart';

/// A customer who owes money, with the bills that make up the debt.
class _ChaseItem {
  _ChaseItem({
    required this.key,
    required this.name,
    required this.bills,
    required this.lastSentAt,
  });

  final String key;
  final String name;
  final List<Transaction> bills;
  final DateTime? lastSentAt;

  double get balance => bills.fold(0.0, (sum, t) => sum + t.balanceDue);

  /// Days overdue of the oldest bill, which is the one to chase first.
  int get daysOverdue =>
      bills.map((t) => t.daysOverdue).fold(0, (a, b) => a > b ? a : b);

  Transaction get oldestBill {
    final sorted = [...bills]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return sorted.first;
  }

  /// Urgency plus neglect: overdue days, boosted when the customer has never
  /// been reminded or has not been contacted for a long time.
  double get score {
    final sinceContact = lastSentAt == null
        ? 30
        : DateTime.now().difference(lastSentAt!).inDays.clamp(0, 30);
    return (daysOverdue + sinceContact).toDouble();
  }
}

enum _Filter { all, never, overdue30 }

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  _Filter _filter = _Filter.all;
  Map<String, DateTime> _lastSent = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  Future<void> _loadLog() async {
    final last = await ReminderLog.lastSentByCustomer();
    if (!mounted) return;
    setState(() {
      _lastSent = last;
      _loaded = true;
    });
  }

  List<_ChaseItem> _buildItems(List<Transaction> transactions) {
    final groups = <String, List<Transaction>>{};
    for (final transaction in transactions) {
      if (!transaction.isOpen) continue;
      final key = normaliseCustomerName(transaction.customerName).toLowerCase();
      groups.putIfAbsent(key, () => []).add(transaction);
    }

    final items = groups.entries.map((entry) {
      final bills = entry.value;
      final name = normaliseCustomerName(bills.first.customerName);
      return _ChaseItem(
        key: entry.key,
        name: name,
        bills: bills,
        lastSentAt: _lastSent[entry.key],
      );
    }).toList();

    items.sort((a, b) => b.score.compareTo(a.score));
    return items;
  }

  List<_ChaseItem> _applyFilter(List<_ChaseItem> items) {
    switch (_filter) {
      case _Filter.all:
        return items;
      case _Filter.never:
        return items.where((i) => i.lastSentAt == null).toList();
      case _Filter.overdue30:
        return items.where((i) => i.daysOverdue > 30).toList();
    }
  }

  Future<void> _openCompose(_ChaseItem item) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ComposeSheet(item: item),
    );
    if (sent == true) await _loadLog();
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider).valueOrNull ??
        const <Transaction>[];
    final allItems = _buildItems(transactions);
    final items = _applyFilter(allItems);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _HeaderCard(
              count: allItems.length,
              total: allItems.fold(0.0, (sum, i) => sum + i.balance),
            ),
            const SizedBox(height: 16),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (allItems.isEmpty)
              const _EmptyState()
            else ...[
              _FilterBar(
                value: _filter,
                onChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 12),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ChaseRow(
                    item: item,
                    onTap: () => _openCompose(item),
                  ),
                ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nobody matches this filter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F5C4D), Color(0xFF15806A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s chase list',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count == 0
                      ? 'Nobody owes you money right now.'
                      : '$count customer${count == 1 ? '' : 's'} owe '
                          '${money(total)} — ranked by age and last contact.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});

  final _Filter value;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  switch (option) {
                    _Filter.all => 'All',
                    _Filter.never => 'Never reminded',
                    _Filter.overdue30 => 'Overdue 30+ days',
                  },
                  style: const TextStyle(fontSize: 12),
                ),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One row in the list
// ---------------------------------------------------------------------------

class _ChaseRow extends StatelessWidget {
  const _ChaseRow({required this.item, required this.onTap});

  final _ChaseItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final days = item.daysOverdue;
    final urgent = days > 60;
    final warning = days > 30 && !urgent;
    final accent = urgent
        ? AppColors.red
        : (warning ? AppColors.orange : AppColors.green);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accent.withValues(alpha: 0.14),
            child: Text(
              item.name.isEmpty ? '?' : item.name[0].toUpperCase(),
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 15,
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
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      money(item.balance),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.bills.length} bill${item.bills.length == 1 ? '' : 's'}'
                  ' · oldest ${days}d overdue · '
                  '${_lastContactText(item.lastSentAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onTap,
            child: const Text('Remind', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _lastContactText(DateTime? last) {
    if (last == null) return 'never reminded';
    final days = DateTime.now().difference(last).inDays;
    if (days == 0) return 'reminded today';
    if (days == 1) return 'reminded 1 day ago';
    return 'reminded $days days ago';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 40, color: AppColors.green),
          const SizedBox(height: 10),
          const Text(
            'Nothing to chase',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Every bill is settled. Recorded sales with an outstanding balance '
            'appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compose sheet
// ---------------------------------------------------------------------------

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.item});

  final _ChaseItem item;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  late Transaction _bill;
  late final TextEditingController _draft;
  ReminderTone _tone = ReminderTone.formal;
  ReminderLanguage _language = ReminderLanguage.english;
  bool _generating = false;
  bool _edited = false;
  bool _quotaExhausted = false;

  @override
  void initState() {
    super.initState();
    _bill = widget.item.oldestBill;
    _draft = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  String get _billReference {
    final cash = _bill.cashBillNumber?.trim();
    if (cash != null && cash.isNotEmpty) return cash;
    final invoice = _bill.invoiceNumber?.trim();
    if (invoice != null && invoice.isNotEmpty) return invoice;
    return '';
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
    });

    final result = await ref.read(reminderServiceProvider).generate(
          transaction: _bill,
          tone: _tone,
          language: _language,
          reference: _billReference,
        );
    final withLink = await _withPaymentLink(result);

    if (!mounted) return;
    setState(() {
      _generating = false;
      _draft.text = withLink.text;
      _edited = false;
      _quotaExhausted = (withLink.error ?? '').contains('503') ||
          (withLink.error ?? '').contains('429');
    });
  }

  /// Appends the payment link and the bill reference. The reference is what the
  /// customer types into the transfer, which is how the agent matches the money
  /// to the right bill later.
  Future<ReminderResult> _withPaymentLink(ReminderResult result) async {
    final billRef = _billReference;
    final refLine = billRef.isEmpty ? '' : '\nRef: $billRef';
    try {
      final statements = ref.read(statementServiceProvider);
      final payments = ref.read(paymentServiceProvider);
      final owner = ref.read(dataOwnerProvider);
      final settings = ref.read(settingsProvider);
      final all =
          ref.read(transactionsProvider).valueOrNull ?? const <Transaction>[];
      final open = all
          .where(
            (t) =>
                normaliseCustomerName(t.customerName).toLowerCase() ==
                    widget.item.key &&
                t.isOpen,
          )
          .toList();
      if (open.isEmpty) return result;

      final byTransaction = <String, List<Payment>>{};
      for (final bill in open) {
        byTransaction[bill.id] = await payments.forTransaction(owner, bill.id);
      }
      final token = await statements.publish(
        ownerUid: owner,
        customerName: widget.item.name,
        openBills: open,
        paymentsByTransaction: byTransaction,
        settings: settings,
        agentPhone: '',
      );
      if (token == null) return result;
      return ReminderResult(
        text: '${result.text}$refLine\nPay here: ${statements.linkFor(token)}',
        tone: result.tone,
        usedFallback: result.usedFallback,
        error: result.error,
      );
    } catch (_) {
      // A reminder without a link still helps; never lose the generated text.
      return ReminderResult(
        text: '${result.text}$refLine',
        tone: result.tone,
        usedFallback: result.usedFallback,
        error: result.error,
      );
    }
  }

  Future<void> _record(String text) async {
    if (text.isEmpty) return;
    final now = DateTime.now();
    try {
      await ReminderLog.add(
      SentReminder(
        customerKey: widget.item.key,
        customerName: widget.item.name,
        tone: _tone,
        language: _language.code,
        text: text,
        usedFallback: _quotaExhausted,
        sentAt: now,
      ),
    );
    } catch (error) {
      // The log is an aid, not the record itself: failing to write it must not
      // stop the message being sent.
      debugPrint('ReminderLog failed: $error');
    }

    try {
      await ref.read(reminderHistoryProvider.notifier).add(
            ReminderRecord(
              id: const Uuid().v4(),
              transactionId: _bill.id,
              customerName: widget.item.name,
              tone: _tone,
              text: text,
              createdAt: now,
              usedFallback: _quotaExhausted,
            ),
          );
    } catch (error) {
      debugPrint('Reminder history failed: $error');
    }
  }

  Future<void> _copy() async {
    final text = _draft.text.trim();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error) {
      // Clipboard can fail on a browser that has lost focus; the message is
      // still visible for a manual copy.
      debugPrint('Clipboard failed: $error');
    }
    await _record(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder copied.')),
    );
    Navigator.of(context).pop(true);
  }

  /// The customer's phone, when the profile has one, so WhatsApp opens the
  /// right chat instead of the contact picker.
  String? get _customerPhone {
    final List<Customer> profiles;
    try {
      profiles = ref.read(customerProvider).valueOrNull ?? const <Customer>[];
    } catch (error) {
      debugPrint('Customer lookup failed: $error');
      return null;
    }
    for (final profile in profiles) {
      if (normaliseCustomerName(profile.name).toLowerCase() ==
          widget.item.key) {
        final phone = profile.phone.trim();
        if (phone.isNotEmpty && phone.toLowerCase() != 'no phone') {
          return phone;
        }
      }
    }
    return null;
  }

  Future<void> _share() async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;

    // Start the launch *before* any await: a browser only allows a new tab while
    // it still considers the click to be in progress, and the log write below
    // takes long enough to lose that permission.
    Future<bool>? launch;
    try {
      launch = openWhatsApp(text, phone: _customerPhone);
    } catch (error) {
      debugPrint('WhatsApp launch threw: $error');
    }

    // Keep the text on the clipboard as well, so a blocked popup still leaves
    // the agent one paste away from sending.
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error) {
      debugPrint('Clipboard failed: $error');
    }

    await _record(text);
    final opened = launch == null ? false : await launch;
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder copied — paste it into WhatsApp.'),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final media = MediaQuery.of(context);
    final hasLink = _draft.text.contains('Pay here:');

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: media.viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${money(widget.item.balance)} outstanding · '
              '${widget.item.bills.length} bill'
              '${widget.item.bills.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),

            // Which bill this reminder is about. One payment settles one bill,
            // so the message must name exactly one.
            if (widget.item.bills.length > 1) ...[
              const Text(
                'Bill to mention',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final bill in widget.item.bills)
                    ChoiceChip(
                      label: Text(
                        '${_refOf(bill)} · ${money(bill.balanceDue)}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _bill.id == bill.id,
                      onSelected: (_) {
                        setState(() => _bill = bill);
                        _generate();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            const Text(
              'Tone',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SegmentedButton<ReminderTone>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              segments: [
                for (final tone in ReminderTone.values)
                  ButtonSegment(value: tone, label: Text(tone.label)),
              ],
              selected: {_tone},
              onSelectionChanged: (values) {
                setState(() => _tone = values.first);
                _generate();
              },
            ),
            const SizedBox(height: 12),

            const Text(
              'Language',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SegmentedButton<ReminderLanguage>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              segments: [
                for (final language in ReminderLanguage.values)
                  ButtonSegment(
                    value: language,
                    label: Text(language.label),
                  ),
              ],
              selected: {_language},
              onSelectionChanged: (values) {
                setState(() => _language = values.first);
                _generate();
              },
            ),
            const SizedBox(height: 14),

            if (_quotaExhausted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 15, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AI quota used up for today — this is the built-in '
                        'template. You can still send it.',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ),
                  ],
                ),
              ),

            TextField(
              controller: _draft,
              minLines: 4,
              maxLines: 10,
              onChanged: (_) => setState(() => _edited = true),
              decoration: InputDecoration(
                labelText: _generating ? 'Writing…' : 'Message (editable)',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                helperText: hasLink
                    ? 'Payment link included.'
                    : 'No payment link — publish the statement rules to add one.',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  hasLink ? Icons.link_rounded : Icons.link_off_rounded,
                  size: 14,
                  color: hasLink ? AppColors.green : AppColors.orange,
                ),
                const SizedBox(width: 5),
                Text(
                  _edited ? 'Edited' : 'As generated',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Regenerate',
                  onPressed: _generating ? null : _generate,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generating || _draft.text.isEmpty ? null : _copy,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _generating || _draft.text.isEmpty ? null : _share,
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _refOf(Transaction bill) {
    final cash = bill.cashBillNumber?.trim();
    if (cash != null && cash.isNotEmpty) return cash;
    final invoice = bill.invoiceNumber?.trim();
    if (invoice != null && invoice.isNotEmpty) return invoice;
    return NumberFormat('yyyyMMdd').format(bill.createdAt);
  }
}
