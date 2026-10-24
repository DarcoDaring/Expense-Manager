import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'add_subscription_screen.dart';

/// Figures from the calculator that fill an EMI form.
class EmiCalcResult {
  final double principal;

  /// The monthly EMI before GST.
  final double emi;
  final int months;

  /// Processing fee before GST.
  final double fee;

  /// GST on the interest and the fee, as a percentage.
  final double gstPercent;
  const EmiCalcResult({
    required this.principal,
    required this.emi,
    required this.months,
    required this.fee,
    required this.gstPercent,
  });
}

class _Calc {
  final double principal;
  final int months;
  final double emi; // principal + interest only
  final double monthlyRate;
  final double interest;
  final double gstInterest;
  final double fee;
  final double gstFee;

  /// GST as a fraction (0.18 for 18%).
  final double gstRate;

  _Calc({
    required this.principal,
    required this.months,
    required this.emi,
    required this.monthlyRate,
    required this.interest,
    required this.gstInterest,
    required this.fee,
    required this.gstFee,
    required this.gstRate,
  });

  double get annualRate => monthlyRate * 1200;
  double get extra => interest + gstInterest + fee + gstFee;
  double get payable => principal + extra;
  double get extraPercent => extra / principal * 100;

  /// The monthly bill with the GST on interest spread evenly over the term.
  double get emiWithGst => emi + gstInterest / months;

  /// The first statement: the EMI, GST on the first month's interest, and the fee.
  double get firstStatement => emi + principal * monthlyRate * gstRate + fee + gstFee;
}

double _emiFor(double p, double r, int n) {
  if (r <= 0) return p / n;
  final f = math.pow(1 + r, n).toDouble();
  return p * r * f / (f - 1);
}

