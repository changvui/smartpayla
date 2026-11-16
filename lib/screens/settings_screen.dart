import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';

import 'package:image_picker/image_picker.dart';

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

            // Payment (DuitNow QR shown to customers)
            const SectionHeader(title: 'Payment'),
            const _PaymentSettingsCard(),
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
/// DuitNow QR and payee details. Whatever is set here is embedded in every
/// customer statement, so the agent uploads the picture once.
class _PaymentSettingsCard extends ConsumerStatefulWidget {
  const _PaymentSettingsCard();

  @override
  ConsumerState<_PaymentSettingsCard> createState() =>
      _PaymentSettingsCardState();
}

class _PaymentSettingsCardState extends ConsumerState<_PaymentSettingsCard> {
  late final TextEditingController _shop;
  late final TextEditingController _payee;
  late final TextEditingController _bank;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _shop = TextEditingController(text: settings.shopName);
    _payee = TextEditingController(text: settings.payeeName);
    _bank = TextEditingController(text: settings.bankNote);
  }

  @override
  void dispose() {
    _shop.dispose();
    _payee.dispose();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final settings = ref.watch(settingsProvider);
    final qr = settings.paymentQr;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DuitNow QR',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Shown on the customer payment page. Screenshot the “Receive” '
            'code from TNG eWallet or your banking app, and crop it close to '
            'the QR — wide margins make the code small on a phone.',
            style: TextStyle(fontSize: 11.5, color: muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: qr == null || qr.isEmpty
                    ? Icon(Icons.qr_code_2_rounded, color: muted)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(
                            qr.substring(qr.indexOf(',') + 1),
                          ),
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickQr,
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: Text(
                        qr == null || qr.isEmpty ? 'Upload QR' : 'Replace QR',
                      ),
                    ),
                    if (qr != null && qr.isNotEmpty)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => ref
                                  .read(settingsProvider.notifier)
                                  .clearPaymentQr(),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.red,
                        ),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _shop,
            decoration: const InputDecoration(
              labelText: 'Shop name',
              hintText: 'Kedai Ah Seng',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _payee,
            decoration: const InputDecoration(
              labelText: 'Payee name (as shown on the transfer)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bank,
            decoration: const InputDecoration(
              labelText: 'Bank details / note (optional)',
              hintText: 'Maybank 1234-5678-9012',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _saveDetails,
              child: const Text('Save payment details'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDetails() async {
    setState(() => _busy = true);
    await ref
        .read(settingsProvider.notifier)
        .setPaymentDetails(
          shopName: _shop.text.trim().isEmpty
              ? 'SmartPayLA'
              : _shop.text.trim(),
          payeeName: _payee.text.trim(),
          bankNote: _bank.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment details saved'),
        backgroundColor: AppColors.green,
      ),
    );
  }

  Future<void> _pickQr() async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 700,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await ref
          .read(settingsProvider.notifier)
          .setPaymentDetails(paymentQr: dataUri);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR saved — it will appear on every statement'),
          backgroundColor: AppColors.green,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not read the image: $error'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
