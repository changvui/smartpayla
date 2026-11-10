import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/receipt_scanner.dart';
import '../services/scanned_bill.dart';
import '../theme.dart';
import '../utils/platform_image.dart';
import '../widgets/common.dart';

/// Scan a cash bill / invoice with a vision model and hand the values back to
/// the "add transaction" form.
///
/// Pops with a [ScannedBill] when the agent confirms, or with `null` when they
/// back out. Nothing is saved here, so an unreadable photo can never create a
/// half-filled transaction.
class OcrScannerScreen extends StatefulWidget {
  const OcrScannerScreen({super.key});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> {
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  bool _busy = false;
  String? _error;
  ScannedBill? _result;

  Future<void> _pickImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        // Smaller payload = faster vision call. A bill is still perfectly
        // readable at 1280 px, and the base64 body shrinks by roughly half.
        imageQuality: 72,
        maxWidth: 1280,
      );
    } catch (e) {
      setState(() => _error = 'Could not open the picker: $e');
      return;
    }
    if (picked == null) return;
    final file = picked;

    setState(() {
      _imagePath = file.path;
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final bill = await ReceiptScanner().scan(
        bytes: bytes,
        mimeType: file.mimeType ?? 'image/jpeg',
        path: file.path,
      );
      if (!mounted) return;
      setState(() {
        _result = bill;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF2C2C2C) : AppColors.background;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _imagePath == null
                      ? Theme.of(context).dividerColor
                      : Colors.transparent,
                  width: 2,
                ),
                image: _imagePath != null
                    ? DecorationImage(
                        image: platformImageProvider(_imagePath!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _imagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 46, color: mutedColor),
                        const SizedBox(height: 10),
                        Text(
                          'Photograph the cash bill or invoice',
                          style: TextStyle(color: mutedColor, fontSize: 13),
                        ),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            if (_busy)
              AppCard(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(
                      'Reading the bill…',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This usually takes 10–20 seconds.',
                      style: TextStyle(fontSize: 11.5, color: mutedColor),
                    ),
                  ],
                ),
              ),

            if (!_busy && _error != null) _MessageCard(
              icon: Icons.error_outline_rounded,
              color: AppColors.red,
              title: 'Could not read this image',
              message: _error!,
            ),

            if (!_busy && _result != null && !_result!.isBill)
              const _MessageCard(
                icon: Icons.image_not_supported_outlined,
                color: AppColors.amber,
                title: 'That does not look like a cash bill',
                message:
                    'SmartPayLA only reads cash bills, invoices and receipts. '
                    'Try again with the bill flat, well lit and fully in frame.',
              ),

            if (!_busy && _result != null && _result!.isBill) ...[
              const SectionHeader(title: 'Detected details'),
              AppCard(
                child: Column(
                  children: [
                    InfoRow(
                      label: 'Customer',
                      value: _result!.partyName ?? 'Not detected',
                    ),
                    const SizedBox(height: 8),
                    if (_result!.vendor != null &&
                        _result!.vendor != _result!.customer) ...[
                      InfoRow(label: 'Issued by', value: _result!.vendor!),
                      const SizedBox(height: 8),
                    ],
                    InfoRow(
                      label: 'Total',
                      value: _result!.amount == null
                          ? 'Not detected'
                          : money(_result!.amount!),
                    ),
                    const SizedBox(height: 8),
                    InfoRow(
                      label: 'Bill date',
                      value: _result!.date == null
                          ? 'Not detected'
                          : DateFormat('d MMM yyyy').format(_result!.date!),
                    ),
                    const SizedBox(height: 8),
                    InfoRow(
                      label: 'Reference',
                      value: _result!.reference ?? 'Not detected',
                    ),
                    if (_result!.note != null) ...[
                      const SizedBox(height: 8),
                      InfoRow(label: 'Items', value: _result!.note!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _result),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Use these details'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can still edit every field on the next screen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: mutedColor),
              ),
            ],

            if (!_busy && _result == null && _error == null) ...[
              const SizedBox(height: 4),
              Text(
                'The photo is sent to a vision model to read the total, date and '
                'vendor. Nothing is saved until you confirm.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
