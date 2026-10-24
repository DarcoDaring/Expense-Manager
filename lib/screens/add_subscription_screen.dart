import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../widgets/account_picker.dart';
import '../widgets/pay_confirm_sheet.dart';
import '../widgets/spend_card.dart';
import '../widgets/app_icon.dart';
import '../widgets/edit_dialogs.dart';
import '../widgets/foreclose_sheet.dart';
import 'emi_calculator_screen.dart';

class AddSubscriptionScreen extends StatefulWidget {
  final Recurring? existing;

  /// Create an EMI instead of a subscription (ignored when editing).
  final bool emi;

  /// Figures to start a new EMI with (from the EMI calculator).
  final double? initialPrincipal;
  final double? initialEmi;
  final int? initialMonths;
  final double? initialFee;
  final double? initialGst;
  const AddSubscriptionScreen({
    super.key,
    this.existing,
    this.emi = false,
    this.initialPrincipal,
    this.initialEmi,
    this.initialMonths,
    this.initialFee,
    this.initialGst,
  });

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _name;
  late final TextEditingController _total;
  late final TextEditingController _paid;
  late final TextEditingController _principal;
  late final TextEditingController _fee;
  late final TextEditingController _gst;
  late final TextEditingController _initial;
  int _delay = 0;
  late int _icon;
  late DateTime _date;
  late Frequency _frequency;
  late int _remind;
  late bool _active;
  int? _categoryId;
  int? _modeId;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    final s = context.read<AppState>();
    _amount = TextEditingController(
        text: r == null
            ? ''
            : (r.amount == r.amount.roundToDouble()
                ? r.amount.toStringAsFixed(0)
                : r.amount.toString()));
    _note = TextEditingController(text: r?.note ?? '');
    _name = TextEditingController(text: r?.name ?? '');
    _total = TextEditingController(
        text: r == null || r.totalCount == 0 ? '' : '${r.totalCount}');
    _paid = TextEditingController(text: r == null ? '0' : '${r.paidCount}');
    _principal = TextEditingController(
        text: r == null || r.principal == 0 ? '' : _plain(r.principal));
    _fee = TextEditingController(text: r == null || r.fee == 0 ? '' : _plain(r.fee));
    // GST on interest and fee: 18% for a new EMI unless told otherwise.
    _gst = TextEditingController(
        text: r == null ? _plain(widget.initialGst ?? 18) : _plain(r.gstRate));
    _delay = r?.firstDelay ?? 0;
    _initial = TextEditingController(
        text: r == null || r.initialInterest == 0 ? '' : _plain(r.initialInterest));
    if (r == null) {
      if (widget.initialEmi != null) _amount.text = _plain(widget.initialEmi!);
      if (widget.initialPrincipal != null) _principal.text = _plain(widget.initialPrincipal!);
      if (widget.initialMonths != null) _total.text = '${widget.initialMonths}';
      if (widget.initialFee != null && widget.initialFee! > 0) {
        _fee.text = _plain(widget.initialFee!);
      }
    }
    _icon = r?.icon ?? kSubscriptionIcon;
    // A card EMI is dated by its purchase, not by a due date.
    _date = r != null && s.isCardEmi(r)
        ? dayOnly(r.startDate)
        : (r?.nextDue ?? dayOnly(DateTime.now()));
    _frequency = r?.frequency ?? Frequency.monthly;
    _remind = r?.remindDays ?? 1;
    _active = r?.active ?? true;
    _categoryId = r?.categoryId;
    _modeId = r?.paymentModeId;
    if (r == null && s.expenses.isNotEmpty) {
      _categoryId = s.expenses.first.categoryId;
      _modeId = s.expenses.first.paymentModeId;
    }
    // An EMI can only be paid from a bank account or a credit card.
    if (!AccountPicker.isAllowed(s, _modeId, _allowed)) _modeId = null;
  }

  bool get _emi => widget.existing?.isEmi ?? widget.emi;
  Set<AccountType>? get _allowed => _emi ? kEmiAccountTypes : null;
  String get _noun => _emi ? 'EMI' : 'subscription';

  /// The account this EMI is paid from, and whether that is a credit card.
  Account? get _card => !_emi || _modeId == null
      ? null
      : context.read<AppState>().accountOfMode(_modeId!);
  bool get _cardEmi => _card?.type == AccountType.credit;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _name.dispose();
    _total.dispose();
    _paid.dispose();
    _principal.dispose();
    _fee.dispose();
    _gst.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      // A card EMI starts with a purchase that has already been made.
      lastDate: _cardEmi ? DateTime.now() : DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _date = dayOnly(d));
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _categoryId == null || _modeId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final old = widget.existing;
    final total = _emi ? int.parse(_total.text.trim()) : 0;
    final paid = _emi ? int.parse(_paid.text.trim().isEmpty ? '0' : _paid.text.trim()) : 0;
    final principal = _emi ? (double.tryParse(_principal.text.trim()) ?? 0) : 0.0;
    final fee = _emi ? (double.tryParse(_fee.text.trim()) ?? 0) : 0.0;
    final card = _cardEmi;
    // Moving the date re-anchors the schedule (e.g. monthly on the 5th -> 12th).
    final unchanged = !card && old != null && _date == dayOnly(old.nextDue);

    if (_remind >= 0 && !card) await NotificationService.instance.requestPermission();
    await s.saveRecurring(Recurring(
      id: old?.id,
      name: _name.text.trim(),
      icon: _icon,
      amount: double.parse(_amount.text.trim()),
      note: _note.text.trim(),
      categoryId: _categoryId!,
      paymentModeId: _modeId!,
      frequency: _emi ? Frequency.monthly : _frequency,
      startDate: unchanged ? old.startDate : _date,
      nextDue: _date,
      // Paying the last instalment finishes an EMI. A card EMI runs by itself.
      active: old != null && old.foreclosed
          ? false
          : (card ? true : _active && !(_emi && paid >= total)),
      remindDays: _remind,
      isEmi: _emi,
      totalCount: total,
      paidCount: paid,
      principal: principal,
      fee: fee,
      gstRate: _emi ? (double.tryParse(_gst.text.trim()) ?? 0) : 0,
      firstDelay: card ? _delay : 0,
      closedOn: old?.closedOn ?? 0,
      closePrincipal: old?.closePrincipal ?? 0,
      closeCharge: old?.closeCharge ?? 0,
      closeGst: old?.closeGst ?? 0,
      closureExpenseId: old?.closureExpenseId,
      initialInterest: card ? (double.tryParse(_initial.text.trim()) ?? 0) : 0,
      created: (old?.created ?? 0) > 0 ? old!.created : DateTime.now().millisecondsSinceEpoch,
      postedCount: old?.postedCount ?? 0,
      purchaseExpenseId: old?.purchaseExpenseId,
    ));
    nav.pop();
  }

  Future<void> _openCalculator() async {
    final r = await Navigator.push<EmiCalcResult>(
        context, MaterialPageRoute(builder: (_) => const EmiCalculatorScreen(pick: true)));
    if (r == null || !mounted) return;
    setState(() {
      _principal.text = _plain(r.principal);
      _amount.text = _plain(r.emi);
      _total.text = '${r.months}';
      _fee.text = r.fee > 0 ? _plain(r.fee) : '';
      _gst.text = _plain(r.gstPercent);
    });
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPicker(context, selected: _icon);
    if (picked != null) setState(() => _icon = picked);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete this $_noun?'),
        content: Text(_cardEmi
            ? 'The amount held on your card is released. Instalments already billed stay in your expenses.'
            : 'Expenses you already marked as paid stay in your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await context.read<AppState>().deleteRecurring(widget.existing!.id!);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    if (_categoryId != null && !s.categories.any((c) => c.id == _categoryId)) _categoryId = null;
    if (_modeId != null && !AccountPicker.isAllowed(s, _modeId, _allowed)) _modeId = null;
    final inPast = !editing && _date.isBefore(dayOnly(DateTime.now()));

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit $_noun' : 'New $_noun'),
        actions: [
          if (_emi)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                tooltip: 'EMI calculator',
                onPressed: _openCalculator,
                icon: const Icon(Icons.calculate_rounded),
              ),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: SpendCard.decoration(cs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_emi ? 'MONTHLY EMI · INCLUDING INTEREST' : 'AMOUNT',
                      style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          fontSize: 13)),
                  TextFormField(
                    controller: _amount,
                    onChanged: (_) => setState(() {}),
                    autofocus: !editing,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}')),
                    ],
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      prefixText: '${s.currency} ',
                      prefixStyle: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant),
                      hintText: '0',
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'Enter an amount greater than 0';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _label('Name & icon'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _pickIcon,
                  child: Stack(
                    children: [
                      IconTile(_icon, size: 58),
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                          child: Icon(Icons.edit_rounded, size: 11, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        hintText: _emi ? 'e.g. Phone EMI, Car loan' : 'e.g. Netflix, House rent',
                        counterText: ''),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Give this $_noun a name' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_emi) ...[
              _label('Instalments'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _total,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      decoration: const InputDecoration(
                          labelText: 'Total months', counterText: ''),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 1 ? 'Enter the number of instalments' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _paid,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      decoration: const InputDecoration(
                          labelText: 'Already paid', counterText: ''),
                      validator: (v) {
                        final paid = int.tryParse((v ?? '').trim().isEmpty ? '0' : v!.trim());
                        final total = int.tryParse(_total.text.trim());
                        if (paid == null) return 'Enter a number';
                        if (total != null && paid > total) return 'More than total';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _label('Cost'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _principal,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                          labelText: _cardEmi ? 'Total amount' : 'Amount financed',
                          counterText: ''),
                      validator: (v) {
                        final p = double.tryParse((v ?? '').trim()) ?? 0;
                        if (_cardEmi && p <= 0) return 'Enter the amount held on the card';
                        final emi = double.tryParse(_amount.text.trim()) ?? 0;
                        final n = int.tryParse(_total.text.trim()) ?? 0;
                        if (p > 0 && emi > 0 && n > 0 && emi * n < p - 0.004) {
                          return 'EMI × months is below this';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _fee,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}\.?\d{0,2}')),
                      ],
                      decoration: const InputDecoration(
                          labelText: 'One-time fee', counterText: ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _gst,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'GST on interest & fee',
                  suffixText: '%',
                  helperText: 'Usually 18%. Use 0 if your bank does not charge it.',
                  counterText: '',
                ),
              ),
              if (_cardEmi) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _initial,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Initial interest (optional)',
                    prefixText: '${s.currency} ',
                    helperMaxLines: 3,
                    helperText: 'Interest billed on the first statement, before the first EMI. '
                        'If the letter\'s total interest is more than EMI × months − amount, '
                        'the difference is this.',
                    counterText: '',
                  ),
                ),
              ],
              _emiSummary(s, cs),
              const SizedBox(height: 24),
            ] else ...[
              _label('Repeats'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<Frequency>(
                  showSelectedIcon: false,
                  segments: [
                    for (final f in Frequency.values)
                      ButtonSegment(value: f, label: Text(f.label)),
                  ],
                  selected: {_frequency},
                  onSelectionChanged: (v) => setState(() => _frequency = v.first),
                ),
              ),
              const SizedBox(height: 24),
            ],
            _label(_cardEmi ? 'Purchase date' : (editing ? 'Next due date' : 'First due date')),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.event_repeat_rounded, size: 22)),
                child: Text(DateFormat('EEEE, d MMMM y').format(_date)),
              ),
            ),
            if (_cardEmi) ...[_cardNote(s, cs), _delayChoice(s, cs)],
            if (inPast && !_cardEmi)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                    'This date has passed, so it will show as overdue until you mark it paid.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ),
            const SizedBox(height: 24),
            _label('Category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in s.categories)
                  ChoiceChip(
                    avatar: AppIcon(c.icon,
                        size: 18, color: _categoryId == c.id ? null : Color(c.color)),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                  onPressed: () async {
                    final id = await showCategoryDialog(context);
                    if (id != null && mounted) setState(() => _categoryId = id);
                  },
                ),
              ],
            ),
            if (_submitted && _categoryId == null) _error('Pick a category'),
            const SizedBox(height: 24),
            AccountPicker(
              modeId: _modeId,
              onChanged: (id) => setState(() {
                _modeId = id;
                // A card EMI starts with a purchase that has already been made.
                final today = dayOnly(DateTime.now());
                if (_cardEmi && _date.isAfter(today)) _date = today;
              }),
              allowed: _allowed,
              error: _submitted && _modeId == null
                  ? (_emi ? 'Pick the bank account or credit card for this EMI' : 'Pick an account')
                  : null,
            ),
            // A card EMI is covered by the card's own statement and due reminders.
            if (!_cardEmi) ...[
              const SizedBox(height: 24),
              _label('Remind me'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in kReminderChoices)
                    ChoiceChip(
                      label: Text(reminderLabel(d)),
                      selected: _remind == d,
                      onSelected: (_) => setState(() => _remind = d),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            _label('Notes'),
            TextFormField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'Anything to remember (optional)'),
            ),
            if (editing && !_cardEmi) ...[
              const SizedBox(height: 4),
              Card(
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text('Pause to stop reminders and due dates'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ),
            ],
            if (editing && _emi) ...[
              const SizedBox(height: 16),
              _closureSection(s, cs),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(editing ? 'Save changes' : 'Save $_noun'),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Where a card EMI's instalments go on the card.
  /// Foreclose an EMI, or reopen one that was closed by mistake.
  Widget _closureSection(AppState s, ColorScheme cs) {
    final r = widget.existing!;
    if (r.foreclosed) {
      String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_busy_rounded, color: Colors.green.shade400),
                  const SizedBox(width: 10),
                  Text('Foreclosed on ${DateFormat('d MMM y').format(r.closedDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  'Paid ${m(r.closePrincipal)} of principal'
                  '${r.closeCharge > 0.004 ? ' + ${m(r.closeCharge)} charge' : ''}'
                  '${r.closeGst > 0.004 ? ' + ${m(r.closeGst)} GST' : ''}.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reopen,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Reopen EMI'),
              ),
            ],
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _foreclose,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: const Icon(Icons.event_busy_rounded),
      label: const Text('Foreclose EMI'),
    );
  }

  Future<void> _foreclose() async {
    final nav = Navigator.of(context);
    final done = await showForeclose(context, widget.existing!);
    if (done == true && mounted) nav.pop();
  }

  Future<void> _reopen() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reopen this EMI?'),
        content: const Text(
            'The foreclosure entry is removed and the remaining instalments start again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reopen')),
        ],
      ),
    );
    if (ok != true) return;
    await s.reopenEmi(widget.existing!);
    nav.pop();
  }

  /// The statements the first charges land on, from the purchase date.
  (DateTime, DateTime) _firstDates(AppState s, Account card) {
    final running = (int.tryParse(_paid.text.trim()) ?? 0) > 0;
    final first = s.emiFirstStatement(card, running ? DateTime.now() : _date);
    var emi = first;
    for (var i = 0; i < _delay; i++) {
      emi = monthDay(emi.year, emi.month + 1, card.billingDay);
    }
    return (first, emi);
  }

  Widget _cardNote(AppState s, ColorScheme cs) {
    final card = _card;
    if (card == null) return const SizedBox.shrink();
    final running = (int.tryParse(_paid.text.trim()) ?? 0) > 0;
    final (first, emi) = _firstDates(s, card);
    final fmt = DateFormat('d MMM y');
    final initial = double.tryParse(_initial.text.trim()) ?? 0;
    final text = running
        ? 'This EMI is already running, so ${card.name}\'s available limit should already '
            'include it. Only the instalments still to come are tracked, starting with the '
            'statement of ${fmt.format(emi)}.'
        : 'The amount is held on ${card.name}\'s limit from this date. '
            '${initial > 0 ? 'The initial interest is billed on the statement of ${fmt.format(first)}. ' : ''}'
            'The first EMI is added to the statement of ${fmt.format(emi)}, then every month.';
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(text,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
    );
  }

  /// Which statement the first EMI is billed on (some banks skip one).
  Widget _delayChoice(AppState s, ColorScheme cs) {
    final card = _card;
    if (card == null) return const SizedBox.shrink();
    final first = s.emiFirstStatement(
        card, (int.tryParse(_paid.text.trim()) ?? 0) > 0 ? DateTime.now() : _date);
    final later = monthDay(first.year, first.month + 1, card.billingDay);
    final fmt = DateFormat('d MMM');
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('First EMI is billed on',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
              'Your bank letter says which statement. “Following your upcoming statement” means the later one.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Next statement · ${fmt.format(first)}'),
                selected: _delay == 0,
                onSelected: (_) => setState(() => _delay = 0),
              ),
              ChoiceChip(
                label: Text('The one after · ${fmt.format(later)}'),
                selected: _delay == 1,
                onSelected: (_) => setState(() => _delay = 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Live interest / total cost from the figures typed so far.
  Widget _emiSummary(AppState s, ColorScheme cs) {
    final p = double.tryParse(_principal.text.trim()) ?? 0;
    final emi = double.tryParse(_amount.text.trim()) ?? 0;
    final n = int.tryParse(_total.text.trim()) ?? 0;
    final fee = double.tryParse(_fee.text.trim()) ?? 0;
    final g = (double.tryParse(_gst.text.trim()) ?? 0) / 100;
    if (p <= 0 || emi <= 0 || n <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Text(
            _cardEmi
                ? 'Enter the total amount, the monthly EMI and the months to see the interest.'
                : 'Optional: enter the amount financed to see the interest you pay.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
      );
    }
    final initial = _cardEmi ? (double.tryParse(_initial.text.trim()) ?? 0) : 0.0;
    final interest = (emi * n - p < 0 ? 0.0 : emi * n - p) + initial;
    final gst = (interest + fee) * g;
    final total = emi * n + initial + fee + gst;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
    Widget line(String l, String v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(l, style: TextStyle(color: bold ? null : cs.onSurfaceVariant)),
              const Spacer(),
              Text(v,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: .25)),
      ),
      child: Column(
        children: [
          line('Amount financed', m(p)),
          line('Interest', m(interest), color: Colors.orange.shade400),
          if (gst > 0.004) line('GST on interest & fee', m(gst), color: Colors.orange.shade400),
          if (fee > 0) line('One-time fee', m(fee), color: Colors.orange.shade400),
          const Divider(height: 18),
          line('Total you pay', m(total), bold: true),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                'Extra ${m(interest + fee + gst)} · ${((interest + fee + gst) / p * 100).toStringAsFixed(1)}% over the amount financed',
                style: TextStyle(fontSize: 12.5, color: Colors.orange.shade400)),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _error(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
