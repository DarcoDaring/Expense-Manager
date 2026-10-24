import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

/// Schedules local reminders for upcoming subscription payments and credit card bills. Does nothing on web.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// How many upcoming occurrences per bill get a reminder queued, so
  /// reminders keep arriving even if the app is not opened for a while.
  static const _perItem = 6;
  static const _hour = 9; // reminders fire at 9:00 AM local time

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks for notification permission (Android 13+ / iOS). Returns whether granted.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Rebuilds every pending reminder from the current list of bills.
  Future<void> reschedule(
    List<Recurring> items,
    String Function(Recurring) title,
    String Function(double) money,
    List<CardBill> cards,
  ) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final now = tz.TZDateTime.now(tz.local);
      for (final r in items) {
        if (!r.active || r.remindDays < 0 || r.id == null) continue;
        var due = dayOnly(r.nextDue);
        for (var k = 0; k < _perItem; k++) {
          final fire = tz.TZDateTime(
              tz.local, due.year, due.month, due.day - r.remindDays, _hour);
          if (fire.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: r.id! * 100 + k,
              title: 'Upcoming: ${title(r)}',
              body: '${money(r.amount)} ${_when(r.remindDays)}',
              scheduledDate: fire,
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'recurring_bills',
                  'Subscriptions',
                  channelDescription: 'Reminders for your subscriptions and bills',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
                iOS: DarwinNotificationDetails(),
              ),
              // Inexact keeps this free of the exact-alarm permission.
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
          due = r.advance(due);
        }
      }
      await _scheduleCards(cards, money, now);
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  /// Reminders for the next few statements of every card: a note when each
  /// statement is generated, then 3 days before, 1 day before and on the due
  /// day. The current bill's amount is known; later ones say to check the app.
  Future<void> _scheduleCards(
      List<CardBill> cards, String Function(double) money, tz.TZDateTime now) async {
    const cycles = 3;
    const offsets = [3, 1, 0];
    for (final b in cards) {
      final card = b.card;
      if (card.id == null) continue;
      var statement = b.statementDate;
      for (var k = 0; k < cycles; k++) {
        if (k > 0) {
          statement = monthDay(statement.year, statement.month + 1, card.billingDay);
          await _notify(
            id: 1000000 + card.id! * 100 + k * 10 + 3,
            fire: tz.TZDateTime(tz.local, statement.year, statement.month, statement.day, _hour),
            now: now,
            title: '${card.name} statement generated',
            body: 'Open the app to see your bill and pay it.',
          );
        }
        final due = billDueDate(statement, card.dueDay);
        final known = k == 0;
        if (known && b.due <= 0) continue;
        for (var j = 0; j < offsets.length; j++) {
          final days = offsets[j];
          await _notify(
            id: 1000000 + card.id! * 100 + k * 10 + j,
            fire: tz.TZDateTime(tz.local, due.year, due.month, due.day - days, _hour),
            now: now,
            title: 'Credit card bill: ${card.name}',
            body: '${known ? '${money(b.due)} ' : 'Your bill '}${_when(days)}',
          );
        }
      }
    }
  }

  Future<void> _notify({
    required int id,
    required tz.TZDateTime fire,
    required tz.TZDateTime now,
    required String title,
    required String body,
  }) async {
    if (!fire.isAfter(now)) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: fire,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'card_bills',
          'Credit card bills',
          channelDescription: 'Statement and due date reminders for your credit cards',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  String _when(int days) => switch (days) {
        0 => 'is due today',
        1 => 'is due tomorrow',
        _ => 'is due in $days days',
      };
}
