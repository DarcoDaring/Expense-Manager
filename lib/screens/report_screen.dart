import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';
import '../widgets/app_icon.dart';
import 'analysis_extras.dart';

enum _Range { week, month, year, custom }

enum _By { category, payment, income }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => ReportScreenState();
}

class ReportScreenState extends State<ReportScreen> {
  _Range _range = _Range.month;
  DateTime _anchor = _day(DateTime.now());
  DateTimeRange? _custom;
  _By _by = _By.category;
  int? _open;
  AnalysisSection _section = AnalysisSection.spending;
  final _scroll = ScrollController();
  final _keys = {for (final sec in AnalysisSection.values) sec: GlobalKey()};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Back to the top, on Spending and the current month. The page is kept alive
  /// between visits, so this is cheaper than building it all again.
  void resetView() {
    if (!mounted) return;
    setState(() {
      _range = _Range.month;
      _anchor = _day(DateTime.now());
      _custom = null;
      _by = _By.category;
      _open = null;
      _section = AnalysisSection.spending;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Chips glide to a section of the page. The time taken grows with the distance,
  /// so a long trip is not a sudden whip, and the curve eases in and out.
  void _jump(AnalysisSection sec) {
    setState(() => _section = sec);
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;

    double target = 0;
    if (sec != AnalysisSection.spending) {
      final ro = _keys[sec]!.currentContext?.findRenderObject();
      if (ro == null) return;
      target = RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0.0).offset;
    }
    target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);

    final distance = (target - pos.pixels).abs();
    if (distance < 1) return;
    final ms = (380 + distance * 0.32).clamp(500.0, 1200.0).round();
    _scroll.animateTo(target,
        duration: Duration(milliseconds: ms), curve: Curves.easeInOutCubic);
  }

  // ---- period maths: [start, end) in whole days ----
  DateTime get _start {
    switch (_range) {
      case _Range.week:
        return _anchor.subtract(Duration(days: _anchor.weekday - 1));
      case _Range.month:
        return DateTime(_anchor.year, _anchor.month);
      case _Range.year:
        return DateTime(_anchor.year);
      case _Range.custom:
        return _custom?.start ?? _anchor;
    }
  }

  DateTime get _end {
    final s = _start;
    switch (_range) {
      case _Range.week:
        return DateTime(s.year, s.month, s.day + 7);
      case _Range.month:
        return DateTime(s.year, s.month + 1);
      case _Range.year:
        return DateTime(s.year + 1);
      case _Range.custom:
        final e = _custom?.end ?? _anchor;
        return DateTime(e.year, e.month, e.day + 1);
    }
  }

  /// Same-length period immediately before the current one.
  (DateTime, DateTime) get _prev {
    final s = _start;
    switch (_range) {
      case _Range.week:
        return (DateTime(s.year, s.month, s.day - 7), s);
      case _Range.month:
        return (DateTime(s.year, s.month - 1), s);
      case _Range.year:
        return (DateTime(s.year - 1), s);
      case _Range.custom:
        final len = _end.difference(s);
        return (s.subtract(len), s);
    }
  }

  bool get _isCurrent {
    final today = _day(DateTime.now());
    return !today.isBefore(_start) && today.isBefore(_end);
  }

  String get _label {
    final fmt = DateFormat('d MMM');
    switch (_range) {
      case _Range.week:
        final last = _end.subtract(const Duration(days: 1));
        return '${fmt.format(_start)} – ${fmt.format(last)}';
      case _Range.month:
        return DateFormat('MMMM y').format(_start);
      case _Range.year:
        return '${_start.year}';
      case _Range.custom:
        final last = _end.subtract(const Duration(days: 1));
        return '${DateFormat('d MMM y').format(_start)} – ${DateFormat('d MMM y').format(last)}';
    }
  }

  List<Income> _incomeBetween(AppState s, DateTime a, DateTime b) => s.incomes.where((i) {
        final d = _day(i.date);
        return !d.isBefore(a) && d.isBefore(b);
      }).toList();

  List<Expense> _between(AppState s, DateTime a, DateTime b) => s.expenses.where((e) {
        final d = _day(e.date);
        return !d.isBefore(a) && d.isBefore(b);
      }).toList();

  void _shift(int dir) => setState(() {
        switch (_range) {
          case _Range.week:
            _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * dir);
          case _Range.month:
            _anchor = DateTime(_anchor.year, _anchor.month + dir);
          case _Range.year:
            _anchor = DateTime(_anchor.year + dir);
          case _Range.custom:
            break;
        }
        _open = null;
      });

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (r != null) {
      setState(() {
        _custom = r;
        _range = _Range.custom;
        _open = null;
      });
    }
  }

  void _setRange(_Range r) {
    if (r == _Range.custom) {
      _pickCustom();
      return;
    }
    setState(() {
      _range = r;
      _anchor = _day(DateTime.now());
      _open = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    final list = _between(s, _start, _end);
    final total = s.total(list);
    final (pa, pb) = _prev;
    final prevTotal = s.total(_between(s, pa, pb));
    final inc = _incomeBetween(s, _start, _end);
    final incTotal = s.totalIncome(inc);
    final shownTotal = _by == _By.income ? incTotal : total;
    final slices = switch (_by) {
      _By.category => s.byCategory(list),
      _By.payment => s.byPayment(list),
      _By.income => s.incomeByCategory(inc),
    };
    final days = math.max(1, _end.difference(_start).inDays);
    final elapsed = _isCurrent
        ? math.max(1, _day(DateTime.now()).difference(_start).inDays + 1)
        : days;

    return Scaffold(
      body: SafeArea(
        // A plain scroll view (not a lazy ListView) so every section exists and the
        // chips at the top can scroll to it.
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Analysis', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            AnalysisTabs(value: _section, onChanged: _jump),
            const SizedBox(height: 14),
            _RangeTabs(value: _range, onChanged: _setRange),
            const SizedBox(height: 14),
            _periodCard(cs, list.length + inc.length),
            const SizedBox(height: 14),
            _summaryCard(s, cs, total, prevTotal, total / elapsed),
            const SizedBox(height: 14),
            _cashflowCard(s, cs, incTotal, total),
            const SizedBox(height: 14),
            CommitmentsRow(onOpen: _jump),
            const SizedBox(height: 14),
            _Trend(
              range: _range,
              start: _start,
              totalOf: (a, b) => s.total(_between(s, a, b)),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text('Breakdown',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SegmentedButton<_By>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _By.category, label: Text('Category')),
                  ButtonSegment(value: _By.payment, label: Text('Payment')),
                  ButtonSegment(value: _By.income, label: Text('Income')),
                ],
                selected: {_by},
                onSelectionChanged: (v) => setState(() {
                  _by = v.first;
                  _open = null;
                }),
              ),
            ),
            const SizedBox(height: 14),
            if (slices.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.donut_large_rounded, size: 56, color: cs.outline),
                        const SizedBox(height: 8),
                        Text(_by == _By.income
                                ? 'No income in this period'
                                : 'No spending in this period',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: _Donut(slices: slices, total: shownTotal, money: s.money),
                    ),
                    for (final sl in slices) _row(context, s, sl, shownTotal, list, inc),
                  ],
                ),
              ),
            // The other sections follow on the same page.
            for (final sec in AnalysisSection.values.skip(1)) ...[
              const SizedBox(height: 36),
              KeyedSubtree(key: _keys[sec], child: AnalysisSectionTitle(sec)),
              const SizedBox(height: 14),
              // Each section repaints on its own, which keeps long scrolls light.
              RepaintBoundary(child: AnalysisBody(section: sec)),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _periodCard(ColorScheme cs, int count) {
    final custom = _range == _Range.custom;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            custom
                ? const SizedBox(width: 48)
                : IconButton(
                    onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: custom ? _pickCustom : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Text(_label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('$count ${count == 1 ? 'TRANSACTION' : 'TRANSACTIONS'}',
                          style: TextStyle(
                              fontSize: 12, letterSpacing: .6, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            custom
                ? const SizedBox(width: 48)
                : IconButton(
                    onPressed: _isCurrent ? null : () => _shift(1),
                    icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(AppState s, ColorScheme cs, double total, double prev, double avg) {
    final up = total > prev;
    Widget delta;
    if (prev == 0) {
      delta = Text('No data for previous period',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13));
    } else if (total == prev) {
      delta = Text('Same as previous period',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13));
    } else {
      final pct = ((total - prev).abs() / prev * 100).toStringAsFixed(0);
      final color = up ? cs.error : Colors.green.shade500;
      delta = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 18, color: color),
          const SizedBox(width: 6),
          Text('$pct% ${up ? 'more' : 'less'} than previous',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
    }
    return SpendCard(
      label: 'Spending',
      amount: s.money(total),
      pillLabel: 'Daily average',
      pillValue: s.money(double.parse(avg.toStringAsFixed(2))),
      footer: delta,
    );
  }

  /// Income, what was spent, and what is left, for the period.
  Widget _cashflowCard(AppState s, ColorScheme cs, double income, double spent) {
    final net = income - spent;
    final green = Colors.green.shade400;
    Widget stat(String label, String value, Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: color)),
              ),
            ],
          ),
        );
    final String note;
    if (income <= 0) {
      note = 'No income recorded in this period';
    } else if (net >= 0) {
      note = 'You kept ${(net / income * 100).toStringAsFixed(0)}% of your income';
    } else {
      note = 'You spent ${(-net / income * 100).toStringAsFixed(0)}% more than you earned';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                stat('INCOME', s.money(income), green),
                stat('SPENT', s.money(spent), cs.error),
                stat('NET', '${net < 0 ? '-' : ''}${s.money(net.abs())}',
                    net < 0 ? cs.error : green),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: income <= 0 ? (spent > 0 ? 1.0 : 0.0) : (spent / income).clamp(0.0, 1.0),
                minHeight: 8,
                color: spent > income ? cs.error : green,
                backgroundColor: green.withValues(alpha: .18),
              ),
            ),
            const SizedBox(height: 10),
            Text(note, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AppState s, Slice sl, double total, List<Expense> list,
      List<Income> incomes) {
    final cs = Theme.of(context).colorScheme;
    final open = _open == sl.id;
    final pct = total == 0 ? 0.0 : sl.total / total;

    // Drill-down: the opposite dimension, restricted to this row.
    List<Slice> inner = const [];
    if (open) {
      if (_by == _By.income) {
        // Income by category, split by the account that received it.
        inner = s.incomeByPayment(incomes.where((i) => i.categoryId == sl.id));
      } else {
        final subset = list.where(
            (e) => _by == _By.category ? e.categoryId == sl.id : e.paymentModeId == sl.id);
        inner = _by == _By.category ? s.byPayment(subset) : s.byCategory(subset);
      }
    }

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = open ? null : sl.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: sl.color.withValues(alpha: .15),
                  child: AppIcon(sl.icon, color: sl.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sl.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${(pct * 100).toStringAsFixed(1)}% · ${sl.count} ${sl.count == 1 ? 'entry' : 'entries'}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(s.money(sl.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: open
              ? Container(
                  width: double.infinity,
                  color: cs.surfaceContainerHighest.withValues(alpha: .4),
                  padding: const EdgeInsets.fromLTRB(72, 8, 20, 8),
                  child: Column(
                    children: [
                      for (final i in inner)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              AppIcon(i.icon, size: 18, color: i.color),
                              const SizedBox(width: 8),
                              Expanded(child: Text(i.label)),
                              Text(s.money(i.total),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _RangeTabs extends StatelessWidget {
  final _Range value;
  final ValueChanged<_Range> onChanged;
  const _RangeTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const labels = {
      _Range.week: 'Week',
      _Range.month: 'Month',
      _Range.year: 'Year',
      _Range.custom: 'Custom',
    };
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          for (final r in _Range.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == value ? cs.surfaceContainerHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(labels[r]!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: r == value ? cs.onSurface : cs.onSurfaceVariant,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Donut with the period total in the middle.
class _Donut extends StatelessWidget {
  final List<Slice> slices;
  final double total;
  final String Function(double) money;
  const _Donut({required this.slices, required this.total, required this.money});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 220,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(slices.map((e) => '${e.id}:${e.total}').join(',')),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              painter: _DonutPainter(slices, total, t, cs.surfaceContainerHighest),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TOTAL',
                        style: TextStyle(
                            fontSize: 11, letterSpacing: 1, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(money(total),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Slice> slices;
  final double total;
  final double progress;
  final Color track;
  _DonutPainter(this.slices, this.total, this.progress, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 30.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track.withValues(alpha: .35));
    if (total <= 0) return;
    final gap = slices.length > 1 ? 0.045 : 0.0;
    var start = -math.pi / 2;
    for (final sl in slices) {
      final sweep = sl.total / total * math.pi * 2 * progress;
      final draw = math.max(0.0, sweep - gap);
      canvas.drawArc(rect, start + gap / 2, draw, false, paint..color = sl.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.total != total || old.slices != slices;
}

/// Small bar chart of spending in sub-periods (days for a week, months for a
/// year, last six months for a month). Hidden for custom ranges.
class _Trend extends StatelessWidget {
  final _Range range;
  final DateTime start;
  final double Function(DateTime from, DateTime to) totalOf;
  const _Trend({required this.range, required this.start, required this.totalOf});

  @override
  Widget build(BuildContext context) {
    if (range == _Range.custom) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final buckets = <(DateTime, DateTime, String)>[];
    int highlight;
    switch (range) {
      case _Range.week:
        for (var i = 0; i < 7; i++) {
          final a = DateTime(start.year, start.month, start.day + i);
          buckets.add((a, DateTime(a.year, a.month, a.day + 1), DateFormat('E').format(a)[0]));
        }
        final today = _day(DateTime.now());
        highlight = today.difference(start).inDays.clamp(-1, 7);
      case _Range.month:
        for (var i = 5; i >= 0; i--) {
          final a = DateTime(start.year, start.month - i);
          buckets.add((a, DateTime(a.year, a.month + 1), DateFormat('MMM').format(a)));
        }
        highlight = 5;
      case _Range.year:
        for (var i = 0; i < 12; i++) {
          final a = DateTime(start.year, i + 1);
          buckets.add((a, DateTime(a.year, a.month + 1), DateFormat('MMM').format(a)[0]));
        }
        final n = DateTime.now();
        highlight = n.year == start.year ? n.month - 1 : -1;
      case _Range.custom:
        return const SizedBox.shrink();
    }

    final totals = [for (final b in buckets) totalOf(b.$1, b.$2)];
    final maxV = totals.fold(0.0, (a, b) => b > a ? b : a);
    final compact = NumberFormat.compact();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: SizedBox(
          height: 118,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (totals[i] > 0 && buckets.length <= 7)
                        Text(compact.format(totals[i]),
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: maxV == 0 ? 4 : (totals[i] / maxV * 66).clamp(4, 66),
                        margin: EdgeInsets.symmetric(horizontal: buckets.length > 7 ? 3 : 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: i == highlight ? cs.primary : cs.primary.withValues(alpha: .3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(buckets[i].$3,
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
