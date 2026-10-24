import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';
import '../widgets/pay_confirm_sheet.dart';
import 'add_subscription_screen.dart';
import '../widgets/app_icon.dart';

/// The list of subscriptions, or of EMIs, shown inside a tab of the Recurring page.
class RecurringList extends StatelessWidget {
  final bool emi;
  const RecurringList({super.key, required this.emi});

  String get _noun => emi ? 'EMI' : 'subscription';

  void _add(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => AddSubscriptionScreen(emi: emi)));

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
    // Confirm (or change) what it is paid from before recording it.
    final modeId = await showPayConfirm(context, r);
    if (modeId == null || !context.mounted) return;
    final id = await s.markPaid(r, paymentModeId: modeId);
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
            // A snackbar with an action otherwise stays until dismissed.
            persist: false,
            duration: const Duration(seconds: 4),
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
    final items = s.recurring.where((r) => r.isEmi == emi).toList();
    // A card EMI stays "active" and finishes once its last instalment is billed.
    final active = items.where((r) => r.active && !s.recurringCompleted(r)).toList()
      ..sort((a, b) => s.emiNextDate(a).compareTo(s.emiNextDate(b)));
    final done = items.where((r) => s.recurringCompleted(r)).toList();
    final paused = items.where((r) => !r.active && !s.recurringCompleted(r)).toList();

    final monthly = active.fold(0.0, (sum, r) => sum + r.monthlyEquivalent);
    final dueSoon = active
        .where((r) => _daysUntil(s.emiNextDate(r)) < 8)
        .fold(0.0, (sum, r) => sum + r.amount);
    // What is still owed across all running EMIs, interest and fee included.
    final owed = active.fold(0.0, (sum, r) => sum + (r.isEmi ? s.emiInfo(r).balance : 0));

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emi ? Icons.account_balance_rounded : Icons.event_repeat_rounded,
                  size: 64, color: cs.outline),
              const SizedBox(height: 12),
              Text('No ${emi ? 'EMIs' : 'subscriptions'} yet',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                  emi
                      ? 'Add a loan or purchase EMI with its instalments. When one falls '
                          'due, confirm the payment and it is added to your expenses.'
                      : 'Add rent, Netflix, recharges or bills once. When one falls due, '
                          'mark it paid and it is added to your expenses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
                onPressed: () => _add(context),
                icon: const Icon(Icons.add_rounded),
                label: Text('Add $_noun'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
      children: [
        SpendCard(
          label: emi ? 'Monthly EMIs' : 'Monthly commitment',
          amount: s.money(double.parse(monthly.toStringAsFixed(2))),
          pillLabel: 'Due in the next 7 days',
          pillValue: s.money(dueSoon),
          footer: Text(
              '${active.length} active'
              '${paused.isEmpty ? '' : ' · ${paused.length} paused'}'
              '${done.isEmpty ? '' : ' · ${done.length} completed'}'
              '${emi && owed > 0 ? ' · ${s.money(owed)} left to pay' : ''}',
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
        if (done.isNotEmpty) _header('Completed'),
        for (final r in done) ...[
          _tile(context, s, r),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _tile(BuildContext context, AppState s, Recurring r) {
    final cs = Theme.of(context).colorScheme;
    final cat = s.category(r.categoryId);
    final dim = !r.active;
    // A card EMI is billed on the card's statement, so it has no Paid button.
    final cardEmi = s.isCardEmi(r);
    final info = r.isEmi ? s.emiInfo(r) : null;
    final due = !cardEmi && r.active && _daysUntil(r.nextDue) <= 0;
    final overdue = !cardEmi && r.active && _daysUntil(r.nextDue) < 0;
    final label = s.recurringCompleted(r)
        ? (r.foreclosed
            ? 'Foreclosed · ${DateFormat('d MMM y').format(r.closedDate)}'
            : 'Completed')
        : dim
            ? 'Paused'
            : cardEmi
                ? (info!.next == null
                    ? 'All instalments billed'
                    : 'Next on the ${DateFormat('d MMM').format(info.next!)} statement')
                : _dueLabel(r.nextDue);
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
              MaterialPageRoute(
                  builder: (_) => AddSubscriptionScreen(existing: r, emi: r.isEmi))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    IconTile(r.icon, size: 48),
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
                              [
                                cat.name,
                                s.paymentLabel(r.paymentModeId),
                                if (r.note.isNotEmpty) r.note,
                              ].join(' · '),
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
                          if (info != null) ...[
                            const SizedBox(height: 3),
                            Text(
                                [
                                  'EMI ${s.money(r.amount)}/mo',
                                  if (info.known)
                                    'Interest ${s.money(double.parse(info.interestTotal.toStringAsFixed(2)))}',
                                  if (info.gstTotal > 0.004)
                                    'GST ${s.money(double.parse(info.gstTotal.toStringAsFixed(2)))}',
                                  if (info.fee > 0) 'Fee ${s.money(info.fee)}',
                                ].join(' · '),
                                // Wraps onto a second line rather than cutting the fee off.
                                style: TextStyle(
                                    color: Colors.orange.shade400, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // An EMI shows what is still left to pay; a subscription its amount.
                        Text(
                            s.money(info != null
                                ? double.parse(info.balance.toStringAsFixed(2))
                                : r.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat_rounded,
                                size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                                r.isEmi && r.totalCount > 0
                                    ? '${info!.settled}/${r.totalCount} ${cardEmi ? 'billed' : 'paid'}'
                                    : r.frequency.label,
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
                      if (!r.isEmi) ...[
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
                      ],
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
