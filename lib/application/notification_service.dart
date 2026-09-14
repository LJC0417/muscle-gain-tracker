/// 本地通知服务（4 类提醒：体重 / 训练 / 喝水 / 每周复盘）
/// settings key 与 prototype me.js 一致：
///   notifyWeightEnabled / notifyWeightTime
///   notifyWorkoutEnabled / notifyWorkoutTime
///   notifyWaterEnabled（10:00-21:00 每 2 小时）
///   notifyReviewEnabled（周日 20:00）
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/app_config.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {/* 兜底：系统默认偏移 */}
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    // Android 13+ 运行时权限
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _inited = true;
  }

  AndroidNotificationDetails get _android => const AndroidNotificationDetails(
        'mg_reminders',
        '增肌提醒',
        channelDescription: '体重/训练/喝水/周复盘提醒',
        importance: Importance.high,
        priority: Priority.high,
      );

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// 清掉全部旧提醒（重排前调用，保证开关/时间改动即时生效）。
  Future<void> cancelAll() => _plugin.cancelAll();

  /// 按 settings 重排所有提醒。settings 值为 '0'/'1' 与 'HH:mm'。
  Future<void> reschedule(Map<String, String> s) async {
    await init();
    await cancelAll();

    // 1) 体重提醒（每日）
    if (s['notifyWeightEnabled'] == '1') {
      final t = _parseTime(s['notifyWeightTime'], AppConfig.notifyWeightTime);
      await _plugin.zonedSchedule(
        1001,
        '该称体重啦',
        '晨起空腹称重更准，点按记录今日体重。',
        _nextInstance(t.$1, t.$2),
        NotificationDetails(android: _android),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    // 2) 训练提醒（每日；休息日用户自行忽略）
    if (s['notifyWorkoutEnabled'] == '1') {
      final t = _parseTime(s['notifyWorkoutTime'], AppConfig.notifyWorkoutTime);
      await _plugin.zonedSchedule(
        1002,
        '训练时间到',
        '按排期完成今天的训练动作，保持渐进超负荷。',
        _nextInstance(t.$1, t.$2),
        NotificationDetails(android: _android),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    // 3) 喝水提醒（10:00–21:00 每 2 小时）
    if (s['notifyWaterEnabled'] == '1') {
      const times = [
        (10, 0),
        (12, 0),
        (14, 0),
        (16, 0),
        (18, 0),
        (20, 0),
      ];
      for (var i = 0; i < times.length; i++) {
        await _plugin.zonedSchedule(
          1100 + i,
          '喝水打卡',
          '来一杯水，向 ${AppConfig.waterGoalCups} 杯目标迈进。',
          _nextInstance(times[i].$1, times[i].$2),
          NotificationDetails(android: _android),
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }

    // 4) 每周复盘提醒（周日 20:00）
    if (s['notifyReviewEnabled'] == '1') {
      final now = tz.TZDateTime.now(tz.local);
      var t = _nextInstance(20, 0);
      // 平移到下一个周日
      while (t.weekday != DateTime.sunday) {
        t = t.add(const Duration(days: 1));
      }
      if (t.isBefore(now)) t = t.add(const Duration(days: 7));
      await _plugin.zonedSchedule(
        1003,
        '每周复盘',
        '生成一次本周总结，看看体重节奏和训练容量。',
        t,
        NotificationDetails(android: _android),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  (int, int) _parseTime(String? raw, String fallback) {
    final src = (raw == null || raw.isEmpty) ? fallback : raw;
    final p = src.split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 8;
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    return (h.clamp(0, 23), m.clamp(0, 59));
  }
}