/// The monthly rate that turns [p] into [emi] over [n] months (bisection).
double _rateFor(double p, double emi, int n) {
  if (emi * n <= p + 1e-9) return 0;
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 100; i++) {
    final mid = (lo + hi) / 2;
    if (_emiFor(p, mid, n) > emi) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Works out an EMI, or the interest rate hidden in an EMI you were quoted, and
/// every extra charge: interest, GST and the processing fee.
class EmiCalculatorScreen extends StatefulWidget {
  /// Opened from the EMI form: the button hands the figures back instead of
  /// starting a new EMI.
  final bool pick;
  const EmiCalculatorScreen({super.key, this.pick = false});

  @override
  State<EmiCalculatorScreen> createState() => _EmiCalculatorScreenState();
}

class _EmiCalculatorScreenState extends State<EmiCalculatorScreen> {
  final _amount = TextEditingController();
  final _months = TextEditingController(text: '6');
  final _rate = TextEditingController(text: '14');
  final _emiIn = TextEditingController();
  final _fee = TextEditingController();
  final _gst = TextEditingController(text: '18');
  bool _byRate = true;
  bool _feePercent = false;

  @override
  void dispose() {
    for (final c in [_amount, _months, _rate, _emiIn, _fee, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  _Calc? _compute() {
    final p = double.tryParse(_amount.text.trim()) ?? 0;
    final n = int.tryParse(_months.text.trim()) ?? 0;
    if (p <= 0 || n <= 0) return null;
    final double r;
    final double emi;
    if (_byRate) {
      r = (double.tryParse(_rate.text.trim()) ?? 0) / 1200;
      emi = _emiFor(p, r, n);
    } else {
      emi = double.tryParse(_emiIn.text.trim()) ?? 0;
      if (emi <= 0) return null;
      r = _rateFor(p, emi, n);
    }
    final feeIn = double.tryParse(_fee.text.trim()) ?? 0;
    final fee = _feePercent ? p * feeIn / 100 : feeIn;
    final g = (double.tryParse(_gst.text.trim()) ?? 0) / 100;
    final interest = math.max(0.0, emi * n - p);
    return _Calc(
      principal: p,
      months: n,
      emi: emi,
      monthlyRate: r,
      interest: interest,
      gstInterest: interest * g,
      fee: fee,
      gstFee: fee * g,
      gstRate: g,
    );
  }

  double _round(double v) => double.parse(v.toStringAsFixed(2));

  void _use(_Calc c) {
    final result = EmiCalcResult(
      principal: _round(c.principal),
      emi: _round(c.emi),
      months: c.months,
      fee: _round(c.fee),
      gstPercent: _round(c.gstRate * 100),
    );
    if (widget.pick) {
      Navigator.pop(context, result);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AddSubscriptionScreen(
            emi: true,
            initialPrincipal: result.principal,
            initialEmi: result.emi,
            initialMonths: result.months,
            initialFee: result.fee,
            initialGst: result.gstPercent,
          ),
        ),
      );
    }
  }

  TextInputFormatter get _decimal =>
      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}'));

  Widget _field(TextEditingController c, String label,
      {bool decimal = true, String? suffix, String? prefix}) {
    return TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [decimal ? _decimal : FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, suffixText: suffix, prefixText: prefix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final calc = _compute();

    return Scaffold(
      appBar: AppBar(title: const Text('EMI calculator')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('I know the rate')),
              ButtonSegment(value: false, label: Text('I know the EMI')),
            ],
            selected: {_byRate},
            onSelectionChanged: (v) => setState(() => _byRate = v.first),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field(_amount, 'Amount', prefix: '${s.currency} ')),
              const SizedBox(width: 12),
              Expanded(child: _field(_months, 'Months', decimal: false)),
            ],
          ),
          const SizedBox(height: 14),
          if (_byRate)
            _field(_rate, 'Interest rate (a year)', suffix: '%')
          else
            _field(_emiIn, 'Monthly EMI your bank quotes', prefix: '${s.currency} '),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _field(_fee, 'Processing fee',
                    prefix: _feePercent ? null : '${s.currency} ',
                    suffix: _feePercent ? '%' : null),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: false, label: Text(s.currency.trim())),
                  const ButtonSegment(value: true, label: Text('%')),
                ],
                selected: {_feePercent},
                onSelectionChanged: (v) => setState(() => _feePercent = v.first),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _field(_gst, 'GST', suffix: '%')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
                'GST (18% in India) is charged on the interest and on the processing fee. '
                'Set it to 0 to leave it out.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 20),
          if (calc == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Center(
                  child: Text(
                      _byRate
                          ? 'Enter the amount and months to see the EMI.'
                          : 'Enter the amount, months and the EMI you were quoted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            )
          else ...[
            _result(context, s, calc),
            const SizedBox(height: 14),
            _breakdown(context, s, calc),
            const SizedBox(height: 14),
            _schedule(context, s, calc),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _use(calc),
              icon: Icon(widget.pick ? Icons.check_rounded : Icons.add_card_rounded),
              label: Text(widget.pick ? 'Use these figures' : 'Create an EMI with these figures'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _result(BuildContext context, AppState s, _Calc c) {
    final cs = Theme.of(context).colorScheme;
    String m(double v) => s.money(_round(v));
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHigh,
            Color.lerp(cs.surfaceContainerHigh, cs.primary, .14)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MONTHLY EMI',
              style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  fontSize: 13)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(m(c.emi),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(
              _byRate
                  ? 'Principal plus interest, for ${c.months} months'
                  : 'The interest rate hidden in this EMI is about '
                      '${c.annualRate.toStringAsFixed(2)}% a year',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          if (c.gstInterest > 0.004 || c.gstFee > 0.004) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('Monthly bill with GST (average)',
                              style: TextStyle(color: cs.onSurfaceVariant))),
                      Text(m(c.emiWithGst),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: Text('First statement (EMI + fee + GST)',
                              style: TextStyle(color: cs.onSurfaceVariant))),
                      Text(m(c.firstStatement),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdown(BuildContext context, AppState s, _Calc c) {
    final cs = Theme.of(context).colorScheme;
    final orange = Colors.orange.shade400;
    final pink = Colors.pink.shade300;
    final amber = Colors.amber.shade600;
    String m(double v) => s.money(_round(v));
    int flex(double v) => v <= 0 ? 0 : (v * 1000).round().clamp(1, 1 << 30);

    Widget line(Color? dot, String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: dot ?? Colors.transparent, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: bold ? null : cs.onSurfaceVariant,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
              ),
              Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
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
                  child: Text(m(c.extra),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('${c.extraPercent.toStringAsFixed(1)}% over the amount',
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
                    Expanded(flex: flex(c.principal), child: Container(color: cs.primary)),
                    if (flex(c.interest) > 0)
                      Expanded(flex: flex(c.interest), child: Container(color: orange)),
                    if (flex(c.gstInterest) > 0)
                      Expanded(flex: flex(c.gstInterest), child: Container(color: amber)),
                    if (flex(c.fee) > 0)
                      Expanded(flex: flex(c.fee), child: Container(color: pink)),
                    if (flex(c.gstFee) > 0)
                      Expanded(flex: flex(c.gstFee), child: Container(color: Colors.pink.shade100)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            line(cs.primary, 'Amount financed', m(c.principal)),
            line(orange, 'Interest', m(c.interest)),
            if (c.gstInterest > 0.004) line(amber, 'GST on interest', m(c.gstInterest)),
            if (c.fee > 0.004) line(pink, 'Processing fee', m(c.fee)),
            if (c.gstFee > 0.004) line(Colors.pink.shade100, 'GST on fee', m(c.gstFee)),
            const Divider(height: 22),
            line(null, 'Total you pay', m(c.payable), bold: true),
          ],
        ),
      ),
    );
  }

  /// Month-by-month split of each EMI into principal and interest.
  Widget _schedule(BuildContext context, AppState s, _Calc c) {
    final cs = Theme.of(context).colorScheme;
    String m(double v) => s.money(_round(v));
    var balance = c.principal;
    final rows = <TableRow>[
      TableRow(
        children: [
          for (final h in ['Month', 'Principal', 'Interest', 'Balance'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(h,
                  textAlign: h == 'Month' ? TextAlign.left : TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    ];
    for (var i = 1; i <= c.months && i <= 120; i++) {
      final interest = balance * c.monthlyRate;
      final principalPart = c.emi - interest;
      balance = math.max(0.0, balance - principalPart);
      rows.add(TableRow(
        children: [
          for (final (j, t) in [
            ('$i', TextAlign.left),
            (m(principalPart), TextAlign.right),
            (m(interest), TextAlign.right),
            (m(balance), TextAlign.right),
          ].indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(t.$1,
                  textAlign: t.$2,
                  style: TextStyle(
                      fontSize: 13,
                      color: j == 2 ? Colors.orange.shade400 : null,
                      fontWeight: j == 0 ? FontWeight.w600 : FontWeight.w500)),
            ),
        ],
      ));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Month by month', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('How each EMI splits into principal and interest',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        children: [
          Table(
            columnWidths: const {
              0: FlexColumnWidth(.8),
              1: FlexColumnWidth(1.4),
              2: FlexColumnWidth(1.3),
              3: FlexColumnWidth(1.5),
            },
            children: rows,
          ),
        ],
      ),
    );
  }
}
