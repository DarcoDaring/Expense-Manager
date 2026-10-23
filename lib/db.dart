import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'models.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    String path;
    if (kIsWeb) {
      // Browser: SQLite compiled to wasm, persisted in IndexedDB.
      databaseFactory = databaseFactoryFfiWebNoWebWorker;
      path = 'expense_manager.db';
    } else {
      path = p.join(await getDatabasesPath(), 'expense_manager.db');
    }
    return openDatabase(
      path,
      version: 3,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''CREATE TABLE categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          icon INTEGER NOT NULL,
          color INTEGER NOT NULL)''');
        await d.execute('''CREATE TABLE payment_modes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          icon INTEGER NOT NULL)''');
        await d.execute('''CREATE TABLE expenses(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          note TEXT,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
          payment_mode_id INTEGER NOT NULL REFERENCES payment_modes(id) ON DELETE RESTRICT,
          date INTEGER NOT NULL)''');
        await d.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
        await _createRecurring(d);

        // Starter data; everything here can be edited or deleted by the user.
        const cats = [
          ['Food', 0, 0xFFF97316],
          ['Transport', 1, 0xFF0EA5E9],
          ['Shopping', 2, 0xFFEC4899],
          ['Bills', 3, 0xFF6366F1],
          ['Health', 4, 0xFFEF4444],
          ['Entertainment', 5, 0xFF8B5CF6],
        ];
        for (final c in cats) {
          await d.insert('categories', {'name': c[0], 'icon': c[1], 'color': c[2]});
        }
        const modes = [
          ['Cash', 16],
          ['Card', 17],
          ['UPI', 19],
        ];
        for (final m in modes) {
          await d.insert('payment_modes', {'name': m[0], 'icon': m[1]});
        }
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) {
          await _createRecurring(d); // already has the v3 columns
        } else if (from < 3) {
          await d.execute("ALTER TABLE recurring ADD COLUMN name TEXT NOT NULL DEFAULT ''");
          await d.execute('ALTER TABLE recurring ADD COLUMN icon INTEGER NOT NULL DEFAULT 22');
        }
      },
    );
  }

  static Future<void> _createRecurring(Database d) => d.execute('''CREATE TABLE recurring(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL DEFAULT '',
          icon INTEGER NOT NULL DEFAULT 22,
          amount REAL NOT NULL,
          note TEXT,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
          payment_mode_id INTEGER NOT NULL REFERENCES payment_modes(id) ON DELETE RESTRICT,
          frequency INTEGER NOT NULL,
          start_date INTEGER NOT NULL,
          next_due INTEGER NOT NULL,
          active INTEGER NOT NULL DEFAULT 1,
          remind_days INTEGER NOT NULL DEFAULT 1)''');

  Future<List<Category>> categories() async =>
      (await (await db).query('categories', orderBy: 'name COLLATE NOCASE'))
          .map(Category.fromMap)
          .toList();

  Future<List<PaymentMode>> paymentModes() async =>
      (await (await db).query('payment_modes', orderBy: 'name COLLATE NOCASE'))
          .map(PaymentMode.fromMap)
          .toList();

  Future<List<Expense>> expenses() async =>
      (await (await db).query('expenses', orderBy: 'date DESC, id DESC'))
          .map(Expense.fromMap)
          .toList();

  Future<int> saveCategory(Category c) async {
    final d = await db;
    if (c.id == null) return d.insert('categories', c.toMap()..remove('id'));
    await d.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  Future<int> savePaymentMode(PaymentMode m) async {
    final d = await db;
    if (m.id == null) return d.insert('payment_modes', m.toMap()..remove('id'));
    await d.update('payment_modes', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
    return m.id!;
  }

  Future<int> saveExpense(Expense e) async {
    final d = await db;
    if (e.id == null) return d.insert('expenses', e.toMap()..remove('id'));
    await d.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    return e.id!;
  }

  Future<void> deleteExpense(int id) async =>
      (await db).delete('expenses', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteCategory(int id) async =>
      (await db).delete('categories', where: 'id = ?', whereArgs: [id]);

  Future<void> deletePaymentMode(int id) async =>
      (await db).delete('payment_modes', where: 'id = ?', whereArgs: [id]);

  Future<List<Recurring>> recurring() async =>
      (await (await db).query('recurring', orderBy: 'next_due ASC'))
          .map(Recurring.fromMap)
          .toList();

  Future<int> saveRecurring(Recurring r) async {
    final d = await db;
    if (r.id == null) return d.insert('recurring', r.toMap()..remove('id'));
    await d.update('recurring', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    return r.id!;
  }

  Future<void> deleteRecurring(int id) async =>
      (await db).delete('recurring', where: 'id = ?', whereArgs: [id]);
}
