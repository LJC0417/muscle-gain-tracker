/// 本地通知服务（4 类提醒：体重 / 训练 / 喝水 / 每周复盘）
/// settings key 与 prototype me.js 一致：
///   notifyWeightEnabled / notifyWeightTime
///   notifyWorkoutEnabled / notifyWorkoutTime
///   notifyWaterEnabled（10:00-21:00 每 2 小时）
///   notifyReviewEnabled（周日 20:00）
///
/// 可靠性要点（真实反馈：关掉应用后收不到通知）：
///   - Android 13+ 必须运行时申请 POST_NOTIFICATIONS（init 时申请）
///   - 非 exact 闹钟在国产 ROM 省电策略下会被无限推迟 → 优先 exactAllowWhileIdle，
///     未授权时自动降级 inexact 并拉起系统授权页。USE_EXACT_ALARM 在 13+ 自动授予，
///     12 及以下走 SCHEDULE_EXACT_ALARM 的用户授权
///   - 手表同步：通知本身是系统通知，手表镜像由手机端健康类 App 完成，
///     应用侧能做的是用标准高优先级渠道 + reminder 类别
library;

import 'package:flutter/services.dart' show PlatformException;
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
    // Android 13+ 运行时权限（首次启动弹一次）
    await _androidPlugin()?.requestNotificationsPermission();
    _inited = true;
  }

  AndroidFlutterLocalNotificationsPlugin? _androidPlugin() =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  AndroidNotificationDetails get _android => const AndroidNotificationDetails(
        'mg_reminders',
        '增肌提醒',
        channelDescription: '体重/训练/喝水/周复盘提醒',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      );

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// 清掉全部旧提醒（重排前调用，保证开关/时间改动即时生效）。
  Future<void> cancelAll() => _plugin.cancelAll();

  /// 立即发一条测试通知。返回给 UI 的状态文案。
  Future<String> sendTestNotification() async {
    await init();
    final enabled = await _androidPlugin()?.areNotificationsEnabled() ?? true;
    if (!enabled) {
      return '通知权限未开启：请在系统设置里允许「增肌管理」发送通知';
    }
    await _plugin.show(
      9999,
      '测试通知：通知功能正常',
      '收到这条说明提醒链路通了。手表要同步的话，'
          '请在手表对应的手机 App（运动健康/小米运动健康等）'
          '的应用通知列表里允许「增肌管理」。',
      NotificationDetails(android: _android),
    );
    return '测试通知已发出，请留意状态栏和手表';
  }

  /// 单个提醒的调度：优先精确闹钟；无权限时降级 inexact 并记录，
  /// 由 [reschedule] 统一拉起一次授权页（Android 12 及以下才会遇到）。
  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required DateTimeComponents match,
  }) async {
    final details = NotificationDetails(android: _android);
    try {
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarm_permission_not_granted') rethrow;
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      _exactDeniedOnce = true;
    }
  }

  bool _exactDeniedOnce = false;

  /// 按 settings 重排所有提醒。settings 值为 '0'/'1' 与 'HH:mm'。
  Future<void> reschedule(Map<String, String> s) async {
    await init();
    await cancelAll();
    _exactDeniedOnce = false;

    // 1) 体重提醒（每日）
    if (s['notifyWeightEnabled'] == '1') {
      final t = _parseTime(s['notifyWeightTime'], AppConfig.notifyWeightTime);
      await _schedule(
        id: 1001,
        title: '该称体重啦',
        body: '晨起空腹称重更准，点按记录今日体重。',
        when: _nextInstance(t.$1, t.$2),
        match: DateTimeComponents.time,
      );
    }

    // 2) 训练提醒（每日；休息日用户自行忽略）
    if (s['notifyWorkoutEnabled'] == '1') {
      final t = _parseTime(s['notifyWorkoutTime'], AppConfig.notifyWorkoutTime);
      await _schedule(
        id: 1002,
        title: '训练时间到',
        body: '按排期完成今天的训练动作，保持渐进超负荷。',
        when: _nextInstance(t.$1, t.$2),
        match: DateTimeComponents.time,
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
        await _schedule(
          id: 1100 + i,
          title: '喝水打卡',
          body: '来一杯水，向 ${AppConfig.waterGoalCups} 杯目标迈进。',
          when: _nextInstance(times[i].$1, times[i].$2),
          match: DateTimeComponents.time,
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
      await _schedule(
        id: 1003,
        title: '每周复盘',
        body: '生成一次本周总结，看看体重节奏和训练容量。',
        when: t,
        match: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    // 有提醒降级成了 inexact（= 缺精确闹钟权限）→ 拉起一次系统授权页。
    // Android 13+ 声明了 USE_EXACT_ALARM 自动授予，不会走到这；
    // Android 12 设备只在真正用到提醒时弹一次。
    if (_exactDeniedOnce) {
      try {
        await _androidPlugin()?.requestExactAlarmsPermission();
      } catch (_) {/* 用户拒绝/页面不可用则保持 inexact */}
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
