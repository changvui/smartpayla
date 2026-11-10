import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../services/receipt_store.dart';
import '../services/scanned_bill.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../utils/platform_image.dart';
import '../widgets/common.dart';
import 'ocr_scanner_screen.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key, 
    this.transaction,
    this.initialAmount, 
    this.initialDate,   
    this.initialImagePath, // 👈 ADDED
  });

  final Transaction? transaction;
  final double? initialAmount;
  final DateTime? initialDate;
  final String? initialImagePath; // 👈 ADDED
// ...

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _customer;
  late final TextEditingController _item;
  late final TextEditingController _total;
  late final TextEditingController _advance;
  late final TextEditingController _invoice;
  late final TextEditingController _cashBill;

  late PaymentStatus _status;
  late DateTime _dueDate;
  DateTime? _finishDate;
  DateTime? _claimExpiry;
  DateTime? _invoiceDate;
  DateTime? _cashBillDate;
  bool _saving = false;
  bool _syncingAmount = false;

  /// One row per printed item. Each row is description + quantity + unit price,
  /// and their product feeds the transaction total, so the agent adds numbers
  /// the same way the cash bill is written.
  final List<_LineItem> _lines = [];

  /// Path/URL of the attached bill photo, if any.
  String? _receiptPath;

  /// True while the photo is being saved to the app's storage.
  bool _uploadingBill = false;

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    
    // 👇 Check for OCR initial values
    final startAmount = t?.totalAmount ?? widget.initialAmount ?? 0;
    final startDate = t?.dueDate ?? widget.initialDate;

    _customer = TextEditingController(text: t?.customerName ?? '');
    _item = TextEditingController(text: t?.itemDescription ?? '');
    _total = TextEditingController(text: _numberText(startAmount));
    _advance = TextEditingController(text: _numberText(t?.advancePaid ?? 0));
    _invoice = TextEditingController(text: t?.invoiceNumber ?? '');
    _cashBill = TextEditingController(text: t?.cashBillNumber ?? '');
    _status = t?.status ?? PaymentStatus.unpaid;
    
    // Set the date from OCR if available, otherwise default to 7 days
    _dueDate = startDate ?? DateTime.now().add(const Duration(days: 7));
    
    _finishDate = t?.finishDate;
    _claimExpiry = t?.claimExpiry;
    _invoiceDate = t?.invoiceDate;
    _cashBillDate = t?.cashBillDate;
    _lines.add(
      t == null
          ? _LineItem()
          : _LineItem(
              description: t.itemDescription,
              qty: '1',
              price: t.totalAmount > 0 ? _numberText(t.totalAmount) : '',
            ),
    );
    _total.addListener(_onTotalChanged);
    _receiptPath = widget.initialImagePath ?? t?.receiptImagePath;
  }

  /// Open the scanner and copy whatever was read into this form.
  ///
  /// Nothing is overwritten blindly: existing text wins, and the agent still
  /// has to press Save, so a misread bill can be corrected before it is stored.
  Future<void> _scanReceipt() async {
    final scanned = await Navigator.of(context).push<ScannedBill>(
      MaterialPageRoute(builder: (_) => const OcrScannerScreen()),
    );
    if (scanned == null || !mounted) return;

    setState(() {
      final party = scanned.partyName;
      if (party != null && _customer.text.trim().isEmpty) {
        _customer.text = party;
      }
      if (scanned.amount != null) {
        _total.text = scanned.amount!.toStringAsFixed(2);
      }
      if (scanned.note != null && _item.text.trim().isEmpty) {
        _item.text = scanned.note!;
      }
      if (scanned.reference != null && _cashBill.text.trim().isEmpty) {
        _cashBill.text = scanned.reference!;
      }
      if (scanned.date != null) {
        _cashBillDate = scanned.date;
        _invoiceDate ??= scanned.date;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Filled from the scanned bill — please check every field.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Pick a saved customer instead of retyping the name.
  ///
  /// The Customers tab is the source of truth; typing a brand-new name still
  /// works (some sales are one-off walk-ins that never need a profile).
  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomerPickerSheet(),
    );
    if (picked == null || picked.trim().isEmpty) return;
    setState(() => _customer.text = picked.trim());
  }

  /// Sum of quantity × unit price across every line.
  double get _linesTotal {
    var total = 0.0;
    for (final line in _lines) {
      final qty = double.tryParse(line.qty.text.trim()) ?? 0;
      final price =
          double.tryParse(line.price.text.replaceAll(',', '.').trim()) ?? 0;
      total += qty * price;
    }
    return total;
  }

  void _addLine() {
    setState(() => _lines.add(_LineItem()));
  }

  void _removeLine(int index) {
    final removed = _lines.removeAt(index);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    _onLineChanged();
  }

  /// Keep the stored description and the total in step with the item rows.
  void _onLineChanged() {
    final parts = <String>[];
    for (final line in _lines) {
      final description = line.desc.text.trim();
      if (description.isEmpty) continue;
      final qty = double.tryParse(line.qty.text.trim()) ?? 1;
      parts.add(qty > 1 ? '$description ×${_numberText(qty)}' : description);
    }
    if (parts.isNotEmpty) {
      _item.text = parts.join(', ');
    }

    final total = _linesTotal;
    if (total > 0) {
      _total.text = total.toStringAsFixed(2);
    }
    setState(() {});
  }

  Widget _buildLineRow(BuildContext context, int index) {
    final line = _lines[index];
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: line.desc,
            onChanged: (_) => _onLineChanged(),
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration(
              context,
              'Item ${index + 1}',
              hint: 'Description',
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 58,
          child: TextFormField(
            controller: line.qty,
            onChanged: (_) => _onLineChanged(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _decoration(context, 'Qty'),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: TextFormField(
            controller: line.price,
            onChanged: (_) => _onLineChanged(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
            ],
            decoration: _decoration(context, 'Price'),
          ),
        ),
        IconButton(
          tooltip: _lines.length == 1 ? 'Keep at least one item' : 'Remove item',
          onPressed: _lines.length == 1 ? null : () => _removeLine(index),
          icon: Icon(Icons.close_rounded, size: 18, color: mutedColor),
        ),
      ],
    );
  }

  /// Attach a photo of the paper bill to this transaction.
  ///
  /// The photo is persisted through `ReceiptStore`: on a phone it is copied into
  /// the app's documents folder (cache clearing cannot delete it), on the web it
  /// is inlined as base64 so a page reload keeps showing it. A `blob:` URL would
  /// die with the tab, and a raw cache path can be purged by the OS.
  Future<void> _attachBill(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: kIsWeb ? 55 : 70,
        maxWidth: kIsWeb ? 1000 : 1400,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _uploadingBill = true);

      final stored = await const ReceiptStore().store(picked);

      if (!mounted) return;
      setState(() {
        _receiptPath = stored;
        _uploadingBill = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingBill = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach the photo: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  void _removeBill() => setState(() => _receiptPath = null);

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _total.removeListener(_onTotalChanged);
    _customer.dispose();
    _item.dispose();
    _total.dispose();
    _advance.dispose();
    _invoice.dispose();
    _cashBill.dispose();
    super.dispose();
  }

  double? _amount(String raw) =>
      double.tryParse(raw.replaceAll(',', '').trim());

  String _numberText(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  double get _totalValue => _amount(_total.text) ?? 0;

  double get _effectiveAdvance {
    switch (_status) {
      case PaymentStatus.unpaid:
        return 0;
      case PaymentStatus.paid:
        return _totalValue;
      case PaymentStatus.partial:
        return (_amount(_advance.text) ?? 0).clamp(0, _totalValue);
    }
  }

  double get _balance =>
      (_totalValue - _effectiveAdvance).clamp(0, _totalValue);

  void _onTotalChanged() {
    if (_syncingAmount) return;
    if (_status == PaymentStatus.paid) {
      _syncingAmount = true;
      _advance.text = _numberText(_totalValue);
      _syncingAmount = false;
    } else if (_status == PaymentStatus.unpaid) {
      _syncingAmount = true;
      _advance.text = '0';
      _syncingAmount = false;
    } else {
      final current = _amount(_advance.text) ?? 0;
      if (current > _totalValue) {
        _syncingAmount = true;
        _advance.text = _numberText(_totalValue);
        _syncingAmount = false;
      }
    }
    setState(() {});
  }

  void _setStatus(PaymentStatus status) {
    setState(() {
      _status = status;
      if (status == PaymentStatus.paid) {
        _advance.text = _numberText(_totalValue);
      } else if (status == PaymentStatus.unpaid) {
        _advance.text = '0';
      } else if ((_amount(_advance.text) ?? 0) <= 0 ||
          (_amount(_advance.text) ?? 0) >= _totalValue) {
        _advance.text = _numberText(_totalValue / 2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: PageWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              // Scan entry point sits here, right above the fields it fills, so
              // it is obvious what the button is for.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _scanReceipt,
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Scan a cash bill to fill this form'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const _SectionLabel(
                icon: Icons.person_outline_rounded,
                title: 'Customer & item',
              ),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _customer,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration(
                        context,
                        'Customer name',
                        hint: 'e.g. Ahmad Faizal',
                        suffixIcon: IconButton(
                          tooltip: 'Pick from customers',
                          icon: const Icon(Icons.people_outline_rounded, size: 20),
                          onPressed: _pickCustomer,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the customer name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    // Item lines: description + qty + unit price, like the
                    // printed cash bill. The total below is their sum.
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _lines.length; i++) ...[
                            _buildLineRow(context, i),
                            if (i != _lines.length - 1) const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add item'),
                              ),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'Subtotal ${money(_linesTotal)}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.photo_camera_outlined,
                title: 'Bill photo',
              ),
              AppCard(
                child: _uploadingBill
                    ? Row(
                        children: [
                          const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Saving the photo…',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : _receiptPath == null
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _attachBill(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined,
                                  size: 18),
                              label: const Text('Camera'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _attachBill(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined,
                                  size: 18),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: platformImage(_receiptPath!),
                            ),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    _attachBill(ImageSource.gallery),
                                icon: const Icon(Icons.sync_rounded, size: 18),
                                label: const Text('Replace'),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _removeBill,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Remove'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.payments_outlined,
                title: 'Amounts',
              ),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*[.,]?\d{0,2}'),
                        ),
                      ],
                      decoration: _decoration(
                        context,
                        'Total amount (RM)',
                        hint: '0.00',
                      ),
                      validator: (value) {
                        final parsed = _amount(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a total greater than 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _advance,
                      enabled: _status == PaymentStatus.partial,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*[.,]?\d{0,2}'),
                        ),
                      ],
                      decoration: _decoration(
                        context,
                        'Advance / amount paid (RM)',
                        hint: '0.00',
                        helper: _status == PaymentStatus.partial
                            ? 'Enter the amount received so far'
                            : 'Set automatically by the payment status',
                      ),
                      validator: (value) {
                        if (_status != PaymentStatus.partial) return null;
                        final parsed = _amount(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'Enter the amount received';
                        }
                        if (parsed >= _totalValue) {
                          return 'Partial payment must be less than the total';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Balance due',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: mutedColor,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            money(_balance),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.flag_outlined,
                title: 'Payment status',
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<PaymentStatus>(
                        segments: const [
                          ButtonSegment(
                            value: PaymentStatus.unpaid,
                            label: Text('Unpaid'),
                          ),
                          ButtonSegment(
                            value: PaymentStatus.partial,
                            label: Text('Partial'),
                          ),
                          ButtonSegment(
                            value: PaymentStatus.paid,
                            label: Text('Paid'),
                          ),
                        ],
                        selected: {_status},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          _setStatus(selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _status == PaymentStatus.paid
                          ? 'The full amount is treated as collected.'
                          : _status == PaymentStatus.partial
                              ? 'Part of the amount has been collected; the balance stays open.'
                              : 'No payment has been collected yet.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: mutedColor,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.event_outlined,
                title: 'Dates',
              ),
              AppCard(
                child: Column(
                  children: [
                    _DateField(
                      label: 'Due date',
                      value: _dueDate,
                      onTap: () => _pickDate(
                        current: _dueDate,
                        onPicked: (value) => setState(() => _dueDate = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Finish / delivery date',
                      value: _finishDate,
                      onTap: () => _pickDate(
                        current: _finishDate,
                        onPicked: (value) =>
                            setState(() => _finishDate = value),
                      ),
                      onClear: _finishDate == null
                          ? null
                          : () => setState(() => _finishDate = null),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Claim expiry',
                      value: _claimExpiry,
                      onTap: () => _pickDate(
                        current: _claimExpiry,
                        onPicked: (value) =>
                            setState(() => _claimExpiry = value),
                      ),
                      onClear: _claimExpiry == null
                          ? null
                          : () => setState(() => _claimExpiry = null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.description_outlined,
                title: 'Reference documents (optional)',
              ),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _invoice,
                      decoration: _decoration(
                        context,
                        'Invoice number',
                        hint: 'e.g. INV-2026-041',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Invoice date',
                      value: _invoiceDate,
                      onTap: () => _pickDate(
                        current: _invoiceDate,
                        onPicked: (value) =>
                            setState(() => _invoiceDate = value),
                      ),
                      onClear: _invoiceDate == null
                          ? null
                          : () => setState(() => _invoiceDate = null),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cashBill,
                      decoration: _decoration(
                        context,
                        'Cash bill number',
                        hint: 'e.g. CB-0912',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Cash bill date',
                      value: _cashBillDate,
                      onTap: () => _pickDate(
                        current: _cashBillDate,
                        onPicked: (value) =>
                            setState(() => _cashBillDate = value),
                      ),
                      onClear: _cashBillDate == null
                          ? null
                          : () => setState(() => _cashBillDate = null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Stored on this device in Increment 1. Cloud sync arrives in Increment 2.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: mutedColor),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Save transaction'),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF2C2C2C) : AppColors.background;
    final borderColor = Theme.of(context).dividerColor;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: borderColor),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: mutedColor),
      hintText: hint,
      hintStyle: TextStyle(color: mutedColor.withValues(alpha: 0.5)),
      helperText: helper,
      helperStyle: TextStyle(color: mutedColor),
      helperMaxLines: 2,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.4),
      ),
    );
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final initial = current ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(2020)) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final total = _amount(_total.text)!;
    final advance = _effectiveAdvance;
    final now = DateTime.now();
    final existing = widget.transaction;

        final transaction = Transaction(
      id: existing?.id ?? const Uuid().v4(),
      customerName: _customer.text.trim(),
      itemDescription: _item.text.trim(),
      totalAmount: total,
      advancePaid: advance,
      dueDate: _dueDate,
      status: _status,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      finishDate: _finishDate,
      claimExpiry: _claimExpiry,
      invoiceNumber: _invoice.text.trim().isEmpty ? null : _invoice.text.trim(),
      invoiceDate: _invoiceDate,
      cashBillNumber:
          _cashBill.text.trim().isEmpty ? null : _cashBill.text.trim(),
      cashBillDate: _cashBillDate,
      // 👇 ADD THIS LINE
      receiptImagePath: _receiptPath,
    );

    setState(() => _saving = true);
    try {
      await ref.read(transactionsProvider.notifier).save(transaction);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Transaction saved.' : 'Changes saved.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $error')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = widget.transaction!.id;
    await ref.read(transactionsProvider.notifier).delete(id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Transaction deleted.')),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF2C2C2C) : AppColors.background;
    final borderColor = Theme.of(context).dividerColor;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: mutedColor),
          filled: true,
          fillColor: fillColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          suffixIcon: onClear != null
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 17),
                )
              : Icon(Icons.calendar_today_outlined, size: 17, color: mutedColor),
        ),
        child: Text(
          value == null ? 'Select date' : shortDate(value),
          style: TextStyle(
            fontSize: 13,
            color: value == null ? mutedColor : textColor,
          ),
        ),
      ),
    );
  }
}
/// Bottom sheet that lists the customers saved in the Customers tab.
///
/// Kept deliberately simple (search + tap) so recording a sale stays fast:
/// typing a new name is still allowed on the form itself for walk-ins.
class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final customersAsync = ref.watch(customerProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                autofocus: false,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search customer',
                  hintStyle: TextStyle(fontSize: 13, color: mutedColor),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
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
            Expanded(
              child: customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load customers: $error',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: mutedColor),
                    ),
                  ),
                ),
                data: (customers) {
                  final filtered = customers.where((customer) {
                    if (_query.isEmpty) return true;
                    final q = _query.toLowerCase();
                    return customer.name.toLowerCase().contains(q) ||
                        customer.phone.toLowerCase().contains(q);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          customers.isEmpty
                              ? 'No customers saved yet.\nAdd them in the Customers tab, or just type a name here.'
                              : 'No customer matches "$_query".',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: mutedColor,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final customer = filtered[index];
                      final initial = customer.name.trim().isEmpty
                          ? '?'
                          : customer.name.trim().substring(0, 1).toUpperCase();
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          customer.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          customer.phone,
                          style: TextStyle(fontSize: 11.5, color: mutedColor),
                        ),
                        onTap: () => Navigator.of(context).pop(customer.name),
                      );
                    },
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

/// One editable row of the item table: description, quantity, unit price.
class _LineItem {
  _LineItem({String description = '', String qty = '1', String price = ''})
      : desc = TextEditingController(text: description),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price);

  final TextEditingController desc;
  final TextEditingController qty;
  final TextEditingController price;

  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
  }
}
