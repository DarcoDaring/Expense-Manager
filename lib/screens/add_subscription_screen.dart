import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';

class AddSubscriptionScreen extends StatefulWidget {
  final Recurring? existing;
  const AddSubscriptionScreen({super.key, this.existing});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _name;
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
    _icon = r?.icon ?? kSubscriptionIcon;
    _date = r?.nextDue ?? dayOnly(DateTime.now());
    _frequency = r?.frequency ?? Frequency.monthly;
    _remind = r?.remindDays ?? 1;
    _active = r?.active ?? true;
    _categoryId = r?.categoryId;
    _modeId = r?.paymentModeId;
    if (r == null && s.expenses.isNotEmpty) {
      _categoryId = s.expenses.first.categoryId;
      _modeId = s.expenses.first.paymentModeId;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _date = dayOnly(d));
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _categoryId == null || _modeId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final old = widget.existing;
    // Moving the date re-anchors the schedule (e.g. monthly on the 5th -> 12th).
    final unchanged = old != null && _date == dayOnly(old.nextDue);

    if (_remind >= 0) await NotificationService.instance.requestPermission();
    await s.saveRecurring(Recurring(
      id: old?.id,
      name: _name.text.trim(),
      icon: _icon,
      amount: double.parse(_amount.text.trim()),
      note: _note.text.trim(),
      categoryId: _categoryId!,
      paymentModeId: _modeId!,
      frequency: _frequency,
      startDate: unchanged ? old.startDate : _date,
      nextDue: _date,
      active: _active,
      remindDays: _remind,
    ));
    nav.pop();
  }

  Future<void> _pickIcon() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose an icon',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < kIcons.length; i++)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(ctx, i),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: i == _icon ? cs.primary.withValues(alpha: .18) : null,
                                border: Border.all(
                                    color: i == _icon ? cs.primary : cs.outlineVariant,
                                    width: 1.4),
                              ),
                              child: Icon(kIcons[i],
                                  color: i == _icon ? cs.primary : cs.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _icon = picked);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this subscription?'),
        content: const Text('Expenses you already marked as paid stay in your list.'),
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
    if (_modeId != null && !s.paymentModes.any((m) => m.id == _modeId)) _modeId = null;
    final inPast = !editing && _date.isBefore(dayOnly(DateTime.now()));

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit subscription' : 'New subscription')),
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
                  Text('AMOUNT',
                      style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          fontSize: 13)),
                  TextFormField(
                    controller: _amount,
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
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(iconAt(_icon), color: cs.primary, size: 28),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(Icons.edit_rounded, size: 13, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        hintText: 'e.g. Netflix, House rent', counterText: ''),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Give this subscription a name' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
            _label(editing ? 'Next due date' : 'First due date'),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.event_repeat_rounded, size: 22)),
                child: Text(DateFormat('EEEE, d MMMM y').format(_date)),
              ),
            ),
            if (inPast)
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
                    avatar: Icon(iconAt(c.icon),
                        size: 18, color: _categoryId == c.id ? null : Color(c.color)),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
            if (_submitted && _categoryId == null) _error('Pick a category'),
            const SizedBox(height: 24),
            _label('Payment mode'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in s.paymentModes)
                  ChoiceChip(
                    avatar: Icon(iconAt(m.icon), size: 18),
                    label: Text(m.name),
                    selected: _modeId == m.id,
                    onSelected: (_) => setState(() => _modeId = m.id),
                  ),
              ],
            ),
            if (_submitted && _modeId == null) _error('Pick a payment mode'),
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
            if (editing) ...[
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(editing ? 'Save changes' : 'Save subscription'),
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _error(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}
