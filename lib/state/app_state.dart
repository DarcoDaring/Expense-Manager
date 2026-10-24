import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db.dart';
import '../models.dart';
import '../services/attachment_service.dart';
import '../services/notification_service.dart';

/// One row of a report: a label with its total and share of the whole.
class Slice {
  final int id;
  final String label;
  final double total;
  final int count;
  final Color color;
  final int icon;
  const Slice(this.id, this.label, this.total, this.count, this.color, this.icon);
}

/// What one EMI costs and where it stands, for the EMI screens and analysis.
class EmiInfo {
  final Recurring r;

  /// Paid through a credit card (instalments are billed on its statements).
  final bool card;
  final int total;

  /// Instalments paid; for a card EMI, instalments already billed to the card.
  final int settled;

  /// The amount financed, 0 when not entered (interest is then unknown).
  final double principal;
  final double fee;
  final double interestTotal;
  final double interestPaid;

  /// GST on the interest and on the fee, in total and so far.
  final double gstTotal;
  final double gstPaid;
  final double paid;
  final double payable;
  final DateTime? next;
  final DateTime? end;

  /// Foreclosed (closed early) and the foreclosure charge paid, before GST.
  final bool closed;
  final double closeCharge;

  const EmiInfo({
    required this.r,
    required this.card,
    required this.total,
    required this.settled,
    required this.principal,
    required this.fee,
    required this.interestTotal,
    required this.interestPaid,
    required this.gstTotal,
    required this.gstPaid,
    required this.paid,
    required this.payable,
    required this.next,
    required this.end,
    required this.closed,
    required this.closeCharge,
  });

  bool get known => principal > 0;
  int get left => closed ? 0 : total - settled;
  double get feePaid => settled >= 1 ? fee : 0;

  /// Interest, fee and GST: everything paid above the amount financed.
  double get extraTotal => interestTotal + fee + gstTotal + closeCharge;
  double get extraPaid => interestPaid + feePaid + gstPaid + closeCharge;
  double get extraLeft => extraTotal - extraPaid;
  double get balance => payable - paid < 0.005 ? 0 : payable - paid;
}

class AppState extends ChangeNotifier {
  final _db = AppDb.instance;

  /// Every category; [categories] is the expense ones, [incomeCategories] the income ones.
  List<Category> allCategories = [];
  List<Category> categories = [];
  List<Category> incomeCategories = [];
  List<Income> incomes = [];
  List<PaymentMode> paymentModes = [];
  List<Expense> expenses = [];
  List<Recurring> recurring = [];
  List<Account> accounts = [];
  List<Note> notes = [];
  List<CardPayment> cardPayments = [];
  bool loaded = false;

