import 'package:flutter/material.dart';

import 'commission_screen.dart';
import 'home_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'transaction_form_screen.dart';
import 'transactions_screen.dart';
// 1. Import your new customer page
import 'customer_screen.dart'; 

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex});

  final int? initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    final fromUri = int.tryParse(Uri.base.queryParameters['tab'] ?? '');
    // 2. Update the max index to 4 because we added a new page
    _index = (widget.initialIndex ?? fromUri ?? 0).clamp(0, 4); 

    // Used by the design preview/screenshots: /?screen=form
    if (Uri.base.queryParameters['screen'] == 'form') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransactionFormScreen(),
          ),
        );
      });
    }

    // Used by the design preview/screenshots: /?screen=commission
    if (Uri.base.queryParameters['screen'] == 'commission') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CommissionScreen(),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            onOpenTransactions: () => setState(() => _index = 2), // Transactions is now index 2
            onOpenReminders: () => setState(() => _index = 3), // Reminders is now index 3
          ),
          const CustomerScreen(), // 3. Your page is at index 1
          const TransactionsScreen(), // Index 2
          const RemindersScreen(), // Index 3
          const SettingsScreen(), // Index 4
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          // 4. Add the Customer navigation button
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}