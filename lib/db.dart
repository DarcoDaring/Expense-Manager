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
      version: 17,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''CREATE TABLE categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          icon INTEGER NOT NULL,
          color INTEGER NOT NULL,
          kind INTEGER NOT NULL DEFAULT 0)''');
        await d.execute('''CREATE TABLE payment_modes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          icon INTEGER NOT NULL,
          account_id INTEGER)''');
        await _createAccounts(d);
        await d.execute('''CREATE TABLE expenses(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          note TEXT,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
          payment_mode_id INTEGER NOT NULL REFERENCES payment_modes(id) ON DELETE RESTRICT,
          date INTEGER NOT NULL,
          attachment TEXT,
          emi_id INTEGER,
          split_group INTEGER)''');
        await d.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
        await _createRecurring(d);
        await _createNotes(d);
        await _createCardPayments(d);
        await _createIncomes(d);

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
        await _addCashAccount(d);
        await _seedIncomeCategories(d);
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) {
          await _createRecurring(d); // already has the v3 and v5 columns
        } else {
          if (from < 3) {
            await d.execute("ALTER TABLE recurring ADD COLUMN name TEXT NOT NULL DEFAULT ''");
            await d.execute('ALTER TABLE recurring ADD COLUMN icon INTEGER NOT NULL DEFAULT 22');
          }
          if (from < 5) {
            await d.execute('ALTER TABLE recurring ADD COLUMN kind INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN total_count INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN paid_count INTEGER NOT NULL DEFAULT 0');
          }
          if (from < 9) {
            await d.execute('ALTER TABLE recurring ADD COLUMN principal REAL NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN fee REAL NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN created INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN posted_count INTEGER NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN purchase_expense_id INTEGER');
          }
          if (from < 14) {
            await d.execute('ALTER TABLE recurring ADD COLUMN gst_rate REAL NOT NULL DEFAULT 0');
          }
          if (from < 15) {
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN first_delay INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN initial_interest REAL NOT NULL DEFAULT 0');
          }
          if (from < 16) {
            await d.execute('ALTER TABLE recurring ADD COLUMN closed_on INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'ALTER TABLE recurring ADD COLUMN close_principal REAL NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN close_charge REAL NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN close_gst REAL NOT NULL DEFAULT 0');
            await d.execute('ALTER TABLE recurring ADD COLUMN closure_expense_id INTEGER');
          }
        }
        if (from < 4) {
          await d.execute('ALTER TABLE payment_modes ADD COLUMN account_id INTEGER');
          await _createAccounts(d);
          await _addCashAccount(d);
        }
        if (from < 5) await _createNotes(d);
        if (from < 6) {
          // Accounts created in this same upgrade (from < 4) already have the column.
          if (from >= 4) {
            await d.execute(
                'ALTER TABLE accounts ADD COLUMN base_payment_id INTEGER NOT NULL DEFAULT 0');
          }
          await _createCardPayments(d);
        }
        if (from < 7) await d.execute('ALTER TABLE expenses ADD COLUMN attachment TEXT');
        // Accounts created in this same upgrade (from < 4) already have the columns.
        if (from < 8 && from >= 4) {
          await d.execute(
              'ALTER TABLE accounts ADD COLUMN unbilled_base REAL NOT NULL DEFAULT 0');
          await d.execute(
              'ALTER TABLE accounts ADD COLUMN base_date INTEGER NOT NULL DEFAULT 0');
        }
        if (from < 9) await d.execute('ALTER TABLE expenses ADD COLUMN emi_id INTEGER');
        if (from < 17) await d.execute('ALTER TABLE expenses ADD COLUMN split_group INTEGER');
        if (from < 10) {
          await d.execute('ALTER TABLE categories ADD COLUMN kind INTEGER NOT NULL DEFAULT 0');
          // Accounts created in this same upgrade (from < 4) already have the column.
          if (from >= 4) {
            await d.execute(
                'ALTER TABLE accounts ADD COLUMN base_income_id INTEGER NOT NULL DEFAULT 0');
          }
          await _createIncomes(d);
          await _seedIncomeCategories(d);
        }
        if (from < 11) {
          // Card EMIs now record each instalment as it is billed instead of the whole
          // purchase: drop what they recorded before, and they are posted again.
          await d.execute('DELETE FROM expenses WHERE emi_id IS NOT NULL');
          await d.execute('UPDATE recurring SET posted_count = 0, purchase_expense_id = NULL');
        }
        // Accounts created in this same upgrade (from < 4) already have the column.
        if (from < 12 && from >= 4) {
          await d.execute('ALTER TABLE accounts ADD COLUMN shared_with INTEGER');
        }
        if (from < 13) {
          // An EMI already running is now billed from the day it was entered, so what
          // was recorded for it before is dropped and posted again.
          await d.execute(
              'DELETE FROM expenses WHERE emi_id IN (SELECT id FROM recurring WHERE paid_count > 0)');
          await d.execute('UPDATE recurring SET posted_count = 0 WHERE paid_count > 0');
        }
      },
    );
  }

  static Future<void> _createAccounts(Database d) => d.execute('''CREATE TABLE accounts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type INTEGER NOT NULL,
          balance REAL NOT NULL DEFAULT 0,
          total_limit REAL NOT NULL DEFAULT 0,
          billing_day INTEGER NOT NULL DEFAULT 1,
          due_day INTEGER NOT NULL DEFAULT 15,
          base_expense_id INTEGER NOT NULL DEFAULT 0,
          base_payment_id INTEGER NOT NULL DEFAULT 0,
          unbilled_base REAL NOT NULL DEFAULT 0,
          base_date INTEGER NOT NULL DEFAULT 0,
          base_income_id INTEGER NOT NULL DEFAULT 0,
          shared_with INTEGER)''');

  static Future<void> _createCardPayments(Database d) => d.execute('''CREATE TABLE card_payments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id INTEGER NOT NULL,
          mode_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          note TEXT,
          date INTEGER NOT NULL)''');

  /// The built-in Cash account; an existing "Cash" payment mode is linked to it.
  static Future<void> _addCashAccount(Database d) async {
    final last = await d.rawQuery('SELECT COALESCE(MAX(id), 0) AS m FROM expenses');
    final id = await d.insert('accounts', {
      'name': 'Cash',
      'type': AccountType.cash.index,
      'base_expense_id': last.first['m'],
    });
    await d.update('payment_modes', {'account_id': id},
        where: "name = 'Cash' COLLATE NOCASE");
  }

  static Future<void> _createIncomes(Database d) => d.execute('''CREATE TABLE incomes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          note TEXT,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
          payment_mode_id INTEGER NOT NULL REFERENCES payment_modes(id) ON DELETE RESTRICT,
          date INTEGER NOT NULL)''');

  /// Starter income categories (kind 1); they can be edited or deleted.
  static Future<void> _seedIncomeCategories(Database d) async {
    int icon(String name) {
      final i = kIcons.indexWhere((x) => x.name == name);
      return i < 0 ? 15 : i;
    }

    final starters = [
      ('Salary', icon('Salary'), 0xFF22C55E),
      ('Business', icon('Business'), 0xFF14B8A6),
      ('Interest', icon('Interest'), 0xFF0EA5E9),
      ('Investments', icon('Investments'), 0xFF6366F1),
      ('Gifts', icon('Gifts'), 0xFFEC4899),
      ('Refund', icon('Rupee'), 0xFFF59E0B),
      ('Other income', icon('Other'), 0xFF64748B),
    ];
    for (final (name, ic, color) in starters) {
      // A name already used by an expense category is skipped (names are unique).
      await d.insert('categories', {'name': name, 'icon': ic, 'color': color, 'kind': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
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
          remind_days INTEGER NOT NULL DEFAULT 1,
          kind INTEGER NOT NULL DEFAULT 0,
          total_count INTEGER NOT NULL DEFAULT 0,
          paid_count INTEGER NOT NULL DEFAULT 0,
          principal REAL NOT NULL DEFAULT 0,
          fee REAL NOT NULL DEFAULT 0,
          created INTEGER NOT NULL DEFAULT 0,
          posted_count INTEGER NOT NULL DEFAULT 0,
          purchase_expense_id INTEGER,
          gst_rate REAL NOT NULL DEFAULT 0,
          first_delay INTEGER NOT NULL DEFAULT 0,
          initial_interest REAL NOT NULL DEFAULT 0,
          closed_on INTEGER NOT NULL DEFAULT 0,
          close_principal REAL NOT NULL DEFAULT 0,
          close_charge REAL NOT NULL DEFAULT 0,
          close_gst REAL NOT NULL DEFAULT 0,
          closure_expense_id INTEGER)''');

  static Future<void> _createNotes(Database d) => d.execute('''CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          body TEXT NOT NULL DEFAULT '',
          pinned INTEGER NOT NULL DEFAULT 0,
          updated INTEGER NOT NULL)''');

  Future<List<Category>> categories() async =>
      (await (await db).query('categories', orderBy: 'name COLLATE NOCASE'))
          .map(Category.fromMap)
          .toList();

  Future<List<PaymentMode>> paymentModes() async =>
      (await (await db).query('payment_modes', orderBy: 'name COLLATE NOCASE'))
          .map(PaymentMode.fromMap)
          .toList();

  Future<List<Account>> accounts() async =>
      (await (await db).query('accounts', orderBy: 'id')).map(Account.fromMap).toList();

  Future<int> saveAccount(Account a) async {
    final d = await db;
    if (a.id == null) return d.insert('accounts', a.toMap()..remove('id'));
    await d.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    return a.id!;
  }

  /// Deletes the account; its payment modes stay, just unlinked.
  Future<void> deleteAccount(int id) async {
    final d = await db;
    await d.update('payment_modes', {'account_id': null},
        where: 'account_id = ?', whereArgs: [id]);
    await d.delete('card_payments', where: 'card_id = ?', whereArgs: [id]);
    // Cards that shared this card's limit keep it as their own.
    await d.update('accounts', {'shared_with': null},
        where: 'shared_with = ?', whereArgs: [id]);
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

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

  Future<List<Income>> incomes() async =>
      (await (await db).query('incomes', orderBy: 'date DESC, id DESC'))
          .map(Income.fromMap)
          .toList();

  Future<int> saveIncome(Income i) async {
    final d = await db;
    if (i.id == null) return d.insert('incomes', i.toMap()..remove('id'));
    await d.update('incomes', i.toMap(), where: 'id = ?', whereArgs: [i.id]);
    return i.id!;
  }

  Future<void> deleteIncome(int id) async =>
      (await db).delete('incomes', where: 'id = ?', whereArgs: [id]);

  /// Removes every leg of a payment that was split across accounts.
  Future<void> deleteExpenseGroup(int group) async =>
      (await db).delete('expenses', where: 'split_group = ?', whereArgs: [group]);

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

  /// Removes the purchase / interest / fee entries a card EMI created.
  Future<void> deleteEmiExpenses(int emiId) async =>
      (await db).delete('expenses', where: 'emi_id = ?', whereArgs: [emiId]);

  Future<void> deleteRecurring(int id) async =>
      (await db).delete('recurring', where: 'id = ?', whereArgs: [id]);

  Future<List<Note>> notes() async =>
      (await (await db).query('notes', orderBy: 'pinned DESC, updated DESC'))
          .map(Note.fromMap)
          .toList();

  Future<int> saveNote(Note n) async {
    final d = await db;
    if (n.id == null) return d.insert('notes', n.toMap()..remove('id'));
    await d.update('notes', n.toMap(), where: 'id = ?', whereArgs: [n.id]);
    return n.id!;
  }

  Future<void> deleteNote(int id) async =>
      (await db).delete('notes', where: 'id = ?', whereArgs: [id]);

  Future<List<CardPayment>> cardPayments() async =>
      (await (await db).query('card_payments', orderBy: 'date DESC, id DESC'))
          .map(CardPayment.fromMap)
          .toList();

  Future<int> saveCardPayment(CardPayment p) async {
    final d = await db;
    if (p.id == null) return d.insert('card_payments', p.toMap()..remove('id'));
    await d.update('card_payments', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
    return p.id!;
  }

  Future<void> deleteCardPayment(int id) async =>
      (await db).delete('card_payments', where: 'id = ?', whereArgs: [id]);

  // ---- cloud sync ----
  static const _syncTables = [
    'categories',
    'payment_modes',
    'accounts',
    'expenses',
    'incomes',
    'recurring',
    'notes',
    'card_payments',
  ];

  /// Every row of every table, for the cloud copy.
  Future<Map<String, List<Map<String, Object?>>>> exportAll() async {
    final d = await db;
    return {for (final t in _syncTables) t: await d.query(t, orderBy: 'id')};
  }

  /// Replaces everything on this device with [data] (ids are kept).
  Future<void> importAll(Map<String, List<Map<String, Object?>>> data) async {
    final d = await db;
    await d.execute('PRAGMA foreign_keys = OFF');
    try {
      await d.transaction((tx) async {
        for (final t in _syncTables.reversed) {
          await tx.delete(t);
        }
        for (final t in _syncTables) {
          for (final row in data[t] ?? const []) {
            await tx.insert(t, row);
          }
        }
      });
    } finally {
      await d.execute('PRAGMA foreign_keys = ON');
    }
  }
}
