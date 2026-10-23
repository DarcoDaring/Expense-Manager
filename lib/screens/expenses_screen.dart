import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';
import 'add_expense_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM y').format(d);
  }

  /// Matches the query against note, category, payment mode and amount.
  bool _matches(AppState s, Expense e) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return e.note.toLowerCase().contains(q) ||
        s.category(e.categoryId).name.toLowerCase().contains(q) ||
        s.paymentMode(e.paymentModeId).name.toLowerCase().contains(q) ||
        e.amount.toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final month = s.inMonth(now);
    final monthTotal = s.total(month);
    final todayTotal = s.total(month.where((e) => e.date.day == now.day));

    final shown = s.expenses.where((e) => _matches(s, e)).toList();
    final searching = _query.isNotEmpty;

    // Group (already newest-first) by calendar day.
    final days = <DateTime, List<Expense>>{};
    for (final e in shown) {
      days.putIfAbsent(DateTime(e.date.year, e.date.month, e.date.day), () => []).add(e);
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expense Manager',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    SpendCard(
                      label: 'Spending',
                      headerTrailing: DateFormat('MMMM y').format(now),
                      amount: s.money(monthTotal),
                      pillLabel: 'Today',
                      pillValue: s.money(todayTotal),
                      footer: Text(
                          '${month.length} ${month.length == 1 ? 'entry' : 'entries'} this month',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search notes, category, payment, amount',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                    if (searching && shown.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(
                            '${shown.length} ${shown.length == 1 ? 'result' : 'results'} · ${s.money(s.total(shown))}',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(searching ? Icons.search_off_rounded : Icons.savings_outlined,
                          size: 64, color: cs.outline),
                      const SizedBox(height: 12),
                      Text(searching ? 'No matching expenses' : 'No expenses yet',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          searching
                              ? 'Try a different word or amount'
                              : 'Tap “Add expense” to record your first one',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              for (final entry in days.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_dayLabel(entry.key),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Text(s.money(s.total(entry.value)),
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.separated(
                    itemCount: entry.value.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ExpenseTile(expense: entry.value[i]),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 130)),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final cat = s.category(expense.categoryId);
    final mode = s.paymentMode(expense.paymentModeId);
    final color = Color(cat.color);
    final hasNote = expense.note.isNotEmpty;

    return Dismissible(
      key: ValueKey('exp-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
      ),
      onDismissed: (_) {
        s.deleteExpense(expense.id!);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: const Text('Expense deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => s.saveExpense(Expense(
                amount: expense.amount,
                note: expense.note,
                categoryId: expense.categoryId,
                paymentModeId: expense.paymentModeId,
                date: expense.date,
              )),
            ),
          ));
      },
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: Theme.of(context).cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => AddExpenseScreen(existing: expense))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(iconAt(cat.icon), color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      if (hasNote) ...[
                        const SizedBox(height: 3),
                        Text(expense.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(s.money(expense.amount),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconAt(mode.icon), size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(mode.name,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
