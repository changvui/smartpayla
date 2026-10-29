import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.transaction});

  final Transaction? transaction;

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

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _customer = TextEditingController(text: t?.customerName ?? '');
    _item = TextEditingController(text: t?.itemDescription ?? '');
    _total = TextEditingController(text: _numberText(t?.totalAmount ?? 0));
    _advance = TextEditingController(text: _numberText(t?.advancePaid ?? 0));
    _invoice = TextEditingController(text: t?.invoiceNumber ?? '');
    _cashBill = TextEditingController(text: t?.cashBillNumber ?? '');
    _status = t?.status ?? PaymentStatus.unpaid;
    _dueDate = t?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    _finishDate = t?.finishDate;
    _claimExpiry = t?.claimExpiry;
    _invoiceDate = t?.invoiceDate;
    _cashBillDate = t?.cashBillDate;
    _total.addListener(_onTotalChanged);
  }

  @override
  void dispose() {
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
              _SectionLabel(
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
                        'Customer name',
                        hint: 'e.g. Ahmad Faizal',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the customer name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _item,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      minLines: 1,
                      decoration: _decoration(
                        'Item or service',
                        hint: 'e.g. Catering order — 80 pax',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel(
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
                        color: AppColors.primary.withValues(alpha: 0.06),
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
                          const Text(
                            'Balance due',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
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
              _SectionLabel(
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
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel(
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
              _SectionLabel(
                icon: Icons.description_outlined,
                title: 'Reference documents (optional)',
              ),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _invoice,
                      decoration: _decoration(
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
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
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
    String label, {
    String? hint,
    String? helper,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      filled: true,
      fillColor: AppColors.background,
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
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.background,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          suffixIcon: onClear != null
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 17),
                )
              : const Icon(Icons.calendar_today_outlined, size: 17),
        ),
        child: Text(
          value == null ? 'Select date' : shortDate(value),
          style: TextStyle(
            fontSize: 13,
            color: value == null ? AppColors.muted : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
