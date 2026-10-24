import 'package:flutter/material.dart';

import 'add_subscription_screen.dart';
import 'emi_calculator_screen.dart';
import 'subscriptions_screen.dart';

/// Bottom-bar tab with two lists: subscriptions and EMIs.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => RecurringScreenState();
}

class RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _emi => _tabs.index == 1;

  /// Starts a new item for the tab that is open: an EMI on the EMIs tab, otherwise
  /// a subscription.
  void addItem() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => AddSubscriptionScreen(emi: _emi)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          if (_emi)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                tooltip: 'EMI calculator',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const EmiCalculatorScreen())),
                icon: const Icon(Icons.calculate_rounded),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: _emi ? 'Add EMI' : 'Add subscription',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddSubscriptionScreen(emi: _emi))),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          tabs: const [Tab(text: 'Subscriptions'), Tab(text: 'EMIs')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // Swiping works here too; at either end the shell passes the swipe on to the
        // neighbouring page.
        children: const [RecurringList(emi: false), RecurringList(emi: true)],
      ),
    );
  }
}
