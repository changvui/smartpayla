import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key});

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerProvider);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),
      body: PageWidth(
        child: customersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load customers: $error',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedColor),
              ),
            ),
          ),
          data: (all) {
            final customers = all
                .where((c) =>
                    _query.isEmpty ||
                    c.name.toLowerCase().contains(_query.toLowerCase()) ||
                    c.phone.toLowerCase().contains(_query.toLowerCase()))
                .toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search name or phone',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${customers.length} '
                        '${customers.length == 1 ? 'customer' : 'customers'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showCustomerDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: customers.isEmpty
                      ? EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: _query.isEmpty
                              ? 'No customers yet'
                              : 'No matching customers',
                          message: _query.isEmpty
                              ? 'Customers you add here can be reused when recording a cash bill.'
                              : 'Try a different name or phone number.',
                          action: _query.isEmpty
                              ? FilledButton.icon(
                                  onPressed: () =>
                                      _showCustomerDialog(context),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add your first customer'),
                                )
                              : null,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          itemCount: customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _CustomerCard(
                            customer: customers[index],
                            onEdit: () => _showCustomerDialog(
                              context,
                              existing: customers[index],
                            ),
                            onDelete: () => _deleteCustomer(customers[index]),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customerProvider.notifier).deleteCustomer(customer.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  Future<void> _showCustomerDialog(
    BuildContext context, {
    Customer? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final isEdit = existing != null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit customer' : 'Add customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Customer name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a customer name.'),
                      backgroundColor: AppColors.red,
                    ),
                  );
                  return;
                }
                final phone = phoneController.text.trim();
                Navigator.pop(dialogContext);

                final messenger = ScaffoldMessenger.of(context);
                final editing = existing;
                try {
                  final notifier = ref.read(customerProvider.notifier);
                  if (editing != null) {
                    await notifier.updateCustomer(
                      editing.id,
                      Customer(
                        id: editing.id,
                        name: name,
                        phone: phone.isEmpty ? 'No phone' : phone,
                        address: editing.address,
                      ),
                    );
                  } else {
                    await notifier.addCustomer(
                      Customer(
                        id: '',
                        name: name,
                        phone: phone.isEmpty ? 'No phone' : phone,
                        address: 'Not set',
                      ),
                    );
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        editing != null ? 'Customer updated.' : 'Customer saved.',
                      ),
                      backgroundColor: AppColors.green,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: AppColors.red,
                    ),
                  );
                }
              },
              child: Text(isEdit ? 'Update' : 'Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final initial = customer.name.trim().isEmpty
        ? '?'
        : customer.name.trim().substring(0, 1).toUpperCase();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 12, color: mutedColor),
                    const SizedBox(width: 4),
                    Text(
                      customer.phone,
                      style: TextStyle(fontSize: 11.5, color: mutedColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, size: 19, color: mutedColor),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
