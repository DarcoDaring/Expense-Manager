import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';
import 'add_subscription_screen.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  void _add(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const AddSubscriptionScreen()));

  static int _daysUntil(DateTime due) =>
      dayOnly(due).difference(dayOnly(DateTime.now())).inDays;

  String _dueLabel(DateTime due) {
    final days = _daysUntil(due);
    final date = DateFormat('d MMM').format(due);
    if (days < 0) return 'Overdue · was due $date';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow · $date';
    if (days < 8) return 'Due in $days days · $date';
    return 'Due $date';
  }

  Future<void> _paid(BuildContext context, AppState s, Recurring r) async {
    final id = await s.markPaid(r);
    if (!context.mounted) return;
    _undoBar(context, s, 'Marked as paid · expense added', r, expenseId: id);
  }

  Future<void> _notPaid(BuildContext context, AppState s, Recurring r) async {
    await s.markNotPaid(r);
    if (!context.mounted) return;
    _undoBar(context, s, 'Marked as not paid · nothing added', r);
  }

  void _undoBar(BuildContext context, AppState s, String text, Recurring before,
      {int? expenseId}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => s.undoMark(before, expenseId: expenseId),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final active = s.recurring.where((r) => r.active).toList()
      ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
    final paused = s.recurring.where((r) => !r.active).toList();

    final monthly = active.fold(0.0, (sum, r) => sum + r.monthlyEquivalent);
    final dueSoon = active
        .where((r) => _daysUntil(r.nextDue) < 8)
        .fold(0.0, (sum, r) => sum + r.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Add subscription',
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
      body: s.recurring.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_repeat_rounded, size: 64, color: cs.outline),
                    const SizedBox(height: 12),
                    const Text('No subscriptions yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        'Add rent, Netflix, EMIs or bills once. When one falls due, '
                        'mark it paid and it is added to your expenses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
                      onPressed: () => _add(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add subscription'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
              children: [
                SpendCard(
                  label: 'Monthly commitment',
                  amount: s.money(double.parse(monthly.toStringAsFixed(2))),
                  pillLabel: 'Due in the next 7 days',
                  pillValue: s.money(dueSoon),
                  footer: Text(
                      '${active.length} active${paused.isEmpty ? '' : ' · ${paused.length} paused'}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ),
                if (active.isNotEmpty) _header('Upcoming'),
                for (final r in active) ...[
                  _tile(context, s, r),
                  const SizedBox(height: 10),
                ],
                if (paused.isNotEmpty) _header('Paused'),
                for (final r in paused) ...[
                  _tile(context, s, r),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _tile(BuildContext context, AppState s, Recurring r) {
    final cs = Theme.of(context).colorScheme;
    final cat = s.category(r.categoryId);
    final color = Color(cat.color);
    final dim = !r.active;
    final due = r.active && _daysUntil(r.nextDue) <= 0;
    final overdue = r.active && _daysUntil(r.nextDue) < 0;
    final label = dim ? 'Paused' : _dueLabel(r.nextDue);
    final labelColor = dim
        ? cs.onSurfaceVariant
        : overdue
            ? cs.error
            : due
                ? Colors.orange.shade400
                : cs.primary;

    return Opacity(
      opacity: dim ? .55 : 1,
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: due
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: labelColor.withValues(alpha: .7), width: 1.2),
              )
            : Theme.of(context).cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => AddSubscriptionScreen(existing: r))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(iconAt(r.icon), color: color, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.recurringTitle(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 3),
                          Text(
                              r.note.isEmpty ? cat.name : '${cat.name} · ${r.note}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12.5)),
                          const SizedBox(height: 5),
                          Text(label,
                              style: TextStyle(
                                  color: labelColor,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(s.money(r.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat_rounded,
                                size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(r.frequency.label,
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                if (due) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _notPaid(context, s, r),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          label: const Text('Not paid'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _paid(context, s, r),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Paid'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
