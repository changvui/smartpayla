import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../utils/whatsapp.dart';
import '../widgets/common.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customer});

  final Customer customer;

  // 快捷键：打开电话 (支持 Web 和 Android APK)
  Future<void> _makePhoneCall(BuildContext context) async {
    final ok = await openPhoneDialer(customer.phone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid phone number or dialer available.'),
        ),
      );
    }
  }

  // 快捷键：打开 WhatsApp (支持 Web 和 Android APK，自动补全 +60 等国际区号)
  Future<void> _openWhatsApp(
    BuildContext context,
    double totalOutstanding,
  ) async {
    final defaultMessage = totalOutstanding > 0
        ? 'Hi ${customer.name}, friendly reminder regarding your outstanding balance of ${money(totalOutstanding)} with SmartPayLA.'
        : 'Hi ${customer.name}, thank you for your business with SmartPayLA!';

    final ok = await openWhatsApp(
      defaultMessage,
      phone: customer.phone,
    );

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open WhatsApp. Please check the customer phone number.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // 获取所有的交易记录
    final transactionsAsync = ref.watch(transactionsProvider);
    final allTransactions = transactionsAsync.valueOrNull ?? [];

    // 筛选出属于这个客户的交易（忽略大小写）
    final customerTransactions = allTransactions
        .where((t) => t.customerName.toLowerCase() == customer.name.toLowerCase())
        .toList();

    // 计算这个客户的总欠款
    final totalOutstanding = customerTransactions
        .where((t) => t.isOpen)
        .fold<double>(0, (sum, t) => sum + t.balanceDue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile'),
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. 顶部客户资料卡片
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      customer.name.isNotEmpty
                          ? customer.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 32,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (customer.phone.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      customer.phone,
                      style: TextStyle(fontSize: 13, color: mutedColor),
                    ),
                  ],
                  if (customer.address.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      customer.address,
                      style: TextStyle(fontSize: 13, color: mutedColor),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // 快捷操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionButton(
                        icon: Icons.phone_rounded,
                        label: 'Call',
                        color: AppColors.blue,
                        onTap: () => _makePhoneCall(context),
                      ),
                      const SizedBox(width: 20),
                      _ActionButton(
                        icon: Icons.chat_rounded,
                        label: 'WhatsApp',
                        color: AppColors.green,
                        onTap: () => _openWhatsApp(context, totalOutstanding),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. 财务概览卡片
            const SectionHeader(title: 'Financial Overview'),
            AppCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Outstanding',
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        money(totalOutstanding),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: totalOutstanding > 0
                              ? AppColors.red
                              : AppColors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Across ${customerTransactions.where((t) => t.isOpen).length} open invoices',
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. 交易记录列表
            const SectionHeader(title: 'Transaction History'),
            if (customerTransactions.isEmpty)
              AppCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No transactions found for this customer.',
                      style: TextStyle(
                        color: mutedColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              )
            else
              ...customerTransactions.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransactionTile(
                    transaction: t,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TransactionDetailScreen(
                          transactionId: t.id,
                          initial: t,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 快捷操作小按钮组件
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}