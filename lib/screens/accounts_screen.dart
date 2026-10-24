import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import 'add_expense_screen.dart';
import '../widgets/app_icon.dart';
import '../widgets/confirm_identity.dart';

/// Bottom-bar tab listing every account (cash, banks, wallets, credit cards)
/// with the balances worked out from recorded expenses.
class AccountsScreen extends StatefulWidget {
  /// Whether the balances are showing. As a bottom-bar tab the bar's eye button flips it;
  /// opened on its own, the screen keeps its own and shows an eye in its top bar.
  final ValueNotifier<bool>? balanceVisible;
  const AccountsScreen({super.key, this.balanceVisible});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

/// Shows or hides the balances. Showing them needs the PIN or biometrics every time.
Future<void> toggleBalances(BuildContext context, ValueNotifier<bool> visible) async {
  if (visible.value) {
    visible.value = false;
    return;
  }
  final ok = await confirmIdentity(context);
  if (!context.mounted) return;
  if (ok) {
    visible.value = true;
  } else {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Couldn’t confirm it’s you')));
  }
}

class _AccountsScreenState extends State<AccountsScreen> with WidgetsBindingObserver {
  late final ValueNotifier<bool> _visible = widget.balanceVisible ?? ValueNotifier<bool>(false);
  bool get _standalone => widget.balanceVisible == null;
  bool get _show => _visible.value;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible.addListener(_rebuild);
  }

  @override
  void dispose() {
    _visible.removeListener(_rebuild);
    if (_standalone) _visible.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app hides the balances again.
    if (state == AppLifecycleState.paused) _visible.value = false;
  }

  /// Wallets sit right below Cash.
  static const _order = [
    AccountType.cash,
    AccountType.wallet,
    AccountType.bank,
    AccountType.credit,
  ];

  static const _typeIcon = {
    AccountType.cash: (Icons.payments_rounded, Color(0xFF4CAF50)),
    AccountType.bank: (Icons.account_balance_rounded, Color(0xFF42A5F5)),
    AccountType.wallet: (Icons.account_balance_wallet_rounded, Color(0xFFFFA726)),
    AccountType.credit: (Icons.credit_card_rounded, Color(0xFFAB47BC)),
  };

