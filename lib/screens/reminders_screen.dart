import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder.dart';
import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  String? _selectedId;
  late ReminderTone _tone;
  ReminderResult? _result;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _tone = ref.read(settingsProvider).defaultTone;
  }

  @override
  Widget build(BuildContext context) {
    final transactions =
        ref.watch(transactionsProvider).valueOrNull ?? const <Transaction>[];
    final settings = ref.watch(settingsProvider);
    final history = ref.watch(reminderHistoryProvider).valueOrNull ??
        const <ReminderRecord>[];

    final open = transactions.where((t) => t.isOpen).toList()
      ..sort((a, b) {
        final byOverdue = b.daysOverdue.compareTo(a.daysOverdue);
        if (byOverdue != 0) return byOverdue;
        return b.balanceDue.compareTo(a.balanceDue);
      });

    if (open.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reminders')),
        body: const EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'No open balances',
          message:
              'Every transaction is paid. New reminders will appear here when a balance is still open.',
        ),
      );
    }

    final selectedId =
        open.any((t) => t.id == _selectedId) ? _selectedId! : open.first.id;
    final selected = open.firstWhere((t) => t.id == selectedId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              onPressed: () => _clearHistory(context),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF153E36), AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI payment reminders',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Context-aware text with a static fallback.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!settings.aiConfigured) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: AppColors.amber,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No API key configured. Reminders will use the built-in templates. Add a key in Settings → AI reminders to use your LLM.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.amber,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const SectionHeader(title: 'Choose a customer'),
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              items: [
                for (final t in open)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.customerName} · ${money(t.balanceDue)}'
                      '${t.daysOverdue > 0 ? ' · ${t.daysOverdue}d overdue' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedId = value;
                  _result = null;
                });
              },
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Tone'),
            SegmentedButton<ReminderTone>(
              segments: const [
                ButtonSegment(
                  value: ReminderTone.formal,
                  label: Text('Formal'),
                ),
                ButtonSegment(
                  value: ReminderTone.friendly,
                  label: Text('Friendly'),
                ),
                ButtonSegment(
                  value: ReminderTone.urgent,
                  label: Text('Urgent'),
                ),
              ],
              selected: {_tone},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                setState(() => _tone = value.first);
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _generating ? null : () => _generate(selected),
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _generating ? 'Generating…' : 'Generate reminder',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 18),
              _PreviewCard(
                result: _result!,
                customer: selected.customerName,
                onCopy: () => _copy(_result!.text),
              ),
            ],
            const SizedBox(height: 22),
            SectionHeader(
              title: 'Reminder history',
              actionLabel: history.isEmpty ? null : 'Clear',
              onAction: history.isEmpty ? null : () => _clearHistory(context),
            ),
            if (history.isEmpty)
              const AppCard(
                child: Text(
                  'No reminders generated yet. Pick a customer and tap Generate.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              )
            else
              ...history.take(8).map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: AppCard(
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  record.customerName,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusPill(
                                  label: record.tone.label,
                                  compact: true,
                                ),
                                const Spacer(),
                                Text(
                                  DateFormat('d MMM, h:mm a')
                                      .format(record.createdAt),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              record.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate(Transaction transaction) async {
    final settings = ref.read(settingsProvider);
    setState(() {
      _generating = true;
      _result = null;
    });
    final result = await ref.read(reminderServiceProvider).generate(
          transaction: transaction,
          tone: _tone,
          apiBaseUrl: settings.aiBaseUrl,
          apiKey: settings.aiApiKey,
          model: settings.aiModel,
        );
    if (!mounted) return;
    setState(() {
      _generating = false;
      _result = result;
    });
    await ref.read(reminderHistoryProvider.notifier).add(
          ReminderRecord(
            id: const Uuid().v4(),
            transactionId: transaction.id,
            customerName: transaction.customerName,
            tone: result.tone,
            text: result.text,
            createdAt: DateTime.now(),
            usedFallback: result.usedFallback,
          ),
        );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder copied to clipboard.')),
    );
  }

  Future<void> _clearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear reminder history?'),
        content: const Text('This only removes the saved reminder texts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(reminderHistoryProvider.notifier).clear();
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.result,
    required this.customer,
    required this.onCopy,
  });

  final ReminderResult result;
  final String customer;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final isFallback = result.usedFallback;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Preview for $customer',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              StatusPill(
                label: isFallback ? 'Fallback' : 'AI',
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.ink,
            ),
          ),
          if (isFallback && result.error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Using the built-in template (${result.error}).',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.amber,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy message'),
            ),
          ),
        ],
      ),
    );
  }
}
