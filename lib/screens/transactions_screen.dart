import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form_screen.dart';

enum _TxFilter { all, unpaid, partial, paid, overdue }

extension on _TxFilter {
  String get label {
    switch (this) {
      case _TxFilter.all:
        return 'All';
      case _TxFilter.unpaid:
        return 'Unpaid';
      case _TxFilter.partial:
        return 'Partial';
      case _TxFilter.paid:
        return 'Paid';
      case _TxFilter.overdue:
        return 'Overdue';
    }
  }

  bool matches(Transaction t) {
    switch (this) {
      case _TxFilter.all:
        return true;
      case _TxFilter.unpaid:
        return t.status == PaymentStatus.unpaid;
      case _TxFilter.partial:
        return t.status == PaymentStatus.partial;
      case _TxFilter.paid:
        return t.isPaid;
      case _TxFilter.overdue:
        return t.isOverdue;
    }
  }
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  _TxFilter _filter = _TxFilter.all;
  String _query = '';
  DateTime? _monthFilter;

  String? get _monthLabel => _monthFilter == null
      ? null
      : DateFormat('MMMM yyyy').format(_monthFilter!);

  bool _matchesMonth(Transaction t) {
    if (_monthFilter == null) return true;
    final date = t.billDate;
    return date.year == _monthFilter!.year && date.month == _monthFilter!.month;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTransactions = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: asyncTransactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load transactions',
          message: '$error',
          action: FilledButton(
            onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
            child: const Text('Try again'),
          ),
        ),
        data: (transactions) {
          final filtered = transactions.where((t) {
            final matchesFilter = _filter.matches(t);
            final q = _query.trim().toLowerCase();
            final matchesQuery = q.isEmpty ||
                t.customerName.toLowerCase().contains(q) ||
                t.itemDescription.toLowerCase().contains(q) ||
                (t.invoiceNumber ?? '').toLowerCase().contains(q) ||
                (t.cashBillNumber ?? '').toLowerCase().contains(q);
            return matchesFilter && matchesQuery && _matchesMonth(t);
          }).toList();

          // Newest bill first inside the selected month.
          filtered.sort((a, b) {
            final byBillDate = b.billDate.compareTo(a.billDate);
            if (byBillDate != 0) return byBillDate;
            return b.updatedAt.compareTo(a.updatedAt);
          });

          final outstanding = filtered
              .where((t) => t.isOpen)
              .fold<double>(0, (sum, t) => sum + t.balanceDue);

          return PageWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search customer, item or invoice',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickMonth,
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _monthLabel ?? 'All bill months',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _monthFilter == null
                                ? AppColors.ink
                                : AppColors.primary,
                            backgroundColor: _monthFilter == null
                                ? Colors.white
                                : AppColors.primary.withValues(alpha: 0.08),
                            side: BorderSide(
                              color: _monthFilter == null
                                  ? AppColors.border
                                  : AppColors.primary,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_monthFilter != null) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Show all bill months',
                          onPressed: () => setState(() => _monthFilter = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final filter in _TxFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                            showCheckmark: false,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _filter == filter
                                  ? Colors.white
                                  : AppColors.ink,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _filter == filter
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} ${filtered.length == 1 ? 'transaction' : 'transactions'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${money(outstanding)} outstanding',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyList(
                          hasAny: transactions.isNotEmpty,
                          onAdd: _openForm,
                          onDemo: _loadDemo,
                          title: _monthFilter == null
                              ? null
                              : 'No bills in ${_monthLabel!}',
                          message: _monthFilter == null
                              ? null
                              : 'Try another month or show all bill months.',
                          onClearFilter: () => setState(() {
                            _filter = _TxFilter.all;
                            _monthFilter = null;
                            _searchController.clear();
                            _query = '';
                          }),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 100),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final t = filtered[index];
                            return TransactionTile(
                              transaction: t,
                              onTap: () => _openDetail(t),
                              onEdit: () => _openForm(t),
                              onDelete: () => _confirmDelete(t),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickMonth() async {
    final initial = _monthFilter ?? DateTime.now();
    final choice = await showModalBottomSheet<_MonthChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MonthPickerSheet(initial: initial),
    );
    if (choice == null || !mounted) return;
    setState(() => _monthFilter = choice.month);
  }

  void _openForm([Transaction? transaction]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(transaction: transaction),
      ),
    );
  }

  void _openDetail(Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(
          transactionId: transaction.id,
          initial: transaction,
        ),
      ),
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
              : 'You already have transactions — demo data was not added.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          'This will remove ${transaction.customerName}\'s record from this device. This cannot be undone.',
        ),
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
    if (confirmed == true) {
      await ref.read(transactionsProvider.notifier).delete(transaction.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction deleted.')),
      );
    }
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    required this.hasAny,
    required this.onAdd,
    required this.onDemo,
    required this.onClearFilter,
    this.title,
    this.message,
  });

  final bool hasAny;
  final VoidCallback onAdd;
  final VoidCallback onDemo;
  final VoidCallback onClearFilter;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (!hasAny) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message:
            'Record a cash bill or invoice, then track its balance and payment status here.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add transaction'),
            ),
            TextButton(
              onPressed: onDemo,
              child: const Text('Load demo data'),
            ),
          ],
        ),
      );
    }

    return EmptyState(
      icon: Icons.search_off_rounded,
      title: title ?? 'No matches',
      message: message ??
          'Try another name, clear the search, or change the filter.',
      action: TextButton(
        onPressed: onClearFilter,
        child: const Text('Clear filters'),
      ),
    );
  }
}

class _MonthChoice {
  const _MonthChoice(this.month);

  /// Null means "all months".
  final DateTime? month;
}

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter by bill month',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const _MonthChoice(null)),
                    child: const Text('All months'),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous year',
                    onPressed: () => setState(() => _year--),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$_year',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next year',
                    onPressed: () => setState(() => _year++),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.5,
                children: List.generate(12, (index) {
                  final month = index + 1;
                  final selected = widget.initial.year == _year &&
                      widget.initial.month == month;
                  final label =
                      DateFormat('MMM').format(DateTime(_year, month));
                  return OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _MonthChoice(DateTime(_year, month)),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                          selected ? AppColors.primary : Colors.white,
                      foregroundColor: selected ? Colors.white : AppColors.ink,
                      side: BorderSide(
                        color: selected ? AppColors.primary : AppColors.border,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              const Text(
                'A bill is grouped by its cash-bill date, then invoice date, then the date it was recorded.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
