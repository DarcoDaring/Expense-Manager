import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/spend_card.dart';

class AddExpenseScreen extends StatefulWidget {
  final Expense? existing;
  const AddExpenseScreen({super.key, this.existing});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  int? _categoryId;
  int? _modeId;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final s = context.read<AppState>();
    _amount = TextEditingController(
        text: e == null ? '' : (e.amount == e.amount.roundToDouble() ? e.amount.toStringAsFixed(0) : e.amount.toString()));
    _note = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    _modeId = e?.paymentModeId;
    // Default a new entry to whatever was used last.
    if (e == null && s.expenses.isNotEmpty) {
      _categoryId = s.expenses.first.categoryId;
      _modeId = s.expenses.first.paymentModeId;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _categoryId == null || _modeId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    await s.saveExpense(Expense(
      id: widget.existing?.id,
      amount: double.parse(_amount.text.trim()),
      note: _note.text.trim(),
      categoryId: _categoryId!,
      paymentModeId: _modeId!,
      date: _date,
    ));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    // A selected item may have vanished (e.g. deleted elsewhere).
    if (_categoryId != null && !s.categories.any((c) => c.id == _categoryId)) _categoryId = null;
    if (_modeId != null && !s.paymentModes.any((m) => m.id == _modeId)) _modeId = null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit expense' : 'New expense')),
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
                          fontSize: 40, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
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
            _label('Date'),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today_rounded, size: 20)),
                child: Text(DateFormat('EEEE, d MMMM y').format(_date)),
              ),
            ),
            const SizedBox(height: 24),
            _label('Notes'),
            TextFormField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What was this for? (optional)'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(editing ? 'Save changes' : 'Save expense'),
            ),
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