  void _info() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('About balances'),
          content: const Text(
              'Balances are worked out from the expenses you record against each '
              'account’s payment modes, starting from the amount you entered. '
              'They can differ from your real balance.\n\n'
              'Available Credit is the unused limit across your credit cards.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    String amount(double v) => _show ? s.money(v) : '••••';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const Flexible(child: Text('All Accounts', overflow: TextOverflow.ellipsis)),
            IconButton(
              onPressed: _info,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.info_outline_rounded, size: 20, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_standalone)
            IconButton(
              tooltip: _show ? 'Hide balances' : 'Show balances',
              onPressed: () => toggleBalances(context, _visible),
              icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => showAccountSheet(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                shape: const StadiumBorder(),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)),
                backgroundColor: cs.surfaceContainer,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Transactions based balance, actual may vary.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _summary(context, 'Available Balance', amount(s.availableBalance),
                      Colors.green.shade400)),
              const SizedBox(width: 12),
              Expanded(
                  child: _summary(context, 'Available Credit', amount(s.availableCredit),
                      Colors.lightBlue.shade300)),
            ],
          ),
          ..._reminders(context, s, amount),
          for (final type in _order)
            if (s.accounts.any((a) => a.type == type)) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(_typeIcon[type]!.$1, color: _typeIcon[type]!.$2, size: 26),
                  const SizedBox(width: 10),
                  Text(type.plural,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              for (final a in s.accounts.where((a) => a.type == type))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _tile(context, s, a, amount),
                ),
            ],
        ],
      ),
    );
  }

  List<Widget> _reminders(BuildContext context, AppState s, String Function(double) amount) {
    final cs = Theme.of(context).colorScheme;
    final bills = s.cardBills;
    // Billed and unpaid first; then cards whose spending is not billed yet.
    final due = bills.where((b) => b.due > 0.004).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final coming = bills.where((b) => b.due <= 0.004 && b.unbilled > 0.004).toList()
      ..sort((a, b) => a.nextStatement.compareTo(b.nextStatement));
    if (due.isEmpty && coming.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: cs.primary, size: 24),
          const SizedBox(width: 10),
          const Text('Bill reminders',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 12),
      for (final b in due)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _reminder(context, b, amount),
        ),
      for (final b in coming)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _reminder(context, b, amount, generating: true),
        ),
    ];
  }

  /// A bill that is due, or (when [generating]) spending that has not been
  /// billed yet and will come on the next statement.
  Widget _reminder(BuildContext context, CardBill b, String Function(double) amount,
      {bool generating = false}) {
    final cs = Theme.of(context).colorScheme;
    final days = b.daysToDue();
    final toStatement = b.nextStatement.difference(dayOnly(DateTime.now())).inDays;
    final (label, color) = generating
        ? (
            toStatement <= 0
                ? 'Bill generates today'
                : toStatement == 1
                    ? 'Bill generates tomorrow'
                    : 'Bill generates in $toStatement days',
            cs.primary
          )
        : days < 0
            ? ('Overdue by ${-days} ${days == -1 ? 'day' : 'days'}', cs.error)
            : days == 0
                ? ('Due today', Colors.orange.shade400)
                : days == 1
                    ? ('Due tomorrow', Colors.orange.shade400)
                    : ('Due in $days days', days <= 7 ? Colors.orange.shade400 : cs.primary);
    final detail = generating
        ? '${amount(b.unbilled)} spent · bill on ${DateFormat('d MMM').format(b.nextStatement)}'
        : '${amount(b.due)} bill · due ${DateFormat('d MMM').format(b.dueDate)}';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: color.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          children: [
            IconTile(b.card.id == null ? 15 : (_firstModeIcon(context, b.card.id!)), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.card.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(detail, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (!generating)
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 44), shape: const StadiumBorder()),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AddExpenseScreen(billCardId: b.card.id))),
                child: const Text('Pay'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, AppState s, Account a, String Function(double) amount) {
    final cs = Theme.of(context).colorScheme;
    final credit = a.type == AccountType.credit;
    // A mode named like the account adds nothing, so only list different ones.
    final modes = s.modesOf(a.id!).map((m) => m.name).where((n) => n != a.name).join(' · ');
    final detail = credit ? '' : modes;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAccountSheet(context, existing: a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(s.modesOf(a.id!).firstOrNull?.icon ?? 15, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 12),
                  Text(amount(credit ? s.outstanding(a) : s.accountBalance(a)),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
              if (credit) _creditRows(context, s, a, amount),
              // Full width, so nothing is cut off beside the balance.
              if (detail.isNotEmpty && a.type != AccountType.cash)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 6),
                  child: Text(detail,
                      style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant)),
                ),
              if (credit && s.outstanding(a) > 0.004)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(billCardId: a.id))),
                    icon: const Icon(Icons.credit_score_rounded, size: 16),
                    label: const Text('Pay bill'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

int _firstModeIcon(BuildContext context, int accountId) =>
    context.read<AppState>().modesOf(accountId).firstOrNull?.icon ?? 15;

/// A credit card's figures, one per line: the name on the left, the amount on the
/// right, each kind in its own colour.
Widget _creditRows(
    BuildContext context, AppState s, Account a, String Function(double) amount) {
  final cs = Theme.of(context).colorScheme;
  final b = s.cardBill(a);
  final fmt = DateFormat('d MMM');
  final billed = b.due > 0.004;
  final unbilled = b.unbilled > 0.004;
  final overdue = billed && b.daysToDue() < 0;

  final billColor = overdue ? cs.error : Colors.orange.shade400;
  final unbilledColor = Colors.purple.shade300;
  final emiColor = Colors.amber.shade600;
  final availableColor = Colors.lightBlue.shade300;
  final paidColor = Colors.green.shade400;

  Widget row(String label, String value, Color color, {String? hint}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
                  children: [
                    if (hint != null)
                      TextSpan(
                        text: ' · $hint',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: .7)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  return Padding(
    padding: const EdgeInsets.only(top: 8, right: 6),
    child: Column(
      children: [
        if (billed)
          row('Bill', amount(b.due), billColor,
              hint: overdue ? 'overdue · was due ${fmt.format(b.dueDate)}' : 'due ${fmt.format(b.dueDate)}')
        else
          row('Bill', 'Nothing due', paidColor),
        if (unbilled)
          row('Unbilled', amount(b.unbilled), unbilledColor,
              hint: 'bill on ${fmt.format(b.nextStatement)}')
        else
          row('Next bill', fmt.format(b.nextStatement), unbilledColor),
        if (b.emiBlocked > 0.004)
          row('EMI held', amount(b.emiBlocked), emiColor, hint: 'not billed yet'),
        row('Available', amount(s.availableLimit(a)), availableColor,
            hint: s.isShared(a)
                ? 'of ${amount(s.groupLimit(a))} shared with ${s.limitPartners(a).map((c) => c.name).join(', ')}'
                : 'of ${amount(a.totalLimit)} limit'),
      ],
    ),
  );
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Add a new account, or edit [existing].
Future<void> showAccountSheet(BuildContext context, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => _AccountSheet(existing: existing),
  );
}

class _AccountSheet extends StatefulWidget {
  final Account? existing;
  const _AccountSheet({this.existing});

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  static const _creatable = [AccountType.bank, AccountType.wallet, AccountType.credit];

  late AccountType _type = widget.existing?.type ?? AccountType.bank;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _balance = TextEditingController();
  late final _total = TextEditingController();
  late final _unbilled = TextEditingController();
  late int _billing = widget.existing?.billingDay ?? 1;
  late int _due = widget.existing?.dueDay ?? 15;
  final List<ModeDraft> _modes = [];
  final List<int> _removed = [];
  String? _error;

  /// The card whose credit limit this card shares, if any.
  int? _sharedWith;

  /// The icon chosen for this account; null means "the default for its type".
  int? _icon;

  /// A card on a shared limit: it shares one, or other cards share its limit.
  bool get _pooled {
    if (_type != AccountType.credit) return false;
    if (_sharedWith != null) return true;
    final a = _existing;
    return a != null && context.read<AppState>().isShared(a);
  }

  static int _defaultIcon(AccountType t) => switch (t) {
        AccountType.credit => 17,
        AccountType.wallet => 20,
        AccountType.cash => 16,
        AccountType.bank => 18,
      };

  int get _iconIndex => _icon ?? _defaultIcon(_type);

  Account? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final a = _existing;
    if (a != null) {
      final s = context.read<AppState>();
      final bal = s.accountBalance(a);
      _sharedWith = a.sharedWith;
      if (s.isShared(a)) {
        // On a shared limit the figure is what this card owes, not an available limit.
        final owed = s.outstanding(a);
        _balance.text = owed <= 0.004 ? '' : _plain(owed);
      } else {
        _balance.text = (bal == 0 && a.type != AccountType.credit) ? '' : _plain(bal);
      }
      _total.text = a.totalLimit == 0 ? '' : _plain(a.totalLimit);
      if (a.type == AccountType.credit) {
        final ub = s.cardBill(a).unbilled;
        _unbilled.text = ub < 0.005 ? '' : _plain(ub);
      }
      for (final m in s.modesOf(a.id!)) {
        _modes.add(ModeDraft(id: m.id, name: m.name, icon: m.icon));
      }
      _icon = _modes.firstOrNull?.icon;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _total.dispose();
    _unbilled.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final total = double.tryParse(_total.text) ?? 0;
    final unbilled = double.tryParse(_unbilled.text) ?? 0;
    final credit = _type == AccountType.credit;
    // On a shared limit the figure typed is what this card owes; otherwise it is the
    // available limit. Blank means nothing is used either way.
    final typed = double.tryParse(_balance.text);
    final bal = !credit
        ? (typed ?? 0)
        : _pooled
            ? total - (typed ?? 0)
            : (typed ?? total);
    if (name.isEmpty) return setState(() => _error = 'Name is required');
    if (credit && total <= 0) return setState(() => _error = 'Enter the total credit limit');
    if (credit && bal > total) {
      return setState(() => _error = 'Available limit can’t exceed the total limit');
    }
    if (credit && unbilled > total - bal + 0.004) {
      return setState(() => _error = 'Unbilled amount can’t be more than what you owe '
          '(${_plain(total - bal)})');
    }

    final old = _existing;
    // Re-baseline only when the user changed the figure; otherwise keep counting
    // from the original starting point.
    final changed = old == null ||
        (bal - s.accountBalance(old)).abs() > 0.004 ||
        (credit && (unbilled - s.cardBill(old).unbilled).abs() > 0.004);
    final account = Account(
      id: old?.id,
      name: name,
      type: _type,
      balance: changed ? bal : old.balance,
      totalLimit: credit ? total : 0,
      billingDay: _billing,
      dueDay: _due,
      baseExpenseId: changed ? s.lastExpenseId : old.baseExpenseId,
      baseIncomeId: changed ? s.lastIncomeId : old.baseIncomeId,
      basePaymentId: changed ? s.lastPaymentId : old.basePaymentId,
      unbilledBase: changed ? (credit ? unbilled : 0) : old.unbilledBase,
      baseDate: changed ? DateTime.now().millisecondsSinceEpoch : old.baseDate,
      sharedWith: credit ? _sharedWith : null,
    );
    if (credit) await NotificationService.instance.requestPermission();
    if (!credit && _modes.isNotEmpty) {
      _modes[0] = ModeDraft(id: _modes[0].id, name: _modes[0].name, icon: _iconIndex);
    }
    final err = await s.saveAccount(account, _modes, _removed, icon: _iconIndex);
    if (!mounted) return;
    if (err != null) return setState(() => _error = err);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete “${_existing!.name}”?'),
        content: const Text('Transactions made through it stay in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await s.deleteAccount(_existing!.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editMode({int? index}) async {
    final draft = index == null ? null : _modes[index];
    final result = await showDialog<ModeDraft>(
      context: context,
      builder: (_) => _ModeDialog(
        initial: draft,
        taken: [
          for (var i = 0; i < _modes.length; i++)
            if (i != index) _modes[i].name.toLowerCase(),
        ],
      ),
    );
    if (result == null) return;
    setState(() => index == null ? _modes.add(result) : _modes[index] = result);
  }

  void _removeMode(int i) {
    final m = _modes[i];
    if (m.id != null) {
      final used = context.read<AppState>().paymentModeUsage(m.id!);
      if (used > 0) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text('“${m.name}” is used by $used '
                  '${used == 1 ? 'expense' : 'expenses'}. Re-assign or delete those first.')));
        return;
      }
      _removed.add(m.id!);
    }
    setState(() => _modes.removeAt(i));
  }

  Future<void> _pickDay(int current, ValueChanged<int> onPick) async {
    final day = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Day of the month'),
          content: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 31; d++)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx, d),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d == current ? cs.onSurface : null,
                    ),
                    child: Text('$d',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: d == current ? cs.surface : cs.onSurface)),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (day != null) setState(() => onPick(day));
  }

  // ---- building blocks ----

  Widget _row({required Widget icon, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 56, child: Align(alignment: Alignment.centerLeft, child: icon)),
            Expanded(child: child),
          ],
        ),
      );

  InputDecoration _bare(String hint) => InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .5)),
      );

  Widget _moneyField(String label, TextEditingController c, {bool enabled = true}) {
    final cs = Theme.of(context).colorScheme;
    final currency = context.read<AppState>().currency;
    return _row(
      icon: Text(currency, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            enabled: enabled,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
            decoration: _bare('0'),
          ),
        ],
      ),
    );
  }

  /// Choose another card to share its credit limit with.
  Widget _shareSection() {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final me = _existing;
    final hasFollowers = me != null && s.creditCards.any((c) => c.sharedWith == me.id);
    if (hasFollowers) {
      return Padding(
        padding: const EdgeInsets.only(left: 56, bottom: 22),
        child: Text('Other cards share this card’s limit. Change it here and they follow.',
            style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant)),
      );
    }
    final hosts =
        s.creditCards.where((c) => c.id != me?.id && c.sharedWith == null).toList();
    if (hosts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
              width: 56, child: Align(alignment: Alignment.topLeft, child: Icon(Icons.link_rounded, size: 30))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shares its limit with',
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('None'),
                      selected: _sharedWith == null,
                      onSelected: (_) => _setShared(null),
                    ),
                    for (final h in hosts)
                      ChoiceChip(
                        label: Text(h.name),
                        selected: _sharedWith == h.id,
                        onSelected: (_) => _setShared(h.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setShared(int? id) {
    final s = context.read<AppState>();
    setState(() {
      final wasPooled = _pooled;
      final oldTotal = double.tryParse(_total.text) ?? 0;
      final typed = double.tryParse(_balance.text);
      // What the card owes, whichever way the figure was typed.
      final owed = wasPooled ? (typed ?? 0) : oldTotal - (typed ?? oldTotal);

      _sharedWith = id;
      if (id != null) {
        final host = s.accounts.where((a) => a.id == id).firstOrNull;
        if (host != null) _total.text = _plain(host.totalLimit);
      }
      // The figure means "available" on its own and "owed" when shared, so convert
      // it rather than lose what was typed.
      if (wasPooled != _pooled) {
        final newTotal = double.tryParse(_total.text) ?? 0;
        final o = owed < 0 ? 0.0 : owed;
        _balance.text = _pooled
            ? (o <= 0.004 ? '' : _plain(o))
            : _plain(newTotal - o < 0 ? 0 : newTotal - o);
      }
    });
  }

  /// What the app makes of the card figures typed so far: what is owed, how much
  /// of it is billed and when that bill is due.
  Widget _creditSummary() {
    final cs = Theme.of(context).colorScheme;
    final s = context.read<AppState>();
    final total = double.tryParse(_total.text) ?? 0;
    if (total <= 0) return const SizedBox.shrink();
    final typed = double.tryParse(_balance.text);
    final unbilled = double.tryParse(_unbilled.text) ?? 0;
    final owed = (_pooled ? (typed ?? 0) : total - (typed ?? total)).clamp(0.0, total).toDouble();
    // EMI principal held on the card is not billed either.
    final blocked = _existing == null ? 0.0 : s.emiBlockedOn(_existing!);
    final billed = owed - unbilled - blocked < 0 ? 0.0 : owed - unbilled - blocked;

    final today = dayOnly(DateTime.now());
    var start = monthDay(today.year, today.month, _billing);
    if (start.isAfter(today)) start = monthDay(today.year, today.month - 1, _billing);
    final due = billDueDate(start, _due);
    final next = monthDay(start.year, start.month + 1, _billing);
    final overdue = billed > 0.004 && due.isBefore(today);
    final fmt = DateFormat('d MMM');
    final orange = Colors.orange.shade400;
    String m(double v) => s.money(double.parse(v.toStringAsFixed(2)));

    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(left: 56, bottom: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line('You owe now', m(owed)),
          line('Not billed yet · on the ${fmt.format(next)} bill', m(unbilled > owed ? owed : unbilled)),
          if (blocked > 0.004) line('EMI held · not billed yet', m(blocked)),
          line('Already billed · due ${fmt.format(due)}', m(billed),
              color: overdue ? orange : null),
          if (overdue)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'That due date has passed, so it will show as overdue. If this bill is '
                  'already paid, raise the available limit by what you paid.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: orange)),
            ),
          if (_balance.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  _pooled
                      ? 'Left blank, so nothing is owed on this card.'
                      : 'Available limit is blank, so nothing is counted as used.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _dateField(String label, int day, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return _row(
      icon: const Icon(Icons.calendar_month_rounded, size: 30),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(day.toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Text('of every month', style: TextStyle(fontSize: 17, color: cs.onSurface)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTabs() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          for (final t in _creatable)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _type = t;
                  _error = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == _type ? cs.surfaceContainerHighest : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(t.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t == _type ? cs.onSurface : cs.onSurfaceVariant,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linkedModes() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Linked payment modes',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            OutlinedButton.icon(
              onPressed: () => _editMode(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                shape: const StadiumBorder(),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)),
                backgroundColor: cs.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_modes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('UPI, debit card, net banking… Add the ways you pay from this account.',
                style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
          ),
        for (var i = 0; i < _modes.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => _editMode(index: i),
            leading: IconTile(_modes[i].icon, size: 44),
            title: Text(_modes[i].name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            trailing: IconButton(
              icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
              onPressed: () => _removeMode(i),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final credit = _type == AccountType.credit;
    final editing = _existing != null;
    final cash = _type == AccountType.cash;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(editing ? 'Edit account' : 'Add account',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                if (editing && !cash) ...[
                  IconButton.filledTonal(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        backgroundColor: cs.surfaceContainerHighest),
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 26),
                  style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      backgroundColor: cs.surfaceContainerHighest),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (!editing) ...[_typeTabs(), const SizedBox(height: 26)],
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(
                      icon: const Icon(Icons.text_format_rounded, size: 34),
                      child: TextField(
                        controller: _name,
                        enabled: !cash,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 24,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                        decoration: _bare('Name').copyWith(counterText: ''),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: IconField(
                          index: _iconIndex, onPick: (i) => setState(() => _icon = i)),
                    ),
                    if (credit) ...[
                      _shareSection(),
                      _moneyField(_pooled ? 'You owe on this card' : 'Current Available Limit',
                          _balance),
                      _moneyField(
                          _sharedWith != null ? 'Shared Credit Limit' : 'Total Credit Limit', _total,
                          enabled: _sharedWith == null),
                      _moneyField('Unbilled Amount', _unbilled),
                      Padding(
                        padding: const EdgeInsets.only(left: 56, bottom: 22),
                        child: Text(
                            'Part of what you owe that was spent after your last bill date and '
                            'is not billed yet. It will come on your next bill instead of '
                            'showing as due now.',
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      _creditSummary(),
                      _dateField('Billing Cycle Start Date', _billing,
                          () => _pickDay(_billing, (d) => _billing = d)),
                      _dateField('Payment Due Date', _due,
                          () => _pickDay(_due, (d) => _due = d)),
                    ] else ...[
                      _moneyField('Current Balance', _balance),
                      // The account is itself the payment mode. Extra linked modes are
                      // only shown for an account that already has some, so they stay editable.
                      if (_existing != null && _modes.length > 1) ...[
                        const SizedBox(height: 4),
                        _linkedModes(),
                      ],
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 62),
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  backgroundColor: cs.onSurface,
                  foregroundColor: cs.surface,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name + icon for a payment mode linked to an account.
class _ModeDialog extends StatefulWidget {
  final ModeDraft? initial;
  final List<String> taken;
  const _ModeDialog({this.initial, required this.taken});

  @override
  State<_ModeDialog> createState() => _ModeDialogState();
}

class _ModeDialogState extends State<_ModeDialog> {
  static const _suggestions = [('UPI', 19), ('Debit Card', 17), ('Net Banking', 18)];

  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late int _icon = widget.initial?.icon ?? 19;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Name is required');
    if (widget.taken.contains(name.toLowerCase())) {
      return setState(() => _error = 'Already added to this account');
    }
    Navigator.pop(context, ModeDraft(id: widget.initial?.id, name: name, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add payment mode' : 'Edit payment mode'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            if (widget.initial == null)
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, icon) in _suggestions)
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() {
                        _name.text = label;
                        _icon = icon;
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            IconField(index: _icon, onPick: (i) => setState(() => _icon = i)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _save,
          child: Text(widget.initial == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
