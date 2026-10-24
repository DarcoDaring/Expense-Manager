import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/attachment_service.dart';
import '../state/app_state.dart';
import '../widgets/account_sheet.dart';
import '../widgets/app_icon.dart';
import '../widgets/calculator_sheet.dart';
import '../widgets/picker_sheet.dart';
import 'accounts_screen.dart';
import 'attachment_viewer.dart';
import 'manage_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  final Expense? existing;

  /// Edit a credit card bill payment instead of an expense.
  final CardPayment? existingPayment;

  /// Open straight into "pay credit card bill" for this card.
  final int? billCardId;

  /// Edit an income entry.
  final Income? existingIncome;
  const AddExpenseScreen(
      {super.key, this.existing, this.existingPayment, this.billCardId, this.existingIncome});

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

  // Receipt photo (expenses only).
  String? _attachment;
  String? _pickedThisSession; // added here and not saved yet
  bool _saved = false;

  // A payment can be split across several accounts, one row (leg) for each.
  bool _split = false;
  final List<_Leg> _legs = [];

  // Credit card bill payment mode.
  // Any account may pay a bill, including a credit card (even the same one).
  static const _billFrom = {...AccountType.values};
  late bool _bill;
  int? _cardId;
  int? _fromId;
  String? _billError;

  // Income goes into a cash or bank account only.
  static const _incomeTo = {AccountType.cash, AccountType.bank};
  late bool _income;
  int? _incCategoryId;
  int? _incModeId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final s = context.read<AppState>();
    _amount = TextEditingController(text: e == null ? '' : _plain(e.amount));
    _note = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    _modeId = e?.paymentModeId;
    _attachment = e?.attachment;
    if (e?.splitGroup != null) {
      final legs = s.legsOf(e!);
      _split = true;
      _amount.text = _plain(legs.fold(0.0, (a, l) => a + l.amount));
      for (final l in legs) {
        _legs.add(_Leg(modeId: l.paymentModeId, text: _plain(l.amount), id: l.id));
      }
    }
    // Default a new entry to whatever was used last.
    if (e == null && s.expenses.isNotEmpty) {
      _categoryId = s.expenses.first.categoryId;
      _modeId = s.expenses.first.paymentModeId;
    }

    final p = widget.existingPayment;
    _bill = p != null || widget.billCardId != null;
    _cardId = p?.cardId ?? widget.billCardId;
    if (p != null) {
      _amount.text = _plain(p.amount);
      _note.text = p.note;
      _date = p.date;
      _fromId = p.modeId;
    } else if (_allowedFrom(s, _modeId)) {
      _fromId = _modeId;
    }

    final inc = widget.existingIncome;
    _income = inc != null;
    if (inc != null) {
      _amount.text = _plain(inc.amount);
      _note.text = inc.note;
      _date = inc.date;
      _incCategoryId = inc.categoryId;
      _incModeId = inc.paymentModeId;
    } else {
      // Default to the last income's category and account.
      final last = s.incomes.firstOrNull;
      _incCategoryId = last?.categoryId ?? s.incomeCategories.firstOrNull?.id;
      _incModeId = _incomeAllowed(s, last?.paymentModeId)
          ? last!.paymentModeId
          : s.paymentModes.where((m) => _incomeAllowed(s, m.id)).firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    // Don't leave a photo behind if the user walks away without saving.
    if (!_saved) AttachmentService.delete(_pickedThisSession);
    _amount.dispose();
    _note.dispose();
    for (final l in _legs) {
      l.amount.dispose();
    }
    super.dispose();
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Whether [modeId] belongs to an account that may pay a card bill.
  static bool _allowedFrom(AppState s, int? modeId) {
    if (modeId == null) return false;
    final a = s.accountOfMode(modeId);
    return a != null && _billFrom.contains(a.type);
  }

  /// Whether [modeId] belongs to a cash or bank account (where income can go).
  static bool _incomeAllowed(AppState s, int? modeId) {
    if (modeId == null) return false;
    final a = s.accountOfMode(modeId);
    return a != null && _incomeTo.contains(a.type);
  }

  // ---- date & time ----
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t != null) {
      setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
    }
  }

  // ---- amount ----
  Future<void> _openCalculator() async {
    FocusScope.of(context).unfocus();
    final v = await showCalculator(context, initial: _amount.text.trim());
    if (v != null && mounted) {
      setState(() {
        _billError = null;
        _amount.text = v <= 0 ? '' : _plain(v);
      });
    }
  }

  void _fill(double v) {
    if (v <= 0) return;
    setState(() {
      _billError = null;
      _amount.text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    });
  }

  /// What can still be paid towards [card]; an edited payment counts as unpaid.
  double owedOn(Account card) {
    final s = context.read<AppState>();
    final old = widget.existingPayment;
    return s.outstanding(card) + (old != null && old.cardId == card.id ? old.amount : 0);
  }

  // ---- pickers ----
  Future<void> _pickCategory() async {
    FocusScope.of(context).unfocus();
    final s = context.read<AppState>();
    final id = await showPickerSheet(
      context,
      title: 'Select Category',
      selectedId: _categoryId,
      items: [
        for (final c in s.categories) PickerItem(c.id!, c.name, c.icon, color: Color(c.color)),
      ],
      onEdit: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ManageScreen(categories: true))),
    );
    if (id != null) setState(() => _categoryId = id);
  }

  Future<void> _pickAccount() async {
    FocusScope.of(context).unfocus();
    final id = await pickAccountMode(context, modeId: _modeId);
    if (id != null) setState(() => _modeId = id);
  }

  Future<void> _pickFrom() async {
    FocusScope.of(context).unfocus();
    final id = await pickAccountMode(
        context, modeId: _fromId, title: 'Paid from', allowed: _billFrom);
    if (id != null) setState(() => _fromId = id);
  }

  Future<void> _pickCard() async {
    FocusScope.of(context).unfocus();
    final s = context.read<AppState>();
    final id = await showPickerSheet(
      context,
      title: 'Select Credit Card',
      selectedId: _cardId,
      items: [
        for (final a in s.creditCards)
          PickerItem(a.id!, a.name, s.modesOf(a.id!).firstOrNull?.icon ?? 0,
              subtitle: '${s.money(s.outstanding(a))} due'),
      ],
      onEdit: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
    );
    if (id != null) {
      setState(() {
        _cardId = id;
        _billError = null;
      });
    }
  }

  Future<void> _pickIncomeCategory() async {
    FocusScope.of(context).unfocus();
    final s = context.read<AppState>();
    final id = await showPickerSheet(
      context,
      title: 'Select Category',
      selectedId: _incCategoryId,
      items: [
        for (final c in s.incomeCategories)
          PickerItem(c.id!, c.name, c.icon, color: Color(c.color)),
      ],
      onEdit: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ManageScreen(categories: true, income: true))),
    );
    if (id != null) setState(() => _incCategoryId = id);
  }

  Future<void> _pickIncomeAccount() async {
    FocusScope.of(context).unfocus();
    final id = await pickAccountMode(context,
        modeId: _incModeId, title: 'Receive in', allowed: _incomeTo);
    if (id != null) setState(() => _incModeId = id);
  }

  // ---- split payment ----
  double get _total => double.tryParse(_amount.text.trim()) ?? 0;
  double get _assigned =>
      _legs.fold(0.0, (a, l) => a + (double.tryParse(l.amount.text.trim()) ?? 0));

  void _startSplit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _split = true;
      _legs
        ..clear()
        ..add(_Leg(
            modeId: _modeId,
            text: _total > 0 ? _plain(_total) : '',
            id: widget.existing?.splitGroup == null ? widget.existing?.id : null))
        ..add(_Leg());
    });
  }

  void _endSplit() {
    setState(() {
      _modeId = _legs.firstOrNull?.modeId ?? _modeId;
      for (final l in _legs) {
        l.amount.dispose();
      }
      _legs.clear();
      _split = false;
    });
  }

  void _addLeg() {
    final left = _total - _assigned;
    setState(() => _legs.add(_Leg(text: left > 0.004 ? _plain(left) : '')));
  }

  void _removeLeg(int i) {
    final l = _legs.removeAt(i);
    l.amount.dispose();
    setState(() {});
  }

  Future<void> _pickLegAccount(int i) async {
    FocusScope.of(context).unfocus();
    final id = await pickAccountMode(context, modeId: _legs[i].modeId);
    if (id != null) setState(() => _legs[i].modeId = id);
  }

  Future<void> _saveSplit() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _categoryId == null) return;
    final s = context.read<AppState>();
    final amounts = [for (final l in _legs) double.tryParse(l.amount.text.trim()) ?? 0];
    if (_legs.any((l) => l.modeId == null) || amounts.any((a) => a <= 0)) {
      _toast('Pick an account and an amount for every row');
      return;
    }
    if ((_assigned - _total).abs() > 0.011) {
      _toast('The rows add up to ${s.money(_assigned)}, not ${s.money(_total)}');
      return;
    }
    final nav = Navigator.of(context);
    final old = widget.existing?.attachment;
    await s.saveSplitExpense(
      existing: widget.existing == null ? const [] : s.legsOf(widget.existing!),
      legs: [for (var i = 0; i < _legs.length; i++) (modeId: _legs[i].modeId!, amount: amounts[i])],
      note: _note.text.trim(),
      categoryId: _categoryId!,
      date: _date,
      attachment: _attachment,
    );
    _saved = true;
    if (old != null && old != _attachment) await AttachmentService.delete(old);
    nav.pop();
  }

  Widget _splitSection(AppState s, ColorScheme cs) {
    final left = _total - _assigned;
    final matches = _total > 0 && left.abs() < 0.011;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));
    final color = matches ? Colors.green.shade400 : (left < 0 ? cs.error : Colors.orange.shade400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Paid with',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              TextButton(onPressed: _endSplit, child: const Text('Use one account')),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _legs.length; i++) _legRow(s, cs, i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addLeg,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add another account'),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: .4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Assigned ${m(_assigned)} of ${m(_total)}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                Text(
                    matches
                        ? 'Matches'
                        : left > 0
                            ? '${m(left)} left'
                            : 'Over by ${m(-left)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
          if (left > 0.011 && _legs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ActionChip(
                avatar: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18),
                label: Text('Put ${m(left)} on the last account'),
                onPressed: () {
                  final last = _legs.last;
                  final cur = double.tryParse(last.amount.text.trim()) ?? 0;
                  setState(() => last.amount.text = _plain(cur + left));
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _legRow(AppState s, ColorScheme cs, int i) {
    final leg = _legs[i];
    final mode = leg.modeId == null ? null : s.paymentMode(leg.modeId!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _pickLegAccount(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    mode == null
                        ? Icon(Icons.account_balance_wallet_rounded,
                            size: 24, color: cs.onSurfaceVariant)
                        : AppIcon(mode.icon, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(mode == null ? 'Select account' : s.paymentLabel(mode.id!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              color: mode == null ? cs.onSurfaceVariant : cs.onSurface)),
                    ),
                    Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: TextField(
              controller: leg.amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0',
                prefixText: '${s.currency} ',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              ),
            ),
          ),
          if (_legs.length > 2)
            IconButton(
              tooltip: 'Remove',
              onPressed: () => _removeLeg(i),
              icon: Icon(Icons.close_rounded, color: cs.error),
            ),
        ],
      ),
    );
  }

  // ---- attachment ----
  Future<void> _addAttachment() async {
    if (!AttachmentService.supported) {
      _toast('Attachments are not available in the browser');
      return;
    }
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Take a photo'),
                subtitle: const Text('Open the camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from gallery'),
                subtitle: const Text('Upload an existing image'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final name = await AttachmentService.pick(source);
      if (name == null || !mounted) return;
      // A photo added earlier in this session and then replaced is dropped now.
      if (_pickedThisSession != null) await AttachmentService.delete(_pickedThisSession);
      setState(() {
        _attachment = name;
        _pickedThisSession = name;
      });
    } on PlatformException catch (e) {
      _toast(e.code.contains('denied')
          ? 'Permission denied. Allow camera or photo access in Settings.'
          : 'Could not get the image');
    }
  }

  void _removeAttachment() {
    if (_attachment == _pickedThisSession) {
      AttachmentService.delete(_pickedThisSession);
      _pickedThisSession = null;
    }
    setState(() => _attachment = null);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  // ---- save / delete ----
  Future<void> _saveBill() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _cardId == null || _fromId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final card = s.accounts.where((a) => a.id == _cardId).firstOrNull;
    if (card == null) return;
    final amount = double.parse(_amount.text.trim());
    final old = widget.existingPayment;
    // Editing: the amount already paid counts as still owed.
    final owed = s.outstanding(card) + (old != null && old.cardId == card.id ? old.amount : 0);
    if (amount > owed + 0.004) {
      setState(() => _billError = 'Only ${s.money(owed)} is outstanding on ${card.name}');
      return;
    }
    await s.saveCardPayment(CardPayment(
      id: old?.id,
      cardId: card.id!,
      modeId: _fromId!,
      amount: amount,
      note: _note.text.trim(),
      date: _date,
    ));
    nav.pop();
  }

  Future<void> _saveIncome() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _incCategoryId == null || _incModeId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    await s.saveIncome(Income(
      id: widget.existingIncome?.id,
      amount: double.parse(_amount.text.trim()),
      note: _note.text.trim(),
      categoryId: _incCategoryId!,
      paymentModeId: _incModeId!,
      date: _date,
    ));
    nav.pop();
  }

  Future<void> _save() async {
    if (_income) return _saveIncome();
    if (_bill) return _saveBill();
    if (_split) return _saveSplit();
    setState(() => _submitted = true);
    if (!_form.currentState!.validate() || _categoryId == null || _modeId == null) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final old = widget.existing?.attachment;
    await s.saveExpense(Expense(
      id: widget.existing?.id,
      amount: double.parse(_amount.text.trim()),
      note: _note.text.trim(),
      categoryId: _categoryId!,
      paymentModeId: _modeId!,
      date: _date,
      attachment: _attachment,
      emiId: widget.existing?.emiId,
    ));
    _saved = true;
    // An expense that was split and is now paid from one account loses its other legs.
    final wasSplit = widget.existing?.splitGroup;
    if (wasSplit != null) await s.deleteSplit(wasSplit);
    // The old photo is no longer referenced once it is replaced or removed.
    if (old != null && old != _attachment) await AttachmentService.delete(old);
    nav.pop();
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final e = widget.existing;
    final p = widget.existingPayment;
    final inc = widget.existingIncome;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p != null
            ? 'Delete this payment?'
            : inc != null
                ? 'Delete this income?'
                : 'Delete this expense?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    if (p != null) {
      await s.deleteCardPayment(p.id!);
    } else if (inc != null) {
      await s.deleteIncome(inc.id!);
    } else if (e != null) {
      if (e.splitGroup != null) {
        await s.deleteSplit(e.splitGroup!);
      } else {
        await s.deleteExpense(e.id!);
      }
      await AttachmentService.delete(e.attachment);
    }
    nav.pop();
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final editing = widget.existing != null ||
        widget.existingPayment != null ||
        widget.existingIncome != null;
    final card = s.accounts.where((a) => a.id == _cardId && a.type == AccountType.credit).firstOrNull;
    // A selected item may have vanished (e.g. deleted elsewhere).
    if (_categoryId != null && !s.categories.any((c) => c.id == _categoryId)) _categoryId = null;
    if (_modeId != null && !s.paymentModes.any((m) => m.id == _modeId)) _modeId = null;
    if (_fromId != null && !_allowedFrom(s, _fromId)) _fromId = null;
    if (_cardId != null && !s.creditCards.any((a) => a.id == _cardId)) _cardId = null;
    if (_incCategoryId != null && !s.incomeCategories.any((c) => c.id == _incCategoryId)) {
      _incCategoryId = null;
    }
    if (_incModeId != null && !_incomeAllowed(s, _incModeId)) _incModeId = null;

    final cat = _categoryId == null ? null : s.category(_categoryId!);
    final mode = _modeId == null ? null : s.paymentMode(_modeId!);
    final from = _fromId == null ? null : s.paymentMode(_fromId!);
    final incCat = _incCategoryId == null ? null : s.category(_incCategoryId!);
    final incMode = _incModeId == null ? null : s.paymentMode(_incModeId!);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: Text(_income
            ? (editing ? 'Edit income' : 'New income')
            : _bill
                ? (editing ? 'Edit card payment' : 'Pay credit card bill')
                : (editing ? 'Edit expense' : 'New expense')),
        actions: [
          if (editing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: IconButton.filledTonal(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_rounded),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        tooltip: 'Save',
        backgroundColor: cs.onSurface,
        foregroundColor: cs.surface,
        shape: const CircleBorder(),
        child: const Icon(Icons.save_rounded),
      ),
      body: Form(
        key: _form,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            if (!editing) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 0, label: Text('Expense')),
                    const ButtonSegment(value: 1, label: Text('Income')),
                    if (s.creditCards.isNotEmpty)
                      const ButtonSegment(value: 2, label: Text('Card bill')),
                  ],
                  selected: {_income ? 1 : (_bill ? 2 : 0)},
                  onSelectionChanged: (v) => setState(() {
                    _income = v.first == 1;
                    _bill = v.first == 2;
                    _billError = null;
                  }),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Date & time
            Row(
              children: [
                Expanded(
                  child: _tap(
                    onTap: _pickDate,
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: 14),
                        Text(DateFormat('d MMM y').format(_date),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _tap(
                    onTap: _pickTime,
                    child: Row(
                      children: [
                        Icon(Icons.schedule_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: 14),
                        Text(DateFormat('hh:mm a').format(_date),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Amount + calculator
            _row(
              leading: Text(s.currency.trim(),
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              label: 'Amount',
              value: TextFormField(
                controller: _amount,
                autofocus: !editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}')),
                ],
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: '0',
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Enter an amount greater than 0';
                  return null;
                },
              ),
              trailing: IconButton.filledTonal(
                tooltip: 'Calculator',
                iconSize: 26,
                style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                onPressed: _openCalculator,
                icon: const Icon(Icons.calculate_rounded),
              ),
            ),
            if (_income) ...[
              _row(
                leading: incCat == null
                    ? Icon(Icons.category_rounded, size: 28, color: cs.onSurfaceVariant)
                    : AppIcon(incCat.icon, size: 30, color: Color(incCat.color)),
                label: 'Category',
                value: _choice(incCat?.name, 'Select category'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickIncomeCategory,
              ),
              if (_submitted && _incCategoryId == null) _error('Pick a category'),
              _row(
                leading: incMode == null
                    ? Icon(Icons.account_balance_wallet_rounded,
                        size: 28, color: cs.onSurfaceVariant)
                    : AppIcon(incMode.icon, size: 30),
                label: 'Receive in',
                value: _choice(incMode == null ? null : s.paymentLabel(incMode.id!),
                    'Select cash or bank account'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickIncomeAccount,
              ),
              if (_submitted && _incModeId == null)
                _error('Pick the cash or bank account that received it'),
            ] else if (!_bill) ...[
              // Category
              _row(
                leading: cat == null
                    ? Icon(Icons.category_rounded, size: 28, color: cs.onSurfaceVariant)
                    : AppIcon(cat.icon, size: 30, color: Color(cat.color)),
                label: 'Category',
                value: _choice(cat?.name, 'Select category'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickCategory,
              ),
              if (_submitted && _categoryId == null) _error('Pick a category'),
              // Account: one, or split across several
              if (!_split) ...[
                _row(
                  leading: mode == null
                      ? Icon(Icons.account_balance_wallet_rounded,
                          size: 28, color: cs.onSurfaceVariant)
                      : AppIcon(mode.icon, size: 30),
                  label: 'Account',
                  value: _choice(mode == null ? null : s.paymentLabel(mode.id!), 'Select account'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickAccount,
                ),
                if (_submitted && _modeId == null) _error('Pick an account'),
                // An EMI entry belongs to its card, so it is not split.
                if (widget.existing?.emiId == null)
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _startSplit,
                        icon: const Icon(Icons.call_split_rounded, size: 18),
                        label: const Text('Split across accounts'),
                      ),
                    ),
                  ),
              ] else
                _splitSection(s, cs),
            ] else ...[
              // Credit card being paid
              _row(
                leading: card == null
                    ? Icon(Icons.credit_card_rounded, size: 28, color: cs.onSurfaceVariant)
                    : AppIcon(s.modesOf(card.id!).firstOrNull?.icon ?? 0, size: 30),
                label: 'Credit card',
                value: _choice(
                    card == null ? null : '${card.name} · ${s.money(s.outstanding(card))} due',
                    'Select credit card'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickCard,
              ),
              if (_submitted && _cardId == null) _error('Pick a credit card'),
              if (card != null)
                Padding(
                  padding: const EdgeInsets.only(left: 54, bottom: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (s.cardBill(card).due > 0.004)
                        ActionChip(
                          avatar: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: Text('Bill due ${s.money(s.cardBill(card).due)}'),
                          onPressed: () => _fill(s.cardBill(card).due),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Full outstanding'),
                        onPressed: () => _fill(owedOn(card)),
                      ),
                    ],
                  ),
                ),
              if (_billError != null) _error(_billError!),
              // Paid from
              _row(
                leading: from == null
                    ? Icon(Icons.account_balance_wallet_rounded,
                        size: 28, color: cs.onSurfaceVariant)
                    : AppIcon(from.icon, size: 30),
                label: 'Paid from',
                value: _choice(
                    from == null ? null : s.paymentLabel(from.id!), 'Select where it came from'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickFrom,
              ),
              if (_submitted && _fromId == null) _error('Pick where the money came from'),
            ],
            const SizedBox(height: 24),
            const Text('Other details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            // Note
            _row(
              leading: Icon(Icons.notes_rounded, size: 26, color: cs.onSurfaceVariant),
              value: TextFormField(
                controller: _note,
                maxLines: 4,
                minLines: 1,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: _bill ? 'Write a note (e.g. Full payment)' : 'Write a note',
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            // Attachment (receipts belong to expenses, not card payments)
            if (!_bill && !_income) _attachmentRow(cs),
          ],
        ),
      ),
    );
  }

  Widget _attachmentRow(ColorScheme cs) {
    final icon = Icon(Icons.attach_file_rounded, size: 26, color: cs.onSurfaceVariant);
    if (_attachment == null) {
      return _row(
        leading: icon,
        value: Text('Add attachment',
            style: TextStyle(fontSize: 17, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _addAttachment,
      );
    }
    return _row(
      leading: icon,
      value: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => AttachmentViewer(name: _attachment!))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                AttachmentService.fileFor(_attachment!),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                cacheWidth: 220,
                errorBuilder: (_, _, _) => Container(
                  width: 72,
                  height: 72,
                  color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_rounded),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Tap the image to view',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          IconButton(
            tooltip: 'Replace',
            onPressed: _addAttachment,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: _removeAttachment,
            icon: Icon(Icons.close_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }

  Widget _choice(String? text, String placeholder) {
    final cs = Theme.of(context).colorScheme;
    return Text(text ?? placeholder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 19, color: text == null ? cs.onSurfaceVariant : cs.onSurface));
  }

  Widget _tap({required VoidCallback onTap, required Widget child}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: child),
      );

  /// A form line: fixed-width leading icon, optional small label above the
  /// value, optional trailing widget.
  Widget _row({
    required Widget leading,
    required Widget value,
    String? label,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: leading)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Text(label, style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
                  if (label != null) const SizedBox(height: 4),
                  value,
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _error(String t) => Padding(
        padding: const EdgeInsets.only(left: 54, bottom: 4),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

/// One account's share of a payment split across several accounts.
class _Leg {
  int? modeId;
  final TextEditingController amount;

  /// The saved expense this leg edits, when there is one.
  final int? id;
  _Leg({this.modeId, String text = '', this.id}) : amount = TextEditingController(text: text);
}
