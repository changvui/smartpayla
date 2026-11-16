import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/qr_saver.dart';

/// The payment QR on a page of its own: full width, pinch to zoom, and a save
/// action, because a customer often hands the phone over the counter to be
/// scanned.
class QrFullScreenScreen extends StatelessWidget {
  const QrFullScreenScreen({
    super.key,
    required this.dataUri,
    this.amountLabel,
    this.reference,
  });

  final String dataUri;
  final String? amountLabel;
  final String? reference;

  Uint8List _bytes() {
    final comma = dataUri.indexOf(',');
    return base64Decode(comma >= 0 ? dataUri.substring(comma + 1) : dataUri);
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = saveDataUri(dataUri, 'duitnow-qr.png');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'QR saved to your downloads'
              : 'Long-press the QR and choose “Save image”',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF0F172A);
    const muted = Color(0xFF64748B);
    const blue = Color(0xFF1D4ED8);

    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
        ).copyWith(onSurface: ink, onSurfaceVariant: muted),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ink,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Scan to pay',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: 'Save QR',
              onPressed: () => _save(context),
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.memory(_bytes(), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                children: [
                  if (amountLabel != null)
                    Text(
                      amountLabel!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  if (reference != null && reference!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Reference: $reference',
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _save(context),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Save QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: blue,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: blue,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pinch to zoom. Works with any banking app or TNG.',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
