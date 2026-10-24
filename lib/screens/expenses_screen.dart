import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';
import 'add_expense_screen.dart';
import '../widgets/app_icon.dart';

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

  bool _matchesPayment(AppState s, CardPayment p) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return 'credit card bill payment'.contains(q) ||
        p.note.toLowerCase().contains(q) ||
        s.accounts.any((a) => a.id == p.cardId && a.name.toLowerCase().contains(q)) ||
        s.paymentMode(p.modeId).name.toLowerCase().contains(q) ||
        p.amount.toString().contains(q);
  }

  bool _matchesIncome(AppState s, Income i) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return 'income'.contains(q) ||
        i.note.toLowerCase().contains(q) ||
        s.category(i.categoryId).name.toLowerCase().contains(q) ||
        s.paymentLabel(i.paymentModeId).toLowerCase().contains(q) ||
        i.amount.toString().contains(q);
  }

  /// One entry per expense; a payment split across accounts is a single entry that
  /// carries all its legs.
  List<_Entry> _expenseEntries(AppState s, List<Expense> matched) {
    final seen = <int>{};
    final out = <_Entry>[];
    for (final e in matched) {
      final g = e.splitGroup;
      if (g == null) {
        out.add(_Entry(e.date, e.id!, expense: e, legs: [e]));
      } else if (seen.add(g)) {
        final legs = s.legsOf(e);
        out.add(_Entry(legs.first.date, legs.first.id!, expense: legs.first, legs: legs));
      }
    }
    return out;
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
    // A payment split across accounts is one entry, however many legs it has.
    final monthEntries = {for (final e in month) e.splitGroup ?? -e.id!}.length;
    final todayTotal = s.total(month.where((e) => e.date.day == now.day));

    final matched = s.expenses.where((e) => _matches(s, e)).toList();
    final searching = _query.isNotEmpty;

    // Expenses and credit card bill payments share one newest-first timeline.
    final shown = <_Entry>[
      ..._expenseEntries(s, matched),
      for (final p in s.cardPayments)
        if (_matchesPayment(s, p)) _Entry(p.date, p.id!, payment: p),
      for (final i in s.incomes)
        if (_matchesIncome(s, i)) _Entry(i.date, i.id!, income: i),
    ]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    final days = <DateTime, List<_Entry>>{};
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
                          '$monthEntries ${monthEntries == 1 ? 'entry' : 'entries'} this month',
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
                            '${shown.length} ${shown.length == 1 ? 'result' : 'results'} · ${s.money(s.total(matched))}',
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
                        Text(s.money(entry.value.fold<double>(0, (a, e) => a + e.expenseTotal)),
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
                    itemBuilder: (_, i) {
                      final e = entry.value[i];
                      if (e.expense != null) {
                        return _ExpenseTile(expense: e.expense!, legs: e.legs ?? [e.expense!]);
                      }
                      if (e.income != null) return _IncomeTile(income: e.income!);
                      return _PaymentTile(payment: e.payment!);
                    },
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

/// One row of the timeline: an expense or a credit card bill payment.
class _Entry {
  final DateTime date;
  final int id;
  final Expense? expense;
  final CardPayment? payment;
  final Income? income;

  /// For an expense: all its legs (one unless it was split across accounts).
  final List<Expense>? legs;
  const _Entry(this.date, this.id, {this.expense, this.payment, this.income, this.legs});

  double get expenseTotal => legs?.fold<double>(0, (a, l) => a + l.amount) ?? 0;
}

class _IncomeTile extends StatelessWidget {
  final Income income;
  const _IncomeTile({required this.income});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final cat = s.category(income.categoryId);
    final color = Color(cat.color);
    final green = Colors.green.shade400;

    return Dismissible(
      key: ValueKey('inc-${income.id}'),
      // Swiping sideways changes page now, so a swipe no longer deletes an entry.
      // Delete from the entry's own screen.
      direction: DismissDirection.none,
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
        s.deleteIncome(income.id!);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            persist: false,
            duration: const Duration(seconds: 4),
            content: const Text('Income deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => s.saveIncome(Income(
                amount: income.amount,
                note: income.note,
                categoryId: income.categoryId,
                paymentModeId: income.paymentModeId,
                date: income.date,
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
              MaterialPageRoute(builder: (_) => AddExpenseScreen(existingIncome: income))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                IconTile(cat.icon, size: 48, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(income.note.isEmpty ? 'Income' : income.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('+${s.money(income.amount)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17, color: green)),
                    const SizedBox(height: 4),
                    Text('to ${s.paymentLabel(income.paymentModeId)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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

class _PaymentTile extends StatelessWidget {
  final CardPayment payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final card = s.accounts.where((a) => a.id == payment.cardId).firstOrNull;
    const color = Color(0xFF22C55E);

    return Dismissible(
      key: ValueKey('pay-${payment.id}'),
      // Swiping sideways changes page now, so a swipe no longer deletes an entry.
      // Delete from the entry's own screen.
      direction: DismissDirection.none,
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
        s.deleteCardPayment(payment.id!);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            // A snackbar with an action otherwise stays until dismissed.
            persist: false,
            duration: const Duration(seconds: 4),
            content: const Text('Payment deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => s.saveCardPayment(CardPayment(
                cardId: payment.cardId,
                modeId: payment.modeId,
                amount: payment.amount,
                note: payment.note,
                date: payment.date,
              )),
            ),
          ));
      },
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: Theme.of(context).cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(existingPayment: payment))),
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
                  child: const Icon(Icons.credit_score_rounded, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Credit card bill',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                          [card?.name ?? 'Card', if (payment.note.isNotEmpty) payment.note]
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(s.money(payment.amount),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text('from ${s.paymentLabel(payment.modeId)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final List<Expense> legs;
  const _ExpenseTile({required this.expense, required this.legs});

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
      // Swiping sideways changes page now, so a swipe no longer deletes an entry.
      // Delete from the entry's own screen.
      direction: DismissDirection.none,
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
            // A snackbar with an action otherwise stays until dismissed.
            persist: false,
            duration: const Duration(seconds: 4),
            content: const Text('Expense deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => s.saveExpense(Expense(
                amount: expense.amount,
                note: expense.note,
                categoryId: expense.categoryId,
                paymentModeId: expense.paymentModeId,
                date: expense.date,
                attachment: expense.attachment,
                emiId: expense.emiId,
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
                IconTile(cat.icon, size: 48, color: color),
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
                    Text(s.money(legs.fold<double>(0, (a, l) => a + l.amount)),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 4),
                    if (legs.length > 1)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_split_rounded, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                  legs.map((l) => s.paymentMode(l.paymentModeId).name).join(' + '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(mode.icon, size: 14),
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
