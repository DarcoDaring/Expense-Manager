import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom-sheet calculator. Resolves to the final amount, or null on Cancel.
Future<double?> showCalculator(BuildContext context, {String initial = ''}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _Calculator(initial: initial),
  );
}

/// Evaluates "12+3×4÷2-5%" style input. Returns null if it is incomplete or
/// divides by zero.
double? evaluateExpression(String input) {
  final tokens = RegExp(r'\d+\.?\d*|\.\d+|[+\-×÷%]').allMatches(input).map((m) => m[0]!).toList();
  if (tokens.isEmpty) return null;

  // Fold percent into the number before it: "50%" -> 0.5
  final flat = <String>[];
  for (final t in tokens) {
    if (t == '%') {
      final v = flat.isEmpty ? null : double.tryParse(flat.last);
      if (v == null) return null;
      flat[flat.length - 1] = (v / 100).toString();
    } else {
      flat.add(t);
    }
  }

  // Allow a leading minus.
  if (flat.first == '-') {
    if (flat.length < 2) return null;
    flat
      ..removeAt(0)
      ..[0] = '-${flat[0]}';
  }

  // First pass: × and ÷
  final terms = <String>[flat.first];
  for (var i = 1; i < flat.length; i += 2) {
    final op = flat[i];
    if (i + 1 >= flat.length) return null;
    final rhs = double.tryParse(flat[i + 1]);
    if (rhs == null) return null;
    if (op == '×' || op == '÷') {
      final lhs = double.tryParse(terms.removeLast());
      if (lhs == null) return null;
      if (op == '÷' && rhs == 0) return null;
      terms.add((op == '×' ? lhs * rhs : lhs / rhs).toString());
    } else {
      terms
        ..add(op)
        ..add(rhs.toString());
    }
  }

  // Second pass: + and -
  var total = double.tryParse(terms.first);
  if (total == null) return null;
  for (var i = 1; i < terms.length; i += 2) {
    final rhs = double.tryParse(terms[i + 1]);
    if (rhs == null) return null;
    total = terms[i] == '+' ? total! + rhs : total! - rhs;
  }
  return total;
}

String _fmt(double v) {
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
}

class _Calculator extends StatefulWidget {
  final String initial;
  const _Calculator({required this.initial});

  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  late String _expr = widget.initial;

  static const _ops = '+-×÷';

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (k) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        case '=':
          final v = evaluateExpression(_expr);
          if (v != null) _expr = _fmt(v);
        default:
          if (_ops.contains(k)) {
            if (_expr.isEmpty) {
              if (k == '-') _expr = '-';
              return;
            }
            // Replace a trailing operator instead of stacking them.
            if (_ops.contains(_expr[_expr.length - 1])) {
              _expr = _expr.substring(0, _expr.length - 1);
            }
          }
          if (k == '%' && (_expr.isEmpty || _ops.contains(_expr[_expr.length - 1]))) return;
          if (k == '.') {
            final lastNumber = _expr.split(RegExp(r'[+\-×÷%]')).last;
            if (lastNumber.contains('.')) return;
          }
          if (_expr.length < 40) _expr += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = evaluateExpression(_expr);
    final isPlain = RegExp(r'^\d*\.?\d*$').hasMatch(_expr);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 20)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 20)),
                onPressed: () => Navigator.pop(context, result == null ? null : double.parse(result.toStringAsFixed(2))),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHigh,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_expr.isEmpty ? '0' : _expr,
                    style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        color: _expr.isEmpty ? cs.onSurfaceVariant : cs.onSurface)),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 22,
                child: Text(
                    isPlain || result == null ? '' : _fmt(result),
                    style: TextStyle(fontSize: 17, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 360,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    for (final row in const [
                      ['C', '⌫', '%'],
                      ['7', '8', '9'],
                      ['4', '5', '6'],
                      ['1', '2', '3'],
                      ['00', '0', '.'],
                    ])
                      Expanded(
                        child: Row(
                          children: [
                            for (final k in row)
                              Expanded(
                                child: _Key(
                                  label: k,
                                  tint: row == const ['C', '⌫', '%']
                                      ? cs.surfaceContainerHighest
                                      : cs.surface,
                                  onTap: () => _tap(k),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    for (final k in const ['÷', '×', '-', '+', '='])
                      Expanded(
                        child: _Key(
                          label: k,
                          tint: cs.onSurface,
                          textColor: cs.surface,
                          onTap: () => _tap(k),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final Color tint;
  final Color? textColor;
  final VoidCallback onTap;
  const _Key({required this.label, required this.tint, required this.onTap, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: label == '⌫'
              ? Icon(Icons.backspace_outlined, color: textColor)
              : Text(label,
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w500, color: textColor)),
        ),
      ),
    );
  }
}
