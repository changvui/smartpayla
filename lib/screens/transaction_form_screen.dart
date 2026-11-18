import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/payment.dart';
import '../models/transaction.dart';
import '../services/scanned_bill.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../utils/names.dart';
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

  /// A name the scanner read off a bill that has no customer profile yet. The
  /// form never stores it: the agent creates the profile first.
  String? _unknownScannedCustomer;

  /// Evidence for the money collected at the counter when the sale is saved as
  /// already paid. A paid bill without proof of payment is a claim, not a
  /// record.
  String? _paymentProof;
  bool _uploadingProof = false;
  bool _paymentProofMissing = false;
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

  /// Why no photograph exists. A transaction needs one or the other.
  String? _evidenceReason;

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

    // The scanned lines replace the empty rows, so a bill with three items
    // arrives as three rows instead of one total the agent has to split.
    final previousLines = <_LineItem>[];
    if (scanned.items.isNotEmpty) {
      previousLines.addAll(_lines);
      _lines.clear();
      for (final item in scanned.items) {
        final qty = item.qty ?? 1;
        final price = item.linePrice;
        _lines.add(
          _LineItem(
            description: item.description,
            qty: qty == qty.roundToDouble()
                ? qty.toInt().toString()
                : qty.toString(),
            price: price == null ? '' : price.toStringAsFixed(2),
          ),
        );
      }
    }

    setState(() {
      final party = scanned.partyName;
      if (party != null && _customer.text.trim().isEmpty) {
        // Only a name that already exists as a profile may be selected. A new
        // name is held aside and offered as a "create profile" action, because
        // a customer that exists only on one bill breaks the statement link.
        final match = _findProfile(party);
        if (match != null) {
          _customer.text = match.name;
        } else {
          _unknownScannedCustomer = party;
        }
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

    if (previousLines.isNotEmpty) {
      // The old controllers are still attached to the widgets until the frame
      // above has been laid out; dispose them afterwards.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final line in previousLines) {
          line.dispose();
        }
      });
      _onLineChanged();
      // The bill's printed total is authoritative: the line amounts can differ
      // by a rounding cent, and a discount would never appear as a row.
      if (scanned.amount != null) {
        _total.text = scanned.amount!.toStringAsFixed(2);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Filled from the scanned bill — please check every field.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// The customer profile whose name matches [name] after normalisation.
  Customer? _findProfile(String name) {
    final wanted = normaliseCustomerName(name).toLowerCase();
    if (wanted.isEmpty) return null;
    for (final customer in ref.read(customerProvider).valueOrNull ?? const []) {
      if (normaliseCustomerName(customer.name).toLowerCase() == wanted) {
        return customer;
      }
    }
    return null;
  }

  /// Create the profile the scanner read, then select it.
  Future<void> _createScannedProfile() async {
    final name = _unknownScannedCustomer;
    if (name == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notifier = ref.read(customerProvider.notifier);
      await notifier.addCustomer(
        Customer(
          id: '',
          name: normaliseCustomerName(name),
          phone: 'No phone',
          address: 'Not set',
        ),
      );
      if (!mounted) return;
      setState(() {
        _customer.text = normaliseCustomerName(name);
        _unknownScannedCustomer = null;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Profile created for ${normaliseCustomerName(name)}.'),
          backgroundColor: AppColors.green,
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not create the profile: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
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

  /// One item row, laid out as two lines so it fits a 360 dp phone:
  ///   [ description ................................  ✨ ]
  ///   [ Qty ]   [ Price (RM) ]        RM 30.00
  Widget _buildLineRow(BuildContext context, int index) {
    final line = _lines[index];
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final textColor = Theme.of(context).colorScheme.onSurface;

    final qty = double.tryParse(line.qty.text.trim()) ?? 0;
    final price =
        double.tryParse(line.price.text.replaceAll(',', '.').trim()) ?? 0;
    final amount = qty * price;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                  hint: 'What was sold?',
                ),
              ),
            ),
            IconButton(
              tooltip:
                  _lines.length == 1 ? 'Keep at least one item' : 'Remove item',
              onPressed: _lines.length == 1 ? null : () => _removeLine(index),
              icon: Icon(Icons.close_rounded, size: 18, color: mutedColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: TextFormField(
                controller: line.qty,
                onChanged: (_) => _onLineChanged(),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _decoration(context, 'Qty'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: line.price,
                onChanged: (_) => _onLineChanged(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
                ],
                decoration: _decoration(context, 'Price (RM)'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  money(amount),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amount > 0 ? textColor : mutedColor,
                  ),
                ),
              ),
            ),
          ],
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
      // The photo is stored inside the transaction document as a compressed
      // data URI, so the bill follows the account to another device. 900 px at
      // quality 60 is still readable for a handwritten bill and keeps the record
      // around 80-150 KB, well inside Firestore's 1 MiB document limit.
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 900,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _uploadingBill = true);

      final bytes = await picked.readAsBytes();
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      if (!mounted) return;
      setState(() {
        _receiptPath = dataUri;
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

  /// The proof of payment for a sale that is collected immediately. Cash needs a
  /// photograph of the note or the signed bill; a transfer needs a screenshot.
  Future<void> _attachPaymentProof(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 900,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _uploadingProof = true);

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _paymentProof = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _uploadingProof = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingProof = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach the payment proof: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  void _removePaymentProof() => setState(() => _paymentProof = null);

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

  /// A paid sale needs both halves of the story: the bill (what was sold and
  /// for how much) and the proof of payment (that the money arrived). One
  /// document alone leaves a hole - a bill shows a price, not a receipt.
  bool get _paymentProofRequired =>
      _status == PaymentStatus.paid && widget.transaction == null;

  /// A paid sale cannot fall back to the "no photo, recorded reason" path: the
  /// reason explains a missing bill, it does not prove a payment.
  bool get _billPhotoRequired =>
      _status == PaymentStatus.paid && widget.transaction == null;

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
                      // Read-only on purpose: the customer is a record in the
                      // Customers list, not a string typed per bill. Free text
                      // used to split one person into several "customers" and
                      // broke the statement link and the claim matching.
                      readOnly: true,
                      onTap: _pickCustomer,
                      decoration: _decoration(
                        context,
                        'Customer *',
                        hint: 'Tap to choose from the Customers list',
                        suffixIcon: IconButton(
                          tooltip: 'Pick from customers',
                          icon: const Icon(Icons.people_outline_rounded, size: 20),
                          onPressed: _pickCustomer,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Choose a customer';
                        }
                        return null;
                      },
                    ),
                    if (_unknownScannedCustomer != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.amber.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: AppColors.amber,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _unknownScannedCustomer == null
                                    ? ''
                                    : 'The bill names '
                                          '"$_unknownScannedCustomer", which has '
                                          'no profile yet.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _createScannedProfile,
                              child: const Text('Create'),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            if (i != _lines.length - 1)
                              const Divider(height: 22),
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
                title: 'Bill photo (what was sold)',
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
                            'Saving the photoÃ¢â‚¬Â¦',
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

              // A sale collected in full needs proof of the money, for the same
              // reason a credit sale needs the bill: without it the payment
              // history is an assertion nobody can check.
              if (widget.transaction == null &&
                  _status != PaymentStatus.unpaid) ...[
                const SizedBox(height: 20),
                const _SectionLabel(
                  icon: Icons.verified_outlined,
                  title: 'Payment history evidence',
                ),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _paymentProofRequired
                            ? 'Required — a paid sale needs both the cash bill '
                                  'photo and the proof of payment: a receipt, '
                                  'the signed bill, or the transfer screenshot.'
                            : 'Optional — add a proof for the payment history '
                                  'entry.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: mutedColor,
                          height: 1.4,
                        ),
                      ),
                      if (_paymentProofRequired) ...[
                        const SizedBox(height: 10),
                        _EvidenceCheck(
                          label: 'Cash bill photo',
                          done: _receiptPath != null,
                        ),
                        const SizedBox(height: 4),
                        _EvidenceCheck(
                          label: 'Payment evidence',
                          done: _paymentProof != null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_uploadingProof)
                        const Center(child: CircularProgressIndicator())
                      else if (_paymentProof == null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _attachPaymentProof(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined,
                                    size: 18),
                                label: const Text('Camera'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _attachPaymentProof(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined,
                                    size: 18),
                                label: const Text('Gallery'),
                              ),
                            ),
                          ],
                        ),
                        if (_paymentProofMissing && _paymentProofRequired)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Attach the payment proof before saving a paid '
                              'sale.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                      ] else
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(
                                  _paymentProof!.split(',').last,
                                ),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Payment proof attached.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: _removePaymentProof,
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: mutedColor),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
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
                title: 'Reference documents (at least one required)',
              ),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _invoice,
                      decoration: _decoration(
                        context,
                        'Invoice number *',
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
                        'Cash bill number *',
                        hint: 'e.g. CB-0912',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          final now = DateTime.now();
                          final suffix = Random().nextInt(9000) + 1000;
                          final y = now.year.toString().substring(2);
                          final m = now.month.toString().padLeft(2, '0');
                          final d = now.day.toString().padLeft(2, '0');
                          setState(() {
                            _cashBill.text = 'CB-$y$m$d-$suffix';
                            _cashBillDate ??= now;
                          });
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Generate a bill number'),
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

  /// Asked once, when a bill is saved without a photograph. Returns null when
  /// the agent cancels, which also cancels the save.
  Future<String?> _askEvidenceReason() async {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('No bill photo'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'A transaction needs either a photo of the paper bill or a '
              'recorded reason. Pick the reason that applies.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
          for (final reason in const [
            'Phone order',
            'Bill not issued',
            'Customer kept the bill',
            'Photo not possible',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(reason),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(reason),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Cancel — I will take a photo'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // A sale must point at a customer profile, not at a typed name: the profile
    // is what the statement link, the claim matching and the Customers tab use.
    if (_findProfile(_customer.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create this customer on the Customers page first, then pick them '
            'here.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    // A paid sale needs the bill photograph itself. The "recorded reason" path
    // exists for bills that were never printed, not for sales where the money
    // is already in hand.
    if (_billPhotoRequired && _receiptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attach the cash bill photo — a paid sale needs both the bill and '
            'the proof of payment.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    // Every debt must be backed by something: a photograph of the paper bill or
    // a recorded reason why there is none. A blank record is not accepted.
    if (_receiptPath == null && _evidenceReason == null) {
      final reason = await _askEvidenceReason();
      if (reason == null) return;
      setState(() => _evidenceReason = reason);
    }
    // A sale must be identifiable: at least one reference number, and it must
    // not already belong to another bill.
    if (!mounted) return;
    final billNo = _cashBill.text.trim().isEmpty
        ? _invoice.text.trim()
        : _cashBill.text.trim();
    if (billNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter an invoice number or a cash bill number so the sale can be '
            'tracked.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    final clash = (ref.read(transactionsProvider).valueOrNull ?? const [])
        .any(
          (t) =>
              t.id != widget.transaction?.id &&
              (t.cashBillNumber == billNo || t.invoiceNumber == billNo),
        );
    if (clash) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reference $billNo is already used by another bill.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    // A paid sale must carry something that proves the money moved: the cash
    // bill photograph, or a separate payment proof.
    if (_paymentProofRequired && _paymentProof == null) {
      setState(() => _paymentProofMissing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attach the payment evidence: a receipt, the signed bill or the '
            'transfer screenshot.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    final total = _amount(_total.text)!;
    final advance = _effectiveAdvance;
    final now = DateTime.now();
    final existing = widget.transaction;

        final transaction = Transaction(
      id: existing?.id ?? const Uuid().v4(),
      customerName: normaliseCustomerName(_customer.text),
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
      receiptImagePath: _receiptPath,
      evidenceReason: _evidenceReason,
    );

    setState(() => _saving = true);
    try {
      await ref.read(transactionsProvider.notifier).save(transaction);
      // An advance typed on the form becomes a real payment record, so the
      // ledger stays the single source of truth for the balance.
      if (existing == null && advance > 0) {
        await ref
            .read(paymentServiceProvider)
            .record(
              ownerUid: ref.read(dataOwnerProvider),
              transaction: transaction,
              amount: advance,
              method: PaymentMethod.cash,
              note: advance >= total
                  ? 'Paid in full at sale'
                  : 'Advance paid at sale',
              proofImage: _paymentProof,
            );
      }
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

/// One line in the "both required" checklist shown inside the evidence box.
class _EvidenceCheck extends StatelessWidget {
  const _EvidenceCheck({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.green : AppColors.red;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.cancel_outlined,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          done ? '  attached' : '  missing',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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

  /// Creates a customer profile (name + phone) so the sale is always attached to
  /// a real record instead of a free-typed string. A name that already exists,
  /// ignoring case and spacing, is reused rather than duplicated.
  Future<String?> _createCustomer(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final existing = ref.read(customerProvider).valueOrNull ?? const [];

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
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
            onPressed: () {
              final name = normaliseCustomerName(nameController.text);
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return null;

    String key(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final match = existing
        .where((c) => key(c.name) == key(result))
        .firstOrNull;
    if (match != null) return match.name;

    await ref
        .read(customerProvider.notifier)
        .addCustomer(
          Customer(
            id: const Uuid().v4(),
            name: result,
            phone: phoneController.text.trim().isEmpty
                ? 'No phone'
                : phoneController.text.trim(),
            address: 'Not set',
          ),
        );
    return result;
  }

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
                    itemCount: filtered.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            child: Icon(Icons.add_rounded, color: Colors.white),
                          ),
                          title: const Text(
                            'New customer',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'Saved to the Customers list',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          onTap: () async {
                            final created = await _createCustomer(context, ref);
                            if (created == null) return;
                            if (context.mounted) {
                              Navigator.of(context).pop(created);
                            }
                          },
                        );
                      }
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
