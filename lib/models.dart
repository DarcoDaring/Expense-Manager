import 'package:flutter/material.dart';

/// Icons users can pick for categories and payment modes. Only the index is
/// persisted, so the list must stay append-only.
const List<IconData> kIcons = [
  Icons.restaurant_rounded,
  Icons.directions_car_rounded,
  Icons.shopping_bag_rounded,
  Icons.receipt_long_rounded,
  Icons.favorite_rounded,
  Icons.movie_rounded,
  Icons.home_rounded,
  Icons.school_rounded,
  Icons.flight_rounded,
  Icons.local_gas_station_rounded,
  Icons.pets_rounded,
  Icons.card_giftcard_rounded,
  Icons.fitness_center_rounded,
  Icons.phone_android_rounded,
  Icons.coffee_rounded,
  Icons.category_rounded,
  Icons.payments_rounded,
  Icons.credit_card_rounded,
  Icons.account_balance_rounded,
  Icons.qr_code_2_rounded,
  Icons.account_balance_wallet_rounded,
  Icons.contactless_rounded,
  // Added for subscriptions (append-only: indexes are persisted).
  Icons.subscriptions_rounded,
  Icons.tv_rounded,
  Icons.music_note_rounded,
  Icons.cloud_rounded,
  Icons.wifi_rounded,
  Icons.bolt_rounded,
  Icons.water_drop_rounded,
  Icons.security_rounded,
  Icons.sports_esports_rounded,
  Icons.newspaper_rounded,
  Icons.apartment_rounded,
  Icons.car_repair_rounded,
  Icons.medication_rounded,
  Icons.child_care_rounded,
  Icons.savings_rounded,
];

/// Default icon for a new subscription (Icons.subscriptions_rounded).
const int kSubscriptionIcon = 22;

const List<Color> kPalette = [
  Color(0xFF6366F1),
  Color(0xFF14B8A6),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFF64748B),
];

IconData iconAt(int i) => kIcons[i.clamp(0, kIcons.length - 1)];

class Category {
  final int? id;
  final String name;
  final int icon;
  final int color;

  const Category({this.id, required this.name, required this.icon, required this.color});

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as int,
        color: m['color'] as int,
      );

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'icon': icon, 'color': color};
}

class PaymentMode {
  final int? id;
  final String name;
  final int icon;

  const PaymentMode({this.id, required this.name, required this.icon});

  factory PaymentMode.fromMap(Map<String, Object?> m) =>
      PaymentMode(id: m['id'] as int, name: m['name'] as String, icon: m['icon'] as int);

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'icon': icon};
}

class Expense {
  final int? id;
  final double amount;
  final String note;
  final int categoryId;
  final int paymentModeId;
  final DateTime date;

  const Expense({
    this.id,
    required this.amount,
    required this.note,
    required this.categoryId,
    required this.paymentModeId,
    required this.date,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        categoryId: m['category_id'] as int,
        paymentModeId: m['payment_mode_id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'note': note,
        'category_id': categoryId,
        'payment_mode_id': paymentModeId,
        'date': date.millisecondsSinceEpoch,
      };
}

enum Frequency {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  final String label;
  final String unit;
  const Frequency(this.label, this.unit);
}

/// Days-before options for the reminder; 0 means "on the due day", -1 is off.
const List<int> kReminderChoices = [-1, 0, 1, 3, 7];

String reminderLabel(int days) => switch (days) {
      -1 => 'No reminder',
      0 => 'On the due day',
      1 => '1 day before',
      _ => '$days days before',
    };

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A bill or subscription that repeats on a schedule. [nextDue] is the next
/// date an expense has not yet been created for.
class Recurring {
  final int? id;
  final String name;
  final int icon;
  final double amount;
  final String note;
  final int categoryId;
  final int paymentModeId;
  final Frequency frequency;
  final DateTime startDate;
  final DateTime nextDue;
  final bool active;
  final int remindDays;

  const Recurring({
    this.id,
    required this.name,
    required this.icon,
    required this.amount,
    required this.note,
    required this.categoryId,
    required this.paymentModeId,
    required this.frequency,
    required this.startDate,
    required this.nextDue,
    this.active = true,
    this.remindDays = 1,
  });

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? '',
        icon: (m['icon'] as int?) ?? kSubscriptionIcon,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        categoryId: m['category_id'] as int,
        paymentModeId: m['payment_mode_id'] as int,
        frequency: Frequency.values[m['frequency'] as int],
        startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
        nextDue: DateTime.fromMillisecondsSinceEpoch(m['next_due'] as int),
        active: (m['active'] as int) == 1,
        remindDays: m['remind_days'] as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'amount': amount,
        'note': note,
        'category_id': categoryId,
        'payment_mode_id': paymentModeId,
        'frequency': frequency.index,
        'start_date': startDate.millisecondsSinceEpoch,
        'next_due': nextDue.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
        'remind_days': remindDays,
      };

  Recurring copyWith({DateTime? nextDue, bool? active}) => Recurring(
        id: id,
        name: name,
        icon: icon,
        amount: amount,
        note: note,
        categoryId: categoryId,
        paymentModeId: paymentModeId,
        frequency: frequency,
        startDate: startDate,
        nextDue: nextDue ?? this.nextDue,
        active: active ?? this.active,
        remindDays: remindDays,
      );

  /// The occurrence after [from]. Monthly/yearly keep the start day, clamped
  /// to short months (31 Jan -> 28 Feb -> 31 Mar).
  DateTime advance(DateTime from) {
    switch (frequency) {
      case Frequency.daily:
        return DateTime(from.year, from.month, from.day + 1);
      case Frequency.weekly:
        return DateTime(from.year, from.month, from.day + 7);
      case Frequency.monthly:
        final y = from.year + (from.month == 12 ? 1 : 0);
        final mo = from.month == 12 ? 1 : from.month + 1;
        return DateTime(y, mo, _clamp(y, mo, startDate.day));
      case Frequency.yearly:
        final y = from.year + 1;
        return DateTime(y, startDate.month, _clamp(y, startDate.month, startDate.day));
    }
  }

  static int _clamp(int y, int m, int day) {
    final last = DateTime(y, m + 1, 0).day;
    return day > last ? last : day;
  }

  /// Rough monthly cost, used for the summary card.
  double get monthlyEquivalent => switch (frequency) {
        Frequency.daily => amount * 30.4375,
        Frequency.weekly => amount * 52 / 12,
        Frequency.monthly => amount,
        Frequency.yearly => amount / 12,
      };
}
