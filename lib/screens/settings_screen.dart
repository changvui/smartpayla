import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase_config.dart';
import '../models/reminder.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_badge.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _rateController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late ReminderTone _tone;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _rateController =
        TextEditingController(text: _formatRate(settings.commissionPercent));
    _baseUrlController = TextEditingController(text: settings.aiBaseUrl);
    _apiKeyController = TextEditingController(text: settings.aiApiKey);
    _modelController = TextEditingController(text: settings.aiModel);
    _tone = settings.defaultTone;
  }

  String _formatRate(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _rateController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
            const SectionHeader(title: 'AI reminders'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LLM connection',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'DeepSeek or any OpenAI-compatible endpoint. Leave the key empty to use the built-in fallback templates. The key is stored on this device only.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    decoration: _aiDecoration(
                      'API base URL',
                      hint: 'https://api.deepseek.com/v1',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelController,
                    decoration: _aiDecoration(
                      'Model',
                      hint: 'deepseek-chat',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _aiDecoration(
                      'API key (optional)',
                      hint: 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ReminderTone>(
                    initialValue: _tone,
                    isExpanded: true,
                    decoration: _aiDecoration('Default tone'),
                    items: [
                      for (final tone in ReminderTone.values)
                        DropdownMenuItem(
                          value: tone,
                          child: Text(tone.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _tone = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saveAi,
                      child: const Text('Save AI settings'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Cloud sync'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SyncBadge(),
                      const Spacer(),
                      if (FirebaseRuntime.initialized)
                        TextButton.icon(
                          onPressed: _syncNow,
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('Sync now'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    FirebaseRuntime.initialized
                        ? 'Connected to Firestore as “${FirebaseConfig.userId}”. Local cache stays available offline.'
                        : 'Local only. Add FIREBASE_* --dart-define values to enable Firestore sync; the app keeps working without them.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      height: 1.45,
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
                  InfoRow(
                      label: 'Build',
                      value: 'Increment 4 · local + cloud + AI'),
                  InfoRow(label: 'Framework', value: 'Flutter · Material 3'),
                  InfoRow(label: 'Currency', value: 'Malaysian Ringgit (RM)'),
                  InfoRow(
                      label: 'Cloud sync',
                      value: 'Firestore adapter · offline cache'),
                  InfoRow(
                      label: 'AI reminders',
                      value: 'LLM API · static fallback'),
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

  Future<void> _syncNow() async {
    await ref.read(transactionsProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync requested.')),
    );
  }

  InputDecoration _aiDecoration(String label, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  Future<void> _saveAi() async {
    final base = _baseUrlController.text.trim();
    if (base.isNotEmpty &&
        !base.startsWith('http://') &&
        !base.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Base URL must start with http:// or https://.'),
        ),
      );
      return;
    }
    await ref.read(settingsProvider.notifier).setAiConfig(
          baseUrl: base,
          apiKey: _apiKeyController.text,
          model: _modelController.text,
        );
    await ref.read(settingsProvider.notifier).setDefaultTone(_tone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI reminder settings saved.')),
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
      SnackBar(
          content:
              Text('Commission rate saved at ${value.toStringAsFixed(1)}%.')),
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
