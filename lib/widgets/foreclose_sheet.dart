import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'account_picker.dart';
import 'pay_confirm_sheet.dart';

/// Asks how an EMI is being closed early and does it. Resolves to true when the
/// EMI was foreclosed.
Future<bool?> showForeclose(BuildContext context, Recurring r) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ForecloseSheet(r: r),
  );
}

String _plain(double v) {
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
}

class _ForecloseSheet extends StatefulWidget {
  final Recurring r;
  const _ForecloseSheet({required this.r});

  @override
  State<_ForecloseSheet> createState() => _ForecloseSheetState();
}

class _ForecloseSheetState extends State<_ForecloseSheet> {
  late final TextEditingController _principal;
  final _charge = TextEditingController();
  late final TextEditingController _gst;
  bool _percent = false;
  DateTime _date = dayOnly(DateTime.now());
  int? _modeId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _principal = TextEditingController(text: _plain(s.emiOutstanding(widget.r)));
    _gst = TextEditingController(text: _plain(widget.r.gstRate));
    if (AccountPicker.isAllowed(s, widget.r.paymentModeId, kEmiAccountTypes)) {
      _modeId = widget.r.paymentModeId;
    }
  }

  @override
  void dispose() {
    _principal.dispose();
    _charge.dispose();
    _gst.dispose();
    super.dispose();
  }

  double get _p => double.tryParse(_principal.text.trim()) ?? 0;
  double get _chargeAmount {
    final c = double.tryParse(_charge.text.trim()) ?? 0;
    return _percent ? _p * c / 100 : c;
  }

  double get _gstAmount => _chargeAmount * (double.tryParse(_gst.text.trim()) ?? 0) / 100;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: dayOnly(widget.r.startDate),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = dayOnly(d));
  }

  Future<void> _confirm() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final card = s.isCardEmi(widget.r);
    if (!card && _modeId == null) return;
    setState(() => _busy = true);
    await s.foreclose(
      widget.r,
      date: _date,
      principal: _p,
      charge: _chargeAmount,
      gstPercent: double.tryParse(_gst.text.trim()) ?? 0,
      payFromModeId: _modeId,
    );
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final r = widget.r;
    final card = s.isCardEmi(r);
    final acc = card ? s.accountOfMode(r.paymentModeId) : null;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
    final total = _p + _chargeAmount + _gstAmount;
    final fmt = DateFormat('d MMM y');
    final billedOn = acc == null ? null : s.emiFirstStatement(acc, _date);

    Widget numberField(TextEditingController c, String label,
            {String? prefix, String? suffix, String? helper}) =>
        TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}'))],
          decoration: InputDecoration(
              labelText: label,
              prefixText: prefix,
              suffixText: suffix,
              helperText: helper,
              helperMaxLines: 3),
        );

    Widget line(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(l, style: TextStyle(color: bold ? null : cs.onSurfaceVariant)),
              const Spacer(),
              Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Foreclose ${s.recurringTitle(r)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Close this EMI early. The remaining instalments stop.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Foreclosure date',
                    prefixIcon: Icon(Icons.event_rounded, size: 22)),
                child: Text(fmt.format(_date)),
              ),
            ),
            const SizedBox(height: 14),
            numberField(_principal, 'Outstanding principal',
                prefix: '${s.currency} ',
                helper: 'Worked out from the schedule. Use the figure in your foreclosure '
                    'letter if it differs.'),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: numberField(_charge, 'Foreclosure charge',
                      prefix: _percent ? null : '${s.currency} ',
                      suffix: _percent ? '%' : null),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: false, label: Text(s.currency.trim())),
                    const ButtonSegment(value: true, label: Text('%')),
                  ],
                  selected: {_percent},
                  onSelectionChanged: (v) => setState(() => _percent = v.first),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: numberField(_gst, 'GST', suffix: '%')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                  'Banks usually charge about 3% of the outstanding principal (with a minimum), '
                  'plus GST. Leave it empty if there is none.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
            ),
            if (!card) ...[
              const SizedBox(height: 18),
              AccountPicker(
                label: 'Paid from',
                modeId: _modeId,
                allowed: kEmiAccountTypes,
                onChanged: (id) => setState(() => _modeId = id),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.primary.withValues(alpha: .25)),
              ),
              child: Column(
                children: [
                  line('Outstanding principal', m(_p)),
                  if (_chargeAmount > 0.004) line('Foreclosure charge', m(_chargeAmount)),
                  if (_gstAmount > 0.004) line('GST on the charge', m(_gstAmount)),
                  const Divider(height: 18),
                  line('You pay', m(total), bold: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                  card
                      ? 'Shown as an expense today, and billed to ${acc?.name ?? 'your card'} '
                          'on the statement of ${fmt.format(billedOn!)}.'
                      : 'Recorded as an expense on ${fmt.format(_date)}.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || (!card && _modeId == null) ? null : _confirm,
              icon: const Icon(Icons.event_busy_rounded),
              label: const Text('Foreclose EMI'),
            ),
          ],
        ),
      ),
    );
  }
}
