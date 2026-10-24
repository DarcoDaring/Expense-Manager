import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/app_icon.dart';
import '../widgets/spend_card.dart';

/// The views on the Analysis tab. [spending] is the original report; the rest
/// live in this file.
enum AnalysisSection {
  spending('Spending', Icons.pie_chart_rounded),
  cards('Credit cards', Icons.credit_card_rounded),
  subscriptions('Subscriptions', Icons.event_repeat_rounded),
  emis('EMIs', Icons.account_balance_rounded);

  final String label;
  final IconData icon;
  const AnalysisSection(this.label, this.icon);
}

class AnalysisTabs extends StatelessWidget {
  final AnalysisSection value;
  final ValueChanged<AnalysisSection> onChanged;
  const AnalysisTabs({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final sec in AnalysisSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(sec.icon, size: 18),
                label: Text(sec.label),
                selected: sec == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(sec),
              ),
            ),
        ],
      ),
    );
  }
}

/// Big heading that starts each section on the single scrolling page.
class AnalysisSectionTitle extends StatelessWidget {
  final AnalysisSection section;
  const AnalysisSectionTitle(this.section, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(section.icon, color: cs.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Text(section.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// This month's subscription and EMI totals, side by side. Tapping a tile
/// jumps to that section.
class CommitmentsRow extends StatelessWidget {
  final ValueChanged<AnalysisSection> onOpen;
  const CommitmentsRow({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final subs = _monthTotals(s, emi: false);
    final emis = _monthTotals(s, emi: true);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _tile(context, s, AnalysisSection.subscriptions, 'Subscriptions', subs),
          ),
          const SizedBox(width: 12),
          Expanded(child: _tile(context, s, AnalysisSection.emis, 'EMIs', emis)),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, AppState s, AnalysisSection sec, String label,
      ({double total, double paid, double due}) t) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(sec),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sec.icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(s.money(double.parse(t.total.toStringAsFixed(2))),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Text('This month',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(
                  '${s.money(double.parse(t.paid.toStringAsFixed(2)))} paid · '
                  '${s.money(double.parse(t.due.toStringAsFixed(2)))} due',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.due > 0.004 ? Colors.orange.shade400 : Colors.green.shade400)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is committed this month: instalments / subscriptions already paid (found
/// through the expense each "Paid" tap created) plus those still due, overdue
/// ones included. A card EMI counts the instalment added to this month's statement.
({double total, double paid, double due}) _monthTotals(AppState s, {required bool emi}) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final monthEnd = DateTime(now.year, now.month + 1);
  final lastDay = monthEnd.subtract(const Duration(days: 1));
  var paid = 0.0;
  var due = 0.0;
  for (final r in s.recurring.where((r) => r.isEmi == emi)) {
    if (s.isCardEmi(r)) {
      final card = s.accountOfMode(r.paymentModeId);
      if (card != null) {
        final dates = s.emiStatementDates(r, card);
        for (var i = 0; i < dates.length; i++) {
          if (!dates[i].isBefore(monthStart) && dates[i].isBefore(monthEnd)) {
            due += r.billedAmount(r.paidCount + i + 1) + (i == 0 ? r.pendingFeeGross : 0);
          }
        }
        if (r.initialGross > 0.004) {
          final d = s.emiInitialDate(r, card);
          if (!d.isBefore(monthStart) && d.isBefore(monthEnd)) due += r.initialGross;
        }
      }
      continue;
    }
    if (r.active && !r.completed) {
      final n = _occurrences(r, lastDay).length;
      for (var i = 0; i < n; i++) {
        due += r.billedAmount(r.paidCount + i + 1) + (emi && i == 0 ? r.pendingFeeGross : 0);
      }
    }
    if (r.name.isEmpty) continue;
    paid += s.expenses
        .where((e) =>
            e.categoryId == r.categoryId &&
            e.date.year == now.year &&
            e.date.month == now.month &&
            (e.note == r.name || e.note.startsWith('${r.name} – ')))
        .fold(0.0, (a, e) => a + e.amount);
  }
  return (total: paid + due, paid: paid, due: due);
}

/// Content for every section except [AnalysisSection.spending].
class AnalysisBody extends StatelessWidget {
  final AnalysisSection section;
  const AnalysisBody({super.key, required this.section});

  @override
  Widget build(BuildContext context) => switch (section) {
        AnalysisSection.cards => const _CardsAnalysis(),
        AnalysisSection.subscriptions => const _SubscriptionsAnalysis(),
        AnalysisSection.emis => const _EmiAnalysis(),
        AnalysisSection.spending => const SizedBox.shrink(),
      };
}

// ---------------------------------------------------------------- helpers

final _dMMM = DateFormat('d MMM');

String _until(DateTime d) {
  final days = dayOnly(d).difference(dayOnly(DateTime.now())).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days > 1) return 'in $days days';
  if (days == -1) return 'yesterday';
  return '${-days} days ago';
}

/// Due dates of [r] up to and including [until], starting from the next one.
/// An EMI stops after its last instalment. Overdue dates come first.
List<DateTime> _occurrences(Recurring r, DateTime until) {
  var left = r.isEmi && r.totalCount > 0 ? r.totalCount - r.paidCount : 1 << 30;
  var d = r.nextDue;
  final out = <DateTime>[];
  while (left > 0 && !d.isAfter(until) && out.length < 600) {
    out.add(d);
    d = r.advance(d);
    left--;
  }
  return out;
}

Widget _header(String t, {String? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: [
          Expanded(
              child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          if (trailing != null)
            Text(trailing, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  const _Empty(this.icon, this.title, this.hint);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 52, color: cs.outline),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(hint,
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final int highlight;
  const _Bars({required this.labels, required this.values, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = values.fold(0.0, math.max);
    final compact = NumberFormat.compact();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: SizedBox(
          height: 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (values[i] > 0)
                        Text(compact.format(values[i]),
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: maxV == 0 ? 4 : (values[i] / maxV * 66).clamp(4, 66),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: i == highlight ? cs.primary : cs.primary.withValues(alpha: .3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[i],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == highlight ? FontWeight.w700 : FontWeight.w400)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded row card with an icon tile, two text lines and a trailing column.
class _RowCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String trailing;
  final String? trailingSub;
  final Color? subtitleColor;
  final Color? trailingColor;
  final Widget? bottom;
  const _RowCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.trailingSub,
    this.subtitleColor,
    this.trailingColor,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12.5, color: subtitleColor ?? cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(trailing,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17, color: trailingColor)),
                    if (trailingSub != null) ...[
                      const SizedBox(height: 3),
                      Text(trailingSub!,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ],
            ),
            if (bottom != null) ...[const SizedBox(height: 14), bottom!],
          ],
        ),
      ),
    );
  }
}

Widget _progress(BuildContext context, double value, Color color) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        color: color,
        backgroundColor: color.withValues(alpha: .15),
      ),
    );

// ------------------------------------------------------------ credit cards

class _CardsAnalysis extends StatelessWidget {
  const _CardsAnalysis();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final cards = s.creditCards;
    if (cards.isEmpty) {
      return const _Empty(Icons.credit_card_off_rounded, 'No credit cards yet',
          'Add a credit card under Accounts to see bills, usage and limits here.');
    }

    // A limit shared by several cards counts once.
    final limit = {for (final c in cards) s.limitHost(c).id!: s.limitHost(c).totalLimit}
        .values
        .fold(0.0, (a, v) => a + v);
    final owed = cards.fold(0.0, (a, c) => a + math.max(0.0, s.outstanding(c)));
    final util = limit <= 0 ? 0.0 : owed / limit;
    final bills = [...s.cardBills]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final totalDue = bills.fold(0.0, (a, b) => a + b.due);

    // Spending through any card, month by month.
    final modeIds = {
      for (final c in cards) for (final m in s.modesOf(c.id!)) m.id,
    };
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    double spent(Iterable<int?> ids, DateTime month) => s.expenses
        .where((e) =>
            ids.contains(e.paymentModeId) &&
            e.date.year == month.year &&
            e.date.month == month.month)
        .fold(0.0, (a, e) => a + e.amount);
    final monthly = [for (final m in months) spent(modeIds, m)];
    final paidThisMonth = s.cardPayments
        .where((p) =>
            p.cardId > 0 &&
            cards.any((c) => c.id == p.cardId) &&
            p.date.year == now.year &&
            p.date.month == now.month)
        .fold(0.0, (a, p) => a + p.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpendCard(
          label: 'Credit card outstanding',
          amount: s.money(owed),
          pillLabel: 'Available credit',
          pillValue: s.money(math.max(0.0, limit - owed)),
          footer: Text(
              '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} · '
              '${(util * 100).toStringAsFixed(0)}% of ${s.money(limit)} limit used',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
        _header('Upcoming bills', trailing: totalDue > 0.004 ? s.money(totalDue) : null),
        for (final b in bills) ...[
          _billRow(context, s, b),
          const SizedBox(height: 10),
        ],
        _header('Card usage'),
        for (final c in cards) ...[
          _usageRow(context, s, c),
          const SizedBox(height: 10),
        ],
        _header('Monthly card spending', trailing: s.money(monthly.last)),
        _Bars(
          labels: [for (final m in months) DateFormat('MMM').format(m)],
          values: monthly,
          highlight: months.length - 1,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final c in cards)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        AppIcon(s.modesOf(c.id!).firstOrNull?.icon ?? 0, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c.name)),
                        Text(
                            s.money(spent(
                                [for (final m in s.modesOf(c.id!)) m.id], now)),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text('Paid towards bills this month',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const Spacer(),
                    Text(s.money(paidThisMonth),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _billRow(BuildContext context, AppState s, CardBill b) {
    final cs = Theme.of(context).colorScheme;
    final owing = b.due > 0.004;
    final unbilled = b.unbilled > 0.004;
    final days = b.daysToDue();
    final overdue = owing && days < 0;
    final soon = owing && days >= 0 && days <= 5;
    final color = overdue ? cs.error : (soon ? Colors.orange.shade400 : null);

    // Nothing billed yet: say when the bill will be generated instead of "due".
    final String subtitle;
    final String trailing;
    final String? trailingSub;
    Color? trailingColor;
    if (owing) {
      subtitle = 'Due ${_dMMM.format(b.dueDate)} · ${_until(b.dueDate)}';
      trailing = s.money(b.due);
      trailingSub = 'Statement ${s.money(b.statement)}';
      trailingColor = color;
    } else if (unbilled) {
      subtitle = 'Bill generates ${_dMMM.format(b.nextStatement)} · ${_until(b.nextStatement)}';
      trailing = s.money(b.unbilled);
      trailingSub = 'not billed yet';
    } else {
      subtitle = 'Nothing due · next statement ${_dMMM.format(b.nextStatement)}';
      trailing = 'Paid';
      trailingSub = 'Statement ${s.money(b.statement)}';
      trailingColor = Colors.green.shade400;
    }
    return _RowCard(
      leading: AppIcon(s.modesOf(b.card.id!).firstOrNull?.icon ?? 0, size: 46),
      title: b.card.name,
      subtitle: subtitle,
      subtitleColor: owing ? color : null,
      trailing: trailing,
      trailingColor: trailingColor,
      trailingSub: trailingSub,
      bottom: Row(
        children: [
          _Stat('Unbilled so far', s.money(b.unbilled)),
          _Stat('Next statement', _dMMM.format(b.nextStatement)),
        ],
      ),
    );
  }

  Widget _usageRow(BuildContext context, AppState s, Account c) {
    final cs = Theme.of(context).colorScheme;
    final owed = math.max(0.0, s.outstanding(c));
    final limit = s.groupLimit(c);
    final util = limit <= 0 ? 0.0 : s.groupOwed(c) / limit;
    final color = util > .8
        ? cs.error
        : util > .5
            ? Colors.orange.shade400
            : Colors.green.shade400;
    return _RowCard(
      leading: AppIcon(s.modesOf(c.id!).firstOrNull?.icon ?? 0, size: 46),
      title: c.name,
      subtitle: s.isShared(c)
          ? 'Shared limit ${s.money(limit)} · with ${s.limitPartners(c).map((x) => x.name).join(', ')}'
          : 'Limit ${s.money(limit)}',
      trailing: '${(util * 100).toStringAsFixed(0)}%',
      trailingColor: color,
      trailingSub: 'used',
      bottom: Column(
        children: [
          _progress(context, util, color),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat('Outstanding', s.money(owed)),
              _Stat('Available', s.money(math.max(0.0, s.availableLimit(c)))),
              if (s.cardBill(c).emiBlocked > 0.004)
                _Stat('EMI held', s.money(s.cardBill(c).emiBlocked)),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- subscriptions

class _SubscriptionsAnalysis extends StatelessWidget {
  const _SubscriptionsAnalysis();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final all = s.recurring.where((r) => !r.isEmi).toList();
    final active = all.where((r) => r.active).toList();
    if (all.isEmpty) {
      return const _Empty(Icons.event_repeat_rounded, 'No subscriptions yet',
          'Add Netflix, rent or other bills in the Subscriptions tab to see them here.');
    }

    final monthly = active.fold(0.0, (a, r) => a + r.monthlyEquivalent);
    final paused = all.length - active.length;

    // What falls due in the next 30 days.
    final horizon = dayOnly(DateTime.now()).add(const Duration(days: 30));
    final coming = <(Recurring, DateTime)>[
      for (final r in active)
        for (final d in _occurrences(r, horizon)) (r, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final comingTotal = coming.fold(0.0, (a, e) => a + e.$1.amount);

    // Monthly cost by category and by item.
    final byCat = <int, double>{};
    for (final r in active) {
      byCat[r.categoryId] = (byCat[r.categoryId] ?? 0) + r.monthlyEquivalent;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final ranked = [...active]..sort((a, b) => b.monthlyEquivalent.compareTo(a.monthlyEquivalent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpendCard(
          label: 'Monthly subscriptions',
          amount: s.money(double.parse(monthly.toStringAsFixed(2))),
          pillLabel: 'Yearly cost',
          pillValue: s.money(double.parse((monthly * 12).toStringAsFixed(2))),
          footer: Text(
              '${active.length} active${paused == 0 ? '' : ' · $paused paused'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
        _header('Next 30 days', trailing: coming.isEmpty ? null : s.money(comingTotal)),
        if (coming.isEmpty)
          const _Empty(Icons.event_available_rounded, 'Nothing due', 'No subscription falls due in the next 30 days.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final e in coming)
                  ListTile(
                    leading: IconTile(e.$1.icon, size: 44),
                    title: Text(s.recurringTitle(e.$1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${_dMMM.format(e.$2)} · ${_until(e.$2)}',
                        style: TextStyle(
                            color: dayOnly(e.$2).isBefore(dayOnly(DateTime.now()))
                                ? cs.error
                                : null)),
                    trailing: Text(s.money(e.$1.amount),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        _header('Where it goes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final en in cats)
                  _shareRow(
                    context,
                    label: s.category(en.key).name,
                    icon: s.category(en.key).icon,
                    color: Color(s.category(en.key).color),
                    value: en.value,
                    total: monthly,
                    money: s.money,
                  ),
              ],
            ),
          ),
        ),
        _header('Biggest subscriptions', trailing: 'per month'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final r in ranked.take(6))
                  _shareRow(
                    context,
                    label: s.recurringTitle(r),
                    icon: r.icon,
                    color: cs.primary,
                    value: r.monthlyEquivalent,
                    total: monthly,
                    money: s.money,
                    sub: r.frequency == Frequency.monthly
                        ? null
                        : '${s.money(r.amount)} ${r.frequency.label.toLowerCase()}',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _shareRow(
  BuildContext context, {
  required String label,
  required int icon,
  required Color color,
  required double value,
  required double total,
  required String Function(double) money,
  String? sub,
}) {
  final cs = Theme.of(context).colorScheme;
  final share = total <= 0 ? 0.0 : value / total;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      children: [
        Row(
          children: [
            IconTile(icon, size: 36, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (sub != null)
                    Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(double.parse(value.toStringAsFixed(2))),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${(share * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _progress(context, share, color),
      ],
    ),
  );
}

// -------------------------------------------------------------------- EMIs

/// The instalments still to come for [r] up to [until], as (date, share that
/// repays the amount financed, share that is interest or fee).
List<(DateTime, double, double)> _future(AppState s, Recurring r, DateTime until) {
  final out = <(DateTime, double, double)>[];
  // Instalment i of those still to come is number paidCount + i + 1 overall.
  double baseOf(int i) =>
      r.hasPrincipal ? math.min(r.amount, r.principalOf(r.paidCount + i + 1)) : r.amount;
  final card = s.isCardEmi(r) ? s.accountOfMode(r.paymentModeId) : null;
  if (card != null) {
    final today = dayOnly(DateTime.now());
    if (r.initialGross > 0.004) {
      final d = s.emiInitialDate(r, card);
      if (d.isAfter(today) && !d.isAfter(until)) out.add((d, 0, r.initialGross));
    }
    final dates = s.emiStatementDates(r, card);
    for (var i = 0; i < dates.length; i++) {
      final d = dates[i];
      if (d.isAfter(today) && !d.isAfter(until)) {
        out.add((d, baseOf(i),
            r.amount - baseOf(i) + r.gstOn(r.paidCount + i + 1) + (i == 0 ? r.pendingFeeGross : 0)));
      }
    }
  } else {
    final dates = _occurrences(r, until);
    for (var i = 0; i < dates.length; i++) {
      out.add((dates[i], baseOf(i),
          r.amount - baseOf(i) + r.gstOn(r.paidCount + i + 1) + (i == 0 ? r.pendingFeeGross : 0)));
    }
  }
  return out;
}

class _EmiAnalysis extends StatelessWidget {
  const _EmiAnalysis();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final emis = s.recurring.where((r) => r.isEmi).toList();
    if (emis.isEmpty) {
      return const _Empty(Icons.account_balance_rounded, 'No EMIs yet',
          'Add an EMI in the Subscriptions tab to track instalments, interest and balance here.');
    }
    final infos = {for (final r in emis) r.id!: s.emiInfo(r)};
    bool finished(Recurring r) => s.recurringCompleted(r);
    final active = emis.where((r) => r.active && !finished(r)).toList()
      ..sort((a, b) => s.emiNextDate(a).compareTo(s.emiNextDate(b)));
    final done = emis.where(finished).toList();
    final stopped = emis.where((r) => !r.active && !finished(r)).toList();

    final monthly = active.fold(0.0, (a, r) => a + r.monthlyEquivalent);
    final balance = active.fold(0.0, (a, r) => a + infos[r.id]!.balance);
    final ends = [for (final r in active) infos[r.id]!.end].whereType<DateTime>().toList()..sort();

    // Outflow for this month and the next five, split into what repays the
    // amount financed and what is interest / fee.
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final months = [for (var i = 0; i < 6; i++) DateTime(start.year, start.month + i)];
    final until = DateTime(start.year, start.month + 6).subtract(const Duration(days: 1));
    final baseOut = List<double>.filled(6, 0);
    final extraOut = List<double>.filled(6, 0);
    for (final r in active) {
      for (final (d, base, extra) in _future(s, r, until)) {
        // Anything overdue counts towards the current month.
        final idx = d.isBefore(start) ? 0 : (d.year - start.year) * 12 + d.month - start.month;
        if (idx >= 0 && idx < 6) {
          baseOut[idx] += base;
          extraOut[idx] += extra;
        }
      }
    }
    final projected = [for (var i = 0; i < 6; i++) baseOut[i] + extraOut[i]];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpendCard(
          label: 'Monthly EMIs',
          amount: s.money(double.parse(monthly.toStringAsFixed(2))),
          pillLabel: 'Balance to pay',
          pillValue: s.money(double.parse(balance.toStringAsFixed(2))),
          footer: Text(
              '${active.length} active${done.isEmpty ? '' : ' · ${done.length} completed'}'
              '${ends.isEmpty ? '' : ' · debt-free by ${DateFormat('MMM y').format(ends.last)}'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
        _header('What your EMIs really cost'),
        _costCard(context, s, emis, infos),
        if (active.isNotEmpty) ...[
          _header('Next 6 months', trailing: s.money(projected.fold(0.0, (a, b) => a + b))),
          _StackedBars(
            labels: [for (final m in months) DateFormat('MMM').format(m)],
            base: baseOut,
            extra: extraOut,
          ),
        ],
        _header('Your EMIs'),
        if (active.isEmpty)
          const _Empty(Icons.celebration_rounded, 'No active EMIs', 'Every EMI is paid off or paused.'),
        for (final r in active) ...[
          _emiCard(context, s, r, infos[r.id]!),
          const SizedBox(height: 10),
        ],
        if (stopped.isNotEmpty) ...[
          _header('Paused'),
          for (final r in stopped) ...[
            Opacity(opacity: .6, child: _emiCard(context, s, r, infos[r.id]!)),
            const SizedBox(height: 10),
          ],
        ],
        if (done.isNotEmpty) ...[
          _header('Completed'),
          for (final r in done) ...[
            _emiCard(context, s, r, infos[r.id]!),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  /// Principal vs interest vs fees across every EMI whose amount financed is known.
  Widget _costCard(
      BuildContext context, AppState s, List<Recurring> emis, Map<int, EmiInfo> infos) {
    final cs = Theme.of(context).colorScheme;
    final known = [for (final r in emis) if (infos[r.id]!.known) infos[r.id]!];
    final unknown = emis.length - known.length;
    if (known.isEmpty) {
      return const _Empty(Icons.percent_rounded, 'Interest not available yet',
          'Edit an EMI and enter the amount financed to see how much interest and fees you pay.');
    }
    double sum(double Function(EmiInfo) f) => known.fold(0.0, (a, i) => a + f(i));
    final financed = sum((i) => i.principal);
    final interest = sum((i) => i.interestTotal);
    final fees = sum((i) => i.fee + i.closeCharge);
    final gst = sum((i) => i.gstTotal);
    final payable = sum((i) => i.payable);
    final extra = interest + gst + fees;
    final extraPaid = sum((i) => i.extraPaid);
    final paid = sum((i) => i.paid);
    final principalPaid = paid - extraPaid;
    final orange = Colors.orange.shade400;
    final pink = Colors.pink.shade300;
    final amber = Colors.amber.shade600;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
    int flex(double v) => v <= 0 ? 0 : (v * 1000).round().clamp(1, 1 << 30);

    Widget legend(Color c, String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: bold ? null : cs.onSurfaceVariant,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
              const Spacer(),
              Text(value,
                  style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EXTRA YOU PAY',
                style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: orange)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(m(extra),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('${(extra / financed * 100).toStringAsFixed(1)}% over what you financed',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (flex(financed) > 0)
                      Expanded(flex: flex(financed), child: Container(color: cs.primary)),
                    if (flex(interest) > 0)
                      Expanded(flex: flex(interest), child: Container(color: orange)),
                    if (flex(gst) > 0)
                      Expanded(flex: flex(gst), child: Container(color: amber)),
                    if (flex(fees) > 0)
                      Expanded(flex: flex(fees), child: Container(color: pink)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            legend(cs.primary, 'Amount financed', m(financed)),
            legend(orange, 'Interest', m(interest)),
            if (gst > 0.004) legend(amber, 'GST', m(gst)),
            legend(pink, 'Fees & foreclosure', m(fees)),
            const Divider(height: 22),
            legend(Colors.transparent, 'Total payable', m(payable), bold: true),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Stat('Paid so far', m(paid)),
                      _Stat('Of which principal', m(principalPaid)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Stat('Interest & fees paid', m(extraPaid)),
                      _Stat('Interest & fees to come', m(extra - extraPaid)),
                    ],
                  ),
                ],
              ),
            ),
            if (unknown > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    '$unknown ${unknown == 1 ? 'EMI has' : 'EMIs have'} no amount financed, so '
                    '${unknown == 1 ? 'it is' : 'they are'} left out. Edit ${unknown == 1 ? 'it' : 'them'} to include the interest.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emiCard(BuildContext context, AppState s, Recurring r, EmiInfo i) {
    final cs = Theme.of(context).colorScheme;
    final orange = Colors.orange.shade400;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
    final overdue = !i.card && r.active && dayOnly(r.nextDue).isBefore(dayOnly(DateTime.now()));
    final String subtitle;
    if (i.closed) {
      subtitle = 'Foreclosed on ${DateFormat('d MMM y').format(r.closedDate)}';
    } else if (i.left <= 0) {
      subtitle = 'Completed';
    } else if (!r.active && !i.card) {
      subtitle = 'Paused';
    } else if (i.next == null) {
      subtitle = 'All instalments billed';
    } else {
      subtitle = i.card
          ? 'Added to the ${_dMMM.format(i.next!)} statement · ${_until(i.next!)}'
          : 'Next ${_dMMM.format(i.next!)} · ${_until(i.next!)}';
    }
    return _RowCard(
      leading: IconTile(r.icon, size: 46),
      title: s.recurringTitle(r),
      subtitle: subtitle,
      subtitleColor: overdue ? cs.error : null,
      trailing: m(r.amount),
      trailingSub: i.card ? 'on card' : 'monthly',
      bottom: Column(
        children: [
          _progress(context, i.total == 0 ? 0 : i.settled / i.total, cs.primary),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(i.card ? 'Billed' : 'Paid', '${i.settled} of ${i.total}'),
              _Stat('Left', '${i.left}'),
              _Stat('Balance', m(i.balance)),
              _Stat('Ends', i.end == null ? '—' : DateFormat('MMM y').format(i.end!)),
            ],
          ),
          if (i.known) ...[
            const Divider(height: 24),
            Row(
              children: [
                _Stat('Financed', m(i.principal)),
                _Stat('Interest', m(i.interestTotal)),
                _Stat('GST & fee', i.fee + i.gstTotal > 0.004 ? m(i.fee + i.gstTotal) : '—'),
                _Stat('Total', m(i.payable)),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Extra paid so far ${m(i.extraPaid)} · still to pay ${m(i.extraLeft)}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: orange)),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add the amount financed to see the interest',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bars split into the part that repays the amount financed and the part that
/// is interest or fee.
class _StackedBars extends StatelessWidget {
  final List<String> labels;
  final List<double> base;
  final List<double> extra;
  const _StackedBars({required this.labels, required this.base, required this.extra});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final orange = Colors.orange.shade400;
    final totals = [for (var i = 0; i < labels.length; i++) base[i] + extra[i]];
    final maxV = totals.fold(0.0, math.max);
    final compact = NumberFormat.compact();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          children: [
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (totals[i] > 0)
                            Text(compact.format(totals[i]),
                                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            height: maxV == 0 ? 4 : (totals[i] / maxV * 70).clamp(4, 70),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              children: [
                                if (extra[i] > 0.004)
                                  Expanded(
                                    flex: (extra[i] * 100).round().clamp(1, 1 << 30),
                                    child: Container(color: orange),
                                  ),
                                Expanded(
                                  flex: (base[i] * 100).round().clamp(1, 1 << 30),
                                  child: Container(
                                      color: totals[i] == 0
                                          ? cs.primary.withValues(alpha: .3)
                                          : cs.primary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(labels[i], style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 10, height: 10, color: cs.primary),
                const SizedBox(width: 6),
                Text('Principal', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 18),
                Container(width: 10, height: 10, color: orange),
                const SizedBox(width: 6),
                Text('Interest & fees',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
