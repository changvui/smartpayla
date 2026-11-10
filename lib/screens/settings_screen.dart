import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';
import '../services/cloud_sync_service.dart';
import '../services/reminder_service.dart';
import '../state/auth_provider.dart';
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
  late ReminderTone _tone;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _rateController = TextEditingController(text: _formatRate(settings.commissionPercent));
    _tone = settings.defaultTone;
    _loadLocalPrefs();
  }

  Future<void> _loadLocalPrefs() async {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() {
      _isDarkMode = prefs.getBool('smartpayla_theme_dark') ?? false;
    });
  }

  String _formatRate(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  String _syncLabel(SyncStatus status) => switch (status) {
        SyncStatus.localOnly => 'Local',
        SyncStatus.syncing => 'Syncing',
        SyncStatus.synced => 'Synced',
        SyncStatus.error => 'Sync error',
      };

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to sync with the cloud. '
          'Records already saved on this device stay here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider).logout();
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme colors
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final inputFillColor = Theme.of(context).brightness == Brightness.dark 
        ? const Color(0xFF2C2C2C) // Dark grey for inputs in dark mode
        : AppColors.background;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            // Profile Card — follows the signed-in account
            AppCard(
              child: Row(
                children: [
                  const UserAvatar(radius: 25),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accountDisplayName(
                            ref.watch(authStateProvider).valueOrNull?.displayName,
                            ref.watch(authStateProvider).valueOrNull?.email,
                          ),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor), // 👈 FIXED
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ref.watch(authStateProvider).valueOrNull?.email ??
                              'Local test mode · not signed in',
                          style: TextStyle(fontSize: 11.5, color: mutedColor), // 👈 FIXED
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  StatusPill(label: _syncLabel(ref.watch(syncStatusProvider))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            
            // AI service status. The app calls the shared SmartPayLA proxy, so
            // there is deliberately no personal API-key field here.
            const SectionHeader(title: 'AI Service'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Shared SmartPayLA proxy',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ReminderService.isConfigured
                        ? 'Reminders are generated through the shared AI proxy. '
                            'No personal API key is needed.'
                        : 'No AI proxy in this build — reminders use the '
                            'built-in templates.',
                    style: TextStyle(
                        fontSize: 11.5, color: mutedColor, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Dark Mode
            const SectionHeader(title: 'Appearance'),
            AppCard(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Dark Mode',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), // 👈 FIXED
                    ),
                    subtitle: Text(
                      'Toggle between light and dark themes.',
                      style: TextStyle(fontSize: 11.5, color: mutedColor), // 👈 FIXED
                    ),
                    value: _isDarkMode,
                    activeTrackColor: AppColors.primary,
                    onChanged: (bool value) async {
                      setState(() => _isDarkMode = value);
                      final prefs = ref.read(sharedPreferencesProvider);
                      await prefs.setBool('smartpayla_theme_dark', value);
                      ref.read(themeModeProvider.notifier).state = value;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tone Selection
            const SectionHeader(title: 'AI Reminder Tone'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default tone',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), // 👈 FIXED
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how the AI should write your payment reminders.',
                    style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4), // 👈 FIXED
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ReminderTone>(
                    initialValue: _tone,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    items: [
                      for (final tone in ReminderTone.values)
                        DropdownMenuItem(
                          value: tone,
                          child: Text(tone.label, style: TextStyle(color: textColor)),
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
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(settingsProvider.notifier).setDefaultTone(_tone);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Default reminder tone saved.')),
                        );
                      },
                      child: const Text('Save default tone'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Commission Rate
            const SectionHeader(title: 'Commission'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Commission rate',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), // 👈 FIXED
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Applied to fully paid transactions.',
                    style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4), // 👈 FIXED
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rateController,
                          style: TextStyle(color: textColor),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Rate',
                            labelStyle: TextStyle(color: mutedColor),
                            suffixText: '%',
                            suffixStyle: TextStyle(color: textColor),
                            filled: true,
                            fillColor: inputFillColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final value = double.tryParse(_rateController.text.replaceAll(',', '').trim());
                          
                          if (value == null || value < 0 || value > 100) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Enter a rate between 0 and 100.')),
                            );
                            return;
                          }
                          
                          await ref.read(settingsProvider.notifier).setCommissionRate(value / 100);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Commission rate saved at ${value.toStringAsFixed(1)}%.')),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            
            const SectionHeader(title: 'Account'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ref.watch(authStateProvider).valueOrNull == null
                        ? 'No account signed in — running on the local ledger.'
                        : 'Signing out returns to the login screen. Cloud sync stops until you sign in again.',
                    style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: ref.watch(authStateProvider).valueOrNull == null
                          ? null
                          : _confirmLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Log out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: BorderSide(color: AppColors.red.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
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
                  InfoRow(label: 'Build', value: 'Increment 4 · local + cloud + AI'),
                  InfoRow(label: 'Framework', value: 'Flutter · Material 3'),
                  InfoRow(label: 'Currency', value: 'Malaysian Ringgit (RM)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}