  String currency = '₹';
  ThemeMode themeMode = ThemeMode.system;

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    currency = _prefs.getString('currency') ?? '₹';
    themeMode = ThemeMode.values[_prefs.getInt('theme') ?? 0];
    await NotificationService.instance.init();
    await AttachmentService.init();
    await reload();
    await syncCardEmis();
    await _reschedule();
    loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    allCategories = await _db.categories();
    categories = allCategories.where((c) => c.kind == 0).toList();
    incomeCategories = allCategories.where((c) => c.kind == 1).toList();
    incomes = await _db.incomes();
    paymentModes = await _db.paymentModes();
    expenses = await _db.expenses();
    recurring = await _db.recurring();
    accounts = await _db.accounts();
    notes = await _db.notes();
    cardPayments = await _db.cardPayments();
    notifyListeners();
  }

  // ---- settings ----
  Future<void> setCurrency(String c) async {
    currency = c;
    await _prefs.setString('currency', c);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt('theme', m.index);
    notifyListeners();
  }

  String money(double v) =>
      '$currency${NumberFormat.decimalPatternDigits(decimalDigits: v == v.roundToDouble() ? 0 : 2).format(v)}';

  // ---- lookups ----
  Category category(int id) => allCategories.firstWhere((c) => c.id == id,
      orElse: () => const Category(name: 'Unknown', icon: 15, color: 0xFF64748B));

  PaymentMode paymentMode(int id) => paymentModes.firstWhere((m) => m.id == id,
      orElse: () => const PaymentMode(name: 'Unknown', icon: 16));

  // ---- writes ----
  Future<void> saveExpense(Expense e) async {
    await _db.saveExpense(e);
    await reload();
    await _reschedule();
  }

  /// The legs of a payment split across accounts, oldest first; just [e] when it
  /// was paid from a single account.
  List<Expense> legsOf(Expense e) {
    final g = e.splitGroup;
    if (g == null) return [e];
    final legs = expenses.where((x) => x.splitGroup == g).toList()
      ..sort((a, b) => a.id!.compareTo(b.id!));
    return legs.isEmpty ? [e] : legs;
  }

  /// Saves an expense paid from several accounts: one entry per account, all with
  /// the same details, so every account's balance and bill stays correct. [existing]
  /// are the legs being edited; surplus ones are removed.
  Future<void> saveSplitExpense({
    required List<Expense> existing,
    required List<({int modeId, double amount})> legs,
    required String note,
    required int categoryId,
    required DateTime date,
    String? attachment,
  }) async {
    final group = existing.firstOrNull?.splitGroup ?? DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < legs.length; i++) {
      await _db.saveExpense(Expense(
        id: i < existing.length ? existing[i].id : null,
        amount: legs[i].amount,
        note: note,
        categoryId: categoryId,
        paymentModeId: legs[i].modeId,
        date: date,
        attachment: i == 0 ? attachment : null,
        splitGroup: group,
      ));
    }
    for (var i = legs.length; i < existing.length; i++) {
      await _db.deleteExpense(existing[i].id!);
    }
    await reload();
    await _reschedule();
  }

  Future<void> deleteSplit(int group) async {
    await _db.deleteExpenseGroup(group);
    await reload();
    await _reschedule();
  }

  Future<void> deleteExpense(int id) async {
    await _db.deleteExpense(id);
    await reload();
    await _reschedule();
  }

  Future<void> saveIncome(Income i) async {
    await _db.saveIncome(i);
    await reload();
  }

  Future<void> deleteIncome(int id) async {
    await _db.deleteIncome(id);
    await reload();
  }

  int get lastIncomeId => incomes.fold(0, (m, i) => i.id! > m ? i.id! : m);

  /// Returns the new/updated id, or null when the name is already taken.
  Future<int?> saveCategory(Category c) async {
    final clash = allCategories.any(
        (x) => x.id != c.id && x.name.toLowerCase() == c.name.trim().toLowerCase());
    if (clash) return null;
    final id = await _db.saveCategory(
        Category(id: c.id, name: c.name.trim(), icon: c.icon, color: c.color, kind: c.kind));
    await reload();
    return id;
  }

  Future<int?> savePaymentMode(PaymentMode m) async {
    final clash = paymentModes.any(
        (x) => x.id != m.id && x.name.toLowerCase() == m.name.trim().toLowerCase());
    if (clash) return null;
    final id = await _db.savePaymentMode(
        PaymentMode(id: m.id, name: m.name.trim(), icon: m.icon, accountId: m.accountId));
    await reload();
    return id;
  }

  int categoryUsage(int id) =>
      expenses.where((e) => e.categoryId == id).length +
      incomes.where((i) => i.categoryId == id).length +
      recurring.where((r) => r.categoryId == id).length;
  int paymentModeUsage(int id) =>
      expenses.where((e) => e.paymentModeId == id).length +
      incomes.where((i) => i.paymentModeId == id).length +
      cardPayments.where((p) => p.modeId == id).length +
      recurring.where((r) => r.paymentModeId == id).length;

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    await reload();
  }

  Future<void> deletePaymentMode(int id) async {
    await _db.deletePaymentMode(id);
    await reload();
  }

  // ---- accounts ----
  int get lastExpenseId => expenses.fold(0, (m, e) => e.id! > m ? e.id! : m);
  int get lastPaymentId => cardPayments.fold(0, (m, p) => p.id! > m ? p.id! : m);

  List<PaymentMode> modesOf(int accountId) =>
      paymentModes.where((m) => m.accountId == accountId).toList();

  /// Current balance (available limit for a credit card): what was set, less
  /// every expense recorded since through one of the account's modes. Card bill
  /// payments raise the card's limit and lower the account they were paid from.
  double accountBalance(Account a) {
    final modeIds = {for (final m in modesOf(a.id!)) m.id};
    // Card EMI entries are reporting-only: the EMI's own hold is applied below.
    final spent = expenses
        .where((e) =>
            e.id! > a.baseExpenseId && e.emiId == null && modeIds.contains(e.paymentModeId))
        .fold(0.0, (sum, e) => sum + e.amount);
    // Money received into a cash / bank account since its figure was set.
    final received = incomes
        .where((i) => i.id! > a.baseIncomeId && modeIds.contains(i.paymentModeId))
        .fold(0.0, (sum, i) => sum + i.amount);
    final emiHeld = a.type == AccountType.credit
        ? emisOf(a).fold(0.0, (sum, r) => sum + emiHold(r))
        : 0.0;
    final paid = cardPayments.where((p) => p.id! > a.basePaymentId);
    final paidIn = paid.where((p) => p.cardId == a.id).fold(0.0, (sum, p) => sum + p.amount);
    final paidOut =
        paid.where((p) => modeIds.contains(p.modeId)).fold(0.0, (sum, p) => sum + p.amount);
    return a.balance - spent + received + paidIn - paidOut - emiHeld;
  }

  /// What is owed on a credit card: its limit less what is still available.
  double outstanding(Account card) => card.totalLimit - accountBalance(card);

  List<Account> get creditCards =>
      accounts.where((a) => a.type == AccountType.credit).toList();

  /// The card's current statement, worked out from its billing and due days:
  /// what is still owed on the bill generated at the start of this cycle is the
  /// outstanding amount less whatever has been spent since.
  CardBill cardBill(Account card, {DateTime? now}) {
    final today = dayOnly(now ?? DateTime.now());
    var start = monthDay(today.year, today.month, card.billingDay);
    if (start.isAfter(today)) start = monthDay(today.year, today.month - 1, card.billingDay);
    final prev = monthDay(start.year, start.month - 1, card.billingDay);
    final next = monthDay(start.year, start.month + 1, card.billingDay);
    final modeIds = {for (final m in modesOf(card.id!)) m.id};

    double spends(DateTime from, DateTime? to) {
      bool inRange(DateTime d) {
        final day = dayOnly(d);
        return !day.isBefore(from) && (to == null || day.isBefore(to));
      }

      // Card EMI entries are billed through the EMI's instalments instead.
      return expenses
              .where((e) =>
                  e.id! > card.baseExpenseId &&
                  e.emiId == null &&
                  modeIds.contains(e.paymentModeId) &&
                  inRange(e.date))
              .fold(0.0, (sum, e) => sum + e.amount) +
          cardPayments
              .where((p) =>
                  p.id! > card.basePaymentId &&
                  modeIds.contains(p.modeId) &&
                  inRange(p.date))
              .fold(0.0, (sum, p) => sum + p.amount);
    }

    // Money already owed when the card was set up but not yet billed belongs to
    // the cycle it was entered in: unbilled now, then part of that cycle's bill.
    final base =
        card.baseDate == 0 ? null : DateTime.fromMillisecondsSinceEpoch(card.baseDate);
    bool baseIn(DateTime from, DateTime to) =>
        base != null && !base.isBefore(from) && base.isBefore(to);
    final unbilled = spends(start, null) + (baseIn(start, next) ? card.unbilledBase : 0);
    // EMI principal held on the limit is not on any statement yet either.
    final blocked = emisOf(card).fold(0.0, (sum, r) => sum + emiBlocked(r));
    final owed = outstanding(card);
    final billed = owed - unbilled - blocked;
    return CardBill(
      card: card,
      statementDate: start,
      dueDate: billDueDate(start, card.dueDay),
      due: billed < 0.005 ? 0 : billed,
      unbilled: unbilled,
      statement: spends(prev, start) +
          (baseIn(prev, start) ? card.unbilledBase : 0) +
          emiBilledOn(card, start),
      nextStatement: next,
      emiBlocked: blocked,
    );
  }

  List<CardBill> get cardBills => [for (final c in creditCards) cardBill(c)];

  Future<void> saveCardPayment(CardPayment p) async {
    await _db.saveCardPayment(p);
    await reload();
    await _reschedule();
  }

  Future<void> deleteCardPayment(int id) async {
    await _db.deleteCardPayment(id);
    await reload();
    await _reschedule();
  }

  double get availableBalance => accounts
      .where((a) => a.type != AccountType.credit)
      .fold(0.0, (sum, a) => sum + accountBalance(a));

  // ---- shared credit limits ----
  // Several cards from one bank can share a single limit while keeping their own
  // statements and due dates. The card that owns the limit is the "host".

  Account limitHost(Account a) => a.sharedWith == null
      ? a
      : (accounts.where((x) => x.id == a.sharedWith).firstOrNull ?? a);

  /// The host plus every card that shares its limit.
  List<Account> limitGroup(Account a) {
    final host = limitHost(a);
    return [
      host,
      ...creditCards.where((c) => c.id != host.id && c.sharedWith == host.id),
    ];
  }

  bool isShared(Account a) => a.type == AccountType.credit && limitGroup(a).length > 1;

  /// The other cards on the same limit.
  List<Account> limitPartners(Account a) =>
      limitGroup(a).where((c) => c.id != a.id).toList();

  double groupLimit(Account a) => limitHost(a).totalLimit;

  /// What the whole group owes, against the one shared limit.
  double groupOwed(Account a) => limitGroup(a).fold(0.0, (sum, c) {
        final o = outstanding(c);
        return sum + (o > 0 ? o : 0);
      });

  /// The limit still free for [a]; for a shared card that is the group's.
  double availableLimit(Account a) => groupLimit(a) - groupOwed(a);

  /// Unused credit across all cards; a shared limit counts once.
  double get availableCredit {
    final seen = <int>{};
    var sum = 0.0;
    for (final c in creditCards) {
      final host = limitHost(c);
      if (seen.add(host.id!)) sum += availableLimit(host);
    }
    return sum;
  }

  /// Saves [a] with its payment modes. [removedModeIds] are deleted. Returns an
  /// error message, or null on success.
  Future<String?> saveAccount(
      Account a, List<ModeDraft> drafts, List<int> removedModeIds,
      {int? icon}) async {
    final name = a.name.trim();
    var modes = drafts;
    if (a.type == AccountType.credit) {
      // A card is its own payment mode.
      final own = a.id == null ? null : modesOf(a.id!).firstOrNull;
      modes = [ModeDraft(id: own?.id, name: name, icon: icon ?? own?.icon ?? 17)];
    } else if (modes.isEmpty) {
      modes = [
        ModeDraft(name: name, icon: icon ?? (a.type == AccountType.wallet ? 20 : 18)),
      ];
    }
    // A mode left behind by a deleted account with the same name is re-used, so
    // the account can be created again and its old history stays together.
    modes = [
      for (final d in modes)
        if (d.id == null)
          ModeDraft(
            id: paymentModes
                .where((m) =>
                    m.accountId == null &&
                    m.name.toLowerCase() == d.name.trim().toLowerCase())
                .firstOrNull
                ?.id,
            name: d.name,
            icon: d.icon,
          )
        else
          d,
    ];
    final keep = {for (final d in modes) d.id};
    final others =
        paymentModes.where((m) => !keep.contains(m.id) && !removedModeIds.contains(m.id));
    for (final d in modes) {
      if (others.any((m) => m.name.toLowerCase() == d.name.trim().toLowerCase())) {
        return 'A payment mode named “${d.name}” already exists';
      }
    }
    // A card on a shared limit always uses its host's limit; what it owes stays put.
    var totalLimit = a.totalLimit;
    var balance = a.balance;
    if (a.type == AccountType.credit && a.sharedWith != null) {
      final host = accounts.where((x) => x.id == a.sharedWith).firstOrNull;
      if (host != null && (host.totalLimit - totalLimit).abs() > 0.004) {
        balance += host.totalLimit - totalLimit;
        totalLimit = host.totalLimit;
      }
    }
    final id = await _db.saveAccount(Account(
      id: a.id,
      name: name,
      type: a.type,
      balance: balance,
      totalLimit: totalLimit,
      billingDay: a.billingDay,
      dueDay: a.dueDay,
      baseExpenseId: a.baseExpenseId,
      basePaymentId: a.basePaymentId,
      baseIncomeId: a.baseIncomeId,
      unbilledBase: a.unbilledBase,
      baseDate: a.baseDate,
      sharedWith: a.sharedWith,
    ));
    // Cards that share this card's limit follow it when it changes.
    if (a.type == AccountType.credit && a.id != null) {
      for (final f in accounts.where((x) => x.sharedWith == a.id)) {
        if ((f.totalLimit - totalLimit).abs() > 0.004) {
          await _db.saveAccount(f.copyWith(
              balance: f.balance + totalLimit - f.totalLimit, totalLimit: totalLimit));
        }
      }
    }
    for (final mid in removedModeIds) {
      await _db.deletePaymentMode(mid);
    }
    for (final d in modes) {
      await _db.savePaymentMode(
          PaymentMode(id: d.id, name: d.name.trim(), icon: d.icon, accountId: id));
    }
    await reload();
    await _reschedule();
    return null;
  }

  Account? accountOfMode(int modeId) {
    final aid = paymentMode(modeId).accountId;
    return aid == null ? null : accounts.where((a) => a.id == aid).firstOrNull;
  }

  /// "HDFC · UPI", or just the name when the mode is the account itself.
  String paymentLabel(int modeId) {
    final m = paymentMode(modeId);
    final a = accountOfMode(modeId);
    if (a == null || a.name.toLowerCase() == m.name.toLowerCase()) return m.name;
    return '${a.name} · ${m.name}';
  }

  Future<void> deleteAccount(int id) async {
    // Modes that no transaction refers to would only clutter the pickers; the
    // others stay so the history keeps its labels.
    for (final m in modesOf(id)) {
      if (paymentModeUsage(m.id!) == 0) await _db.deletePaymentMode(m.id!);
    }
    await _db.deleteAccount(id);
    await reload();
    await _reschedule();
  }

  // ---- credit card EMIs ----
  // An EMI paid through a credit card holds its full amount on the limit from
  // the purchase date. From the first statement after that, one instalment is
  // added to each statement; paying the bill gives that part of the limit back.

  /// An EMI whose amount financed is known and that is paid through a credit card.
  bool isCardEmi(Recurring r) =>
      r.isEmi &&
      r.hasPrincipal &&
      accountOfMode(r.paymentModeId)?.type == AccountType.credit;

  /// The statement on which the first instalment of a purchase made on
  /// [purchase] is billed: the first statement after it.
  DateTime emiFirstStatement(Account card, DateTime purchase) {
    final p = dayOnly(purchase);
    final d = monthDay(p.year, p.month, card.billingDay);
    return d.isAfter(p) ? d : monthDay(p.year, p.month + 1, card.billingDay);
  }

  /// Where the billing starts: the purchase date for a new EMI, but the day it was
  /// entered for one already running, whose earlier instalments are paid and gone.
  DateTime emiAnchor(Recurring r) => r.paidCount > 0 && r.created > 0
      ? dayOnly(DateTime.fromMillisecondsSinceEpoch(r.created))
      : dayOnly(r.startDate);

  /// The statement that carries the initial interest: the first after the purchase.
  DateTime emiInitialDate(Recurring r, Account card) => emiFirstStatement(card, emiAnchor(r));

  /// The statement dates on which the instalments still to be billed fall.
  List<DateTime> emiStatementDates(Recurring r, Account card) {
    final out = <DateTime>[];
    var d = emiFirstStatement(card, emiAnchor(r));
    // Some banks start the EMIs one statement later.
    for (var i = 0; i < r.firstDelay; i++) {
      d = monthDay(d.year, d.month + 1, card.billingDay);
    }
    for (var i = 0; i < r.totalCount - r.paidCount && i < 600; i++) {
      out.add(d);
      d = monthDay(d.year, d.month + 1, card.billingDay);
    }
    // A foreclosed EMI bills nothing after the day it was closed.
    if (r.foreclosed) {
      final closed = dayOnly(r.closedDate);
      return out.where((x) => !x.isAfter(closed)).toList();
    }
    return out;
  }

  int emiBilledCount(Recurring r, {DateTime? now}) {
    final card = accountOfMode(r.paymentModeId);
    if (card == null) return 0;
    final today = dayOnly(now ?? DateTime.now());
    return emiStatementDates(r, card).where((d) => !d.isAfter(today)).length;
  }

  /// Every card EMI paid through [card].
  List<Recurring> emisOf(Account card) => recurring
      .where((r) => isCardEmi(r) && accountOfMode(r.paymentModeId)?.id == card.id)
      .toList();

  /// The EMI principal held on [card] that is not on any statement yet.
  double emiBlockedOn(Account card) =>
      emisOf(card).fold(0.0, (sum, r) => sum + emiBlocked(r));

  /// Principal still held on the limit, not yet on a statement.
  double emiBlocked(Recurring r) {
    if (r.foreclosed) {
      // After foreclosure the principal waits to be billed on the next statement.
      final card = accountOfMode(r.paymentModeId);
      if (card == null) return 0;
      final billedOn = emiFirstStatement(card, r.closedDate);
      return billedOn.isAfter(dayOnly(DateTime.now())) ? r.closePrincipal : 0;
    }
    return r.remainingPrincipalAfter(r.paidCount + emiBilledCount(r));
  }

  /// What is left of the principal to repay: the held amount on a card, otherwise the
  /// schedule's balance (or the remaining instalments when no amount financed is known).
  double emiOutstanding(Recurring r) {
    if (isCardEmi(r)) return emiBlocked(r);
    if (r.hasPrincipal) return r.remainingPrincipalAfter(r.paidCount);
    final left = r.totalCount - r.paidCount;
    return left <= 0 ? 0 : r.amount * left;
  }

  /// What the EMI adds to the card's outstanding, on top of the figures entered.
  ///
  /// A purchase made after those figures were set is added in full: the blocked
  /// principal plus everything put on statements since. An EMI that was already
  /// running is part of the figures (the bank's available limit includes it), so
  /// only what builds up afterwards counts: the interest billed on later statements.
  double emiHold(Recurring r) {
    final card = accountOfMode(r.paymentModeId);
    if (card == null) return 0;
    final today = dayOnly(DateTime.now());
    final dates = emiStatementDates(r, card);
    final k = dates.where((d) => !d.isAfter(today)).length;
    final base = card.baseDate == 0
        ? null
        : dayOnly(DateTime.fromMillisecondsSinceEpoch(card.baseDate));
    final fresh = r.paidCount == 0 && (base == null || !dayOnly(r.startDate).isBefore(base));
    final initDate = emiInitialDate(r, card);
    final initBilled = !initDate.isAfter(today);
    // The foreclosure bill lands on the first statement after the closing date.
    final closeBilled =
        r.foreclosed && !emiFirstStatement(card, r.closedDate).isAfter(today);

    if (fresh) {
      // Blocked principal plus everything billed since: each instalment with the GST
      // on its interest, the fee with its GST on the first, and any initial interest.
      var sum = emiBlocked(r);
      for (var i = 0; i < k; i++) {
        sum += r.billedAmount(r.paidCount + i + 1) + (i == 0 ? r.pendingFeeGross : 0);
      }
      if (initBilled) sum += r.initialGross;
      if (closeBilled) sum += r.closePrincipal + r.closeCharge + r.closeGst;
      return sum;
    }
    var sum = 0.0;
    for (var i = 0; i < k; i++) {
      if (base == null || dates[i].isAfter(base)) {
        final j = r.paidCount + i + 1;
        sum += r.interestOf(j) + r.gstOn(j) + (i == 0 ? r.pendingFeeGross : 0);
      }
    }
    if (initBilled && (base == null || initDate.isAfter(base))) sum += r.initialGross;
    if (closeBilled) sum += r.closeCharge + r.closeGst;
    return sum;
  }

  /// What the EMIs of [card] put on the statement generated on [date].
  double emiBilledOn(Account card, DateTime date) {
    final day = dayOnly(date);
    var sum = 0.0;
    for (final r in emisOf(card)) {
      final i = emiStatementDates(r, card).indexWhere((d) => d == day);
      if (i >= 0) sum += r.billedAmount(r.paidCount + i + 1) + (i == 0 ? r.pendingFeeGross : 0);
      if (emiInitialDate(r, card) == day) sum += r.initialGross;
      if (r.foreclosed && emiFirstStatement(card, r.closedDate) == day) {
        sum += r.closePrincipal + r.closeCharge + r.closeGst;
      }
    }
    return sum;
  }

  bool recurringCompleted(Recurring r) => r.foreclosed ||
      (isCardEmi(r) ? r.totalCount - r.paidCount - emiBilledCount(r) <= 0 : r.completed);

  /// The next date this item is due: a card EMI's next statement, otherwise its due date.
  DateTime emiNextDate(Recurring r) {
    final card = isCardEmi(r) ? accountOfMode(r.paymentModeId) : null;
    if (card == null) return r.nextDue;
    final today = dayOnly(DateTime.now());
    return emiStatementDates(r, card).where((d) => d.isAfter(today)).firstOrNull ?? r.nextDue;
  }

  EmiInfo emiInfo(Recurring r) {
    final card = isCardEmi(r);
    final total = r.totalCount;
    var settled = card ? r.paidCount + emiBilledCount(r) : r.paidCount;
    if (total > 0 && settled > total) settled = total;
    final g = r.gstRate / 100;
    // GST on the interest of the first [m] instalments.
    double gstUpTo(int m) {
      var sum = 0.0;
      for (var j = 1; j <= m && j <= total; j++) {
        sum += r.gstOn(j);
      }
      return sum;
    }

    // Interest in the first [m] instalments of the reducing-balance schedule.
    double interestUpTo(int m) {
      var sum = 0.0;
      for (var j = 1; j <= m && j <= total; j++) {
        sum += r.interestOf(j);
      }
      return sum;
    }

    DateTime? next;
    DateTime? end;
    final acc = card ? accountOfMode(r.paymentModeId) : null;
    if (acc != null) {
      final dates = emiStatementDates(r, acc);
      final today = dayOnly(DateTime.now());
      next = dates.where((d) => d.isAfter(today)).firstOrNull;
      end = dates.isEmpty ? null : dates.last;
    } else if (r.active && !r.completed && total > r.paidCount) {
      next = r.nextDue;
      var d = r.nextDue;
      for (var i = 1; i < total - r.paidCount; i++) {
        d = r.advance(d);
      }
      end = d;
    }
    // Initial interest (card EMIs): charged on the first statement, before any instalment.
    final init = card ? (r.paidCount == 0 ? r.initialInterest : 0.0) : 0.0;
    var initBilled = false;
    if (acc != null && init > 0) {
      initBilled = !emiInitialDate(r, acc).isAfter(dayOnly(DateTime.now()));
    }
    final closed = r.foreclosed;
    final feeIn = closed || settled >= 1 ? r.fee : 0.0;
    final initIn = closed ? init : (initBilled ? init : 0.0);
    final paidSoFar = r.amount * settled +
        gstUpTo(settled) +
        feeIn * (1 + g) +
        initIn * (1 + g) +
        (closed ? r.closePrincipal + r.closeCharge + r.closeGst : 0);
    return EmiInfo(
      r: r,
      card: card,
      total: total,
      settled: settled,
      principal: r.hasPrincipal ? r.principal : 0,
      fee: r.fee,
      interestTotal: (closed ? interestUpTo(settled) : interestUpTo(total)) + init,
      interestPaid: interestUpTo(settled) + initIn,
      gstTotal: (closed ? gstUpTo(settled) + r.closeGst : gstUpTo(total)) +
          r.fee * g +
          init * g,
      gstPaid: gstUpTo(settled) + feeIn * g + initIn * g + (closed ? r.closeGst : 0),
      paid: paidSoFar,
      payable: closed
          ? paidSoFar
          : r.amount * total + gstUpTo(total) + r.fee * (1 + g) + init * (1 + g),
      next: closed ? null : next,
      end: closed ? r.closedDate : end,
      closed: closed,
      closeCharge: closed ? r.closeCharge : 0,
    );
  }

  /// Closes an EMI early. The principal paid, the charge and its GST are recorded as
  /// one expense (on the closing date); on a card they are billed on the next
  /// statement and the instalments after the closing date stop.
  Future<void> foreclose(
    Recurring r, {
    required DateTime date,
    required double principal,
    required double charge,
    required double gstPercent,
    int? payFromModeId,
  }) async {
    final day = dayOnly(date);
    final now = DateTime.now();
    final gst = charge * gstPercent / 100;
    final card = isCardEmi(r);
    if ((r.closureExpenseId ?? 0) > 0) await _db.deleteExpense(r.closureExpenseId!);
    // A card EMI's instalments are recorded again, up to the closing date only.
    if (card) await _db.deleteEmiExpenses(r.id!);
    final id = await _db.saveExpense(Expense(
      amount: principal + charge + gst,
      note: [
        r.name,
        'EMI foreclosure',
        if (charge > 0.004) 'incl. charge${gst > 0.004 ? ' & GST' : ''}',
      ].where((t) => t.isNotEmpty).join(' – '),
      categoryId: r.categoryId,
      paymentModeId: card ? r.paymentModeId : (payFromModeId ?? r.paymentModeId),
      date: day == dayOnly(now) ? now : day.add(const Duration(hours: 12)),
      emiId: card ? r.id : null,
    ));
    await _db.saveRecurring(r.copyWith(
      active: false,
      postedCount: card ? 0 : null,
      closedOn: day.millisecondsSinceEpoch,
      closePrincipal: principal,
      closeCharge: charge,
      closeGst: gst,
      closureExpenseId: id,
    ));
    await reload();
    await syncCardEmis();
    await _reschedule();
  }

  /// Undoes a foreclosure: the EMI runs again and what it recorded is removed.
  Future<void> reopenEmi(Recurring r) async {
    final card = isCardEmi(r);
    if ((r.closureExpenseId ?? 0) > 0) await _db.deleteExpense(r.closureExpenseId!);
    if (card) await _db.deleteEmiExpenses(r.id!);
    await _db.saveRecurring(r.copyWith(
      active: true,
      postedCount: card ? 0 : null,
      closedOn: 0,
      closePrincipal: 0,
      closeCharge: 0,
      closeGst: 0,
      closureExpenseId: 0,
    ));
    await reload();
    await syncCardEmis();
    await _reschedule();
  }

  /// What a card EMI puts on the card, in the order it is billed: any initial
  /// interest, then each instalment (the first with the fee), each with the
  /// statement date it falls on and the note for its expense.
  List<({DateTime date, double amount, String note})> emiEvents(Recurring r, Account card) {
    final out = <({DateTime date, double amount, String note})>[];
    if (r.initialGross > 0.004) {
      out.add((
        date: emiInitialDate(r, card),
        amount: r.initialGross,
        note: 'EMI initial interest${r.gstRate > 0 ? ' incl. GST' : ''}',
      ));
    }
    final dates = emiStatementDates(r, card);
    for (var i = 0; i < dates.length; i++) {
      final fee = i == 0 ? r.pendingFeeGross : 0.0;
      final extras = [
        if (fee > 0.004) 'fee',
        if (r.gstRate > 0 && r.hasPrincipal) 'GST',
      ];
      out.add((
        date: dates[i],
        amount: r.billedAmount(r.paidCount + i + 1) + fee,
        note: 'EMI ${r.paidCount + i + 1}/${r.totalCount}'
            '${extras.isEmpty ? '' : ' incl. ${extras.join(' & ')}'}',
      ));
    }
    return out;
  }

  /// Records everything a card EMI has billed so far as an expense, dated on its
  /// statement. The purchase is not recorded separately, so the spending shows up
  /// month by month as it is charged. Safe to call often.
  Future<void> syncCardEmis() async {
    var changed = false;
    final today = dayOnly(DateTime.now());
    for (final r in List.of(recurring)) {
      if (!isCardEmi(r) || r.id == null) continue;
      final card = accountOfMode(r.paymentModeId);
      if (card == null) continue;
      final events = emiEvents(r, card);
      final billed = events.where((e) => !e.date.isAfter(today)).length;
      if (billed <= r.postedCount) continue;
      for (var j = r.postedCount; j < billed; j++) {
        final e = events[j];
        await _db.saveExpense(Expense(
          amount: e.amount,
          note: [r.name, e.note].where((t) => t.isNotEmpty).join(' – '),
          categoryId: r.categoryId,
          paymentModeId: r.paymentModeId,
          date: e.date,
          emiId: r.id,
        ));
      }
      await _db.saveRecurring(r.copyWith(postedCount: billed));
      changed = true;
    }
    if (changed) {
      await reload();
      await _reschedule();
    }
  }

  /// A card EMI used to record its whole purchase as one expense. It no longer does,
  /// so an old one is removed.
  Future<void> _syncPurchase(Recurring r) async {
    if ((r.purchaseExpenseId ?? 0) > 0) {
      await _db.deleteExpense(r.purchaseExpenseId!);
      await _db.saveRecurring(r.copyWith(purchaseExpenseId: 0));
    }
  }

  // ---- recurring ----
  String recurringTitle(Recurring r) =>
      r.name.isNotEmpty ? r.name : category(r.categoryId).name;

  /// Whether two versions of an EMI bill the same amounts on the same dates.
  bool _sameBilling(Recurring a, Recurring b) =>
      a.name == b.name &&
      a.categoryId == b.categoryId &&
      a.paymentModeId == b.paymentModeId &&
      a.amount == b.amount &&
      a.principal == b.principal &&
      a.fee == b.fee &&
      a.gstRate == b.gstRate &&
      a.totalCount == b.totalCount &&
      a.paidCount == b.paidCount &&
      a.firstDelay == b.firstDelay &&
      a.initialInterest == b.initialInterest &&
      dayOnly(a.startDate) == dayOnly(b.startDate);

  Future<void> saveRecurring(Recurring r) async {
    var toSave = r;
    final before = r.id == null ? null : recurring.where((x) => x.id == r.id).firstOrNull;
    // Changing what a card EMI bills makes what was already recorded for it wrong,
    // so it is recorded again from scratch.
    // A foreclosed EMI keeps its records, including the closure expense.
    if (before != null &&
        !before.foreclosed &&
        before.postedCount > 0 &&
        !_sameBilling(before, r)) {
      await _db.deleteEmiExpenses(r.id!);
      toSave = r.copyWith(postedCount: 0);
    }
    final id = await _db.saveRecurring(toSave);
    await reload();
    final saved = recurring.where((x) => x.id == id).firstOrNull;
    if (saved != null) {
      await _syncPurchase(saved);
      await reload();
      await syncCardEmis();
    }
    await _reschedule();
  }

  Future<void> deleteRecurring(int id) async {
    final r = recurring.where((x) => x.id == id).firstOrNull;
    // Before any instalment is billed nothing real has happened yet, so its
    // purchase entry goes too; afterwards the history stays in the reports.
    if (r != null && !r.foreclosed && (!isCardEmi(r) || emiBilledCount(r) == 0)) {
      await _db.deleteEmiExpenses(id);
    }
    await _db.deleteRecurring(id);
    await reload();
    await _reschedule();
  }

  Future<void> setRecurringActive(Recurring r, bool active) async {
    var next = r.nextDue;
    if (active) {
      // Resuming skips what was missed while paused.
      final today = dayOnly(DateTime.now());
      while (next.isBefore(today)) {
        next = r.advance(next);
      }
    }
    await saveRecurring(r.copyWith(active: active, nextDue: next));
  }

  /// "Paid": records an expense dated today and moves to the next due date.
  /// [paymentModeId] overrides the default mode for this payment only. An EMI
  /// counts the instalment and finishes after the last one. Returns the new
  /// expense id so the action can be undone.
  Future<int> markPaid(Recurring r, {int? paymentModeId}) async {
    final count = r.paidCount + 1;
    final id = await _db.saveExpense(Expense(
      amount: r.amount + (r.isEmi ? r.gstOn(r.paidCount + 1) + r.pendingFeeGross : 0),
      note: [
        r.name,
        if (r.isEmi && r.totalCount > 0) 'EMI $count/${r.totalCount}',
        if (r.isEmi && (r.pendingFee > 0 || (r.gstRate > 0 && r.hasPrincipal)))
          'incl. ${[if (r.pendingFee > 0) 'fee', if (r.gstRate > 0 && r.hasPrincipal) 'GST'].join(' & ')}',
        r.note,
      ].where((t) => t.isNotEmpty).join(' – '),
      categoryId: r.categoryId,
      paymentModeId: paymentModeId ?? r.paymentModeId,
      date: dayOnly(DateTime.now()),
    ));
    final done = r.isEmi && r.totalCount > 0 && count >= r.totalCount;
    await saveRecurring(r.copyWith(
      nextDue: r.advance(r.nextDue),
      paidCount: r.isEmi ? count : null,
      active: done ? false : null,
    ));
    return id;
  }

  /// "Not paid": skips this due date without adding any expense.
  Future<void> markNotPaid(Recurring r) =>
      saveRecurring(r.copyWith(nextDue: r.advance(r.nextDue)));

  /// Reverts [markPaid] / [markNotPaid]: [before] is the item as it was.
  Future<void> undoMark(Recurring before, {int? expenseId}) async {
    if (expenseId != null) await _db.deleteExpense(expenseId);
    await saveRecurring(before);
  }

  Future<void> _reschedule() =>
      NotificationService.instance.reschedule(
          recurring.where((r) => !isCardEmi(r)).toList(), recurringTitle, money, cardBills);

  // ---- notes ----
  Future<int> saveNote(Note n) async {
    final id = await _db.saveNote(n);
    await reload();
    return id;
  }

  Future<void> deleteNote(int id) async {
    await _db.deleteNote(id);
    await reload();
  }

  // ---- reporting ----
  List<Expense> inMonth(DateTime month) => expenses
      .where((e) => e.date.year == month.year && e.date.month == month.month)
      .toList();

  double total(Iterable<Expense> list) => list.fold(0.0, (s, e) => s + e.amount);

  double totalIncome(Iterable<Income> list) => list.fold(0.0, (s, i) => s + i.amount);

  List<Slice> incomeByCategory(Iterable<Income> list) {
    final map = <int, List<Income>>{};
    for (final i in list) {
      map.putIfAbsent(i.categoryId, () => []).add(i);
    }
    final out = map.entries.map((en) {
      final c = category(en.key);
      return Slice(en.key, c.name, totalIncome(en.value), en.value.length, Color(c.color), c.icon);
    }).toList();
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// Income split by the account that received it.
  List<Slice> incomeByPayment(Iterable<Income> list) {
    final map = <int, List<Income>>{};
    for (final i in list) {
      map.putIfAbsent(i.paymentModeId, () => []).add(i);
    }
    final out = map.entries.map((en) {
      final m = paymentMode(en.key);
      return Slice(en.key, paymentLabel(en.key), totalIncome(en.value), en.value.length,
          kPalette[en.key % kPalette.length], m.icon);
    }).toList();
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  List<Slice> byCategory(Iterable<Expense> list) {
    final map = <int, List<Expense>>{};
    for (final e in list) {
      map.putIfAbsent(e.categoryId, () => []).add(e);
    }
    final out = map.entries.map((en) {
      final c = category(en.key);
      return Slice(en.key, c.name, total(en.value), en.value.length, Color(c.color), c.icon);
    }).toList();
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  List<Slice> byPayment(Iterable<Expense> list) {
    final map = <int, List<Expense>>{};
    for (final e in list) {
      map.putIfAbsent(e.paymentModeId, () => []).add(e);
    }
    final out = map.entries.map((en) {
      final m = paymentMode(en.key);
      return Slice(en.key, m.name, total(en.value), en.value.length,
          kPalette[en.key % kPalette.length], m.icon);
    }).toList();
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }
}

