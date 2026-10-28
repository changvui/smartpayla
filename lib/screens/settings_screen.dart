import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _rateController;

  @override
  void initState() {
    super.initState();
    final rate = ref.read(settingsProvider).commissionPercent;
    _rateController = TextEditingController(text: _formatRate(rate));
  }

  String _formatRate(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      'TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tiong Chang Vui',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '25WMR00499 · Sales agent',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(label: 'Local mode'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Commission'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Commission rate',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Applied to fully paid transactions. The partner Settings module will share this value in the integrated build.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rateController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*[.,]?\d{0,2}'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Rate',
                            suffixText: '%',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _saveRate,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: ${percent(settings.commissionRate)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Data'),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.dataset_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Load demo data'),
                    subtitle: const Text(
                      'Adds sample transactions if your ledger is empty.',
                    ),
                    onTap: _loadDemo,
                  ),
                  const Divider(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_sweep_outlined,
                      color: AppColors.red,
                    ),
                    title: const Text('Clear all transactions'),
                    subtitle: const Text(
                      'Removes every transaction stored on this device.',
                    ),
                    onTap: _clearAll,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'About'),
            const AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow(label: 'Build', value: 'Increment 1 · local storage'),
                  InfoRow(label: 'Framework', value: 'Flutter · Material 3'),
                  InfoRow(label: 'Currency', value: 'Malaysian Ringgit (RM)'),
                  InfoRow(label: 'Cloud sync', value: 'Increment 2 · Firestore'),
                  InfoRow(label: 'AI reminders', value: 'Increment 4 · LLM API'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This build is a local prototype for the SmartPayLA Core Transaction Engine. Authentication, customer profiles, OCR and reminder delivery are partner-module features and are intentionally not implemented here.',
              textAlign: TextAlign.center,
              style: TextStyle(
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

  Future<void> _saveRate() async {
    final value = double.tryParse(
      _rateController.text.replaceAll(',', '').trim(),
    );
    if (value == null || value < 0 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a rate between 0 and 100.')),
      );
      return;
    }
    await ref.read(settingsProvider.notifier).setCommissionRate(value / 100);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Commission rate saved at ${value.toStringAsFixed(1)}%.')),
    );
  }

  Future<void> _loadDemo() async {
    final added = await ref.read(transactionsProvider.notifier).seedDemo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Demo transactions loaded.'
              : 'Your ledger already has transactions; demo data was not added.',
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all transactions?'),
        content: const Text(
          'Every transaction on this device will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(transactionsProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All transactions cleared.')),
    );
  }
}
