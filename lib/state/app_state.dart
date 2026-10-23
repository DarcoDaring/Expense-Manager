import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db.dart';
import '../models.dart';
import '../services/notification_service.dart';

/// One row of a report: a label with its total and share of the whole.
class Slice {
  final int id;
  final String label;
  final double total;
  final int count;
  final Color color;
  final IconData icon;
  const Slice(this.id, this.label, this.total, this.count, this.color, this.icon);
}

class AppState extends ChangeNotifier {
  final _db = AppDb.instance;

  List<Category> categories = [];
  List<PaymentMode> paymentModes = [];
  List<Expense> expenses = [];
  List<Recurring> recurring = [];
  bool loaded = false;

  String currency = '₹';
  ThemeMode themeMode = ThemeMode.system;
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    currency = _prefs.getString('currency') ?? '₹';
    themeMode = ThemeMode.values[_prefs.getInt('theme') ?? 0];
    await NotificationService.instance.init();
    await reload();
    await _reschedule();
    loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    categories = await _db.categories();
    paymentModes = await _db.paymentModes();
    expenses = await _db.expenses();
    recurring = await _db.recurring();
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
  Category category(int id) => categories.firstWhere((c) => c.id == id,
      orElse: () => const Category(name: 'Unknown', icon: 15, color: 0xFF64748B));

  PaymentMode paymentMode(int id) => paymentModes.firstWhere((m) => m.id == id,
      orElse: () => const PaymentMode(name: 'Unknown', icon: 16));

  // ---- writes ----
  Future<void> saveExpense(Expense e) async {
    await _db.saveExpense(e);
    await reload();
  }

  Future<void> deleteExpense(int id) async {
    await _db.deleteExpense(id);
    await reload();
  }

  /// Returns the new/updated id, or null when the name is already taken.
  Future<int?> saveCategory(Category c) async {
    final clash = categories.any(
        (x) => x.id != c.id && x.name.toLowerCase() == c.name.trim().toLowerCase());
    if (clash) return null;
    final id = await _db.saveCategory(
        Category(id: c.id, name: c.name.trim(), icon: c.icon, color: c.color));
    await reload();
    return id;
  }

  Future<int?> savePaymentMode(PaymentMode m) async {
    final clash = paymentModes.any(
        (x) => x.id != m.id && x.name.toLowerCase() == m.name.trim().toLowerCase());
    if (clash) return null;
    final id = await _db.savePaymentMode(
        PaymentMode(id: m.id, name: m.name.trim(), icon: m.icon));
    await reload();
    return id;
  }

  int categoryUsage(int id) =>
      expenses.where((e) => e.categoryId == id).length +
      recurring.where((r) => r.categoryId == id).length;
  int paymentModeUsage(int id) =>
      expenses.where((e) => e.paymentModeId == id).length +
      recurring.where((r) => r.paymentModeId == id).length;

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    await reload();
  }

  Future<void> deletePaymentMode(int id) async {
    await _db.deletePaymentMode(id);
    await reload();
  }

  // ---- recurring ----
  String recurringTitle(Recurring r) =>
      r.name.isNotEmpty ? r.name : category(r.categoryId).name;

  Future<void> saveRecurring(Recurring r) async {
    await _db.saveRecurring(r);
    await reload();
    await _reschedule();
  }

  Future<void> deleteRecurring(int id) async {
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
  /// Returns the new expense id so the action can be undone.
  Future<int> markPaid(Recurring r) async {
    final id = await _db.saveExpense(Expense(
      amount: r.amount,
      note: [r.name, r.note].where((t) => t.isNotEmpty).join(' – '),
      categoryId: r.categoryId,
      paymentModeId: r.paymentModeId,
      date: dayOnly(DateTime.now()),
    ));
    await saveRecurring(r.copyWith(nextDue: r.advance(r.nextDue)));
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
      NotificationService.instance.reschedule(recurring, recurringTitle, money);

  // ---- reporting ----
  List<Expense> inMonth(DateTime month) => expenses
      .where((e) => e.date.year == month.year && e.date.month == month.month)
      .toList();

  double total(Iterable<Expense> list) => list.fold(0.0, (s, e) => s + e.amount);

  List<Slice> byCategory(Iterable<Expense> list) {
    final map = <int, List<Expense>>{};
    for (final e in list) {
      map.putIfAbsent(e.categoryId, () => []).add(e);
    }
    final out = map.entries.map((en) {
      final c = category(en.key);
      return Slice(en.key, c.name, total(en.value), en.value.length, Color(c.color), iconAt(c.icon));
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
          kPalette[en.key % kPalette.length], iconAt(m.icon));
    }).toList();
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }
}

