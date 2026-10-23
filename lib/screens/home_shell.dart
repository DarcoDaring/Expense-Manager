import 'package:flutter/material.dart';

import 'add_expense_screen.dart';
import 'expenses_screen.dart';
import 'subscriptions_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Let pages scroll behind the translucent area around the + button.
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          ExpensesScreen(),
          ReportScreen(),
          SubscriptionsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        onAdd: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AddExpenseScreen())),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  const _NavBar({required this.index, required this.onSelect, required this.onAdd});

  static const _bump = 30.0; // how far the + button rises above the bar
  static const _button = 66.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _bump),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Row(
                  children: [
                    _item(context, 0, Icons.home_rounded, 'Home'),
                    _item(context, 1, Icons.bar_chart_rounded, 'Analysis'),
                    const SizedBox(width: _button + 16),
                    _item(context, 2, Icons.event_repeat_rounded, 'Subscriptions'),
                    _item(context, 3, Icons.more_horiz_rounded, 'More'),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: Semantics(
            button: true,
            label: 'Add expense',
            child: GestureDetector(
              onTap: onAdd,
              child: Container(
                width: _button,
                height: _button,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.onSurface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .25),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.add_rounded, size: 36, color: cs.surface),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = index == i;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: .6);
    return Expanded(
      child: InkResponse(
        onTap: () => onSelect(i),
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
