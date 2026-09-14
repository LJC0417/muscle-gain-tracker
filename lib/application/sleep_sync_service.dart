/// Health Connect 睡眠同步（vivo 健康 → Health Connect → 本应用）。
///
/// 链路：手表 → vivo 健康 App（需用户在 vivo 健康里打开「数据共享 → Health Connect」）
///       → Health Connect（系统中间层）→ 本插件读取 → 落库。
/// 权限：睡眠阶段 + 心率 + 呼吸率 + 血氧；HRV（RMSSD）单独防御式申请，
///       部分机型/插件版本不支持时静默跳过（UI 显示无数据）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:health/health.dart';

import '../data/database.dart';

/// 同步结果（UI 提示用）。
class SleepSyncReport {
  final int nights; // 本次写入的晚数
  final bool hrvSupported; // HRV 是否可用
  final String? error; // 非 null = 同步失败

  const SleepSyncReport({
    required this.nights,
    required this.hrvSupported,
    this.error,
  });
}

class SleepSyncService {
  SleepSyncService._();
  static final instance = SleepSyncService._();

  final Health _health = Health();
  bool _configured = false;

  /// 睡眠阶段类型（Health Connect 的 SleepStage 逐段返回）。
  static const List<HealthDataType> _stageTypes = [
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP, // 未细分 → 按浅睡计
  ];

  /// 体征类型。
  static const List<HealthDataType> _metricTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.BLOOD_OXYGEN,
  ];

  static const HealthDataType _hrvType =
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  bool _hrvGranted = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _health.configure();
    } catch (_) {
      // 老版本插件无 configure，忽略
    }
    _configured = true;
  }

  Future<bool> _authorize(List<HealthDataType> types) async {
    try {
      return await _health.requestAuthorization(types);
    } catch (_) {
      return false;
    }
  }

  /// 申请 Health Connect 权限。返回是否至少拿到睡眠数据权限。
  Future<bool> requestPermissions() async {
    await _ensureConfigured();
    final main = await _authorize([..._stageTypes, ..._metricTypes]);
    // HRV 防御式申请：不支持的平台会抛异常或拒绝，不影响主流程
    _hrvGranted = await _authorize([_hrvType]);
    return main;
  }

  /// 是否已授权（静默检查，不弹窗）。
  Future<bool> hasPermissions() async {
    await _ensureConfigured();
    try {
      return await _health.hasPermissions([..._stageTypes, ..._metricTypes]) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 同步最近 [days] 天的睡眠（含今晚在睡的，按起床日归组）。
  Future<SleepSyncReport> sync(AppDatabase db, {int days = 4}) async {
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final start =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: days));

      final stagePoints = await _health.getHealthDataFromTypes(
          types: _stageTypes, startTime: start, endTime: now);

      // 按起床日归组：阶段段的「结束时刻」落在哪天就归哪天（睡眠段结束于清晨）
      final groups = <DateTime, List<HealthDataPoint>>{};
      for (final p in stagePoints) {
        final wake =
            DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
        groups.putIfAbsent(wake, () => []).add(p);
      }

      // 体征点一次拉回，再按各晚会话窗口过滤
      final metricPoints = <HealthDataType, List<HealthDataPoint>>{};
      final metricTypes = [
        ..._metricTypes,
        if (_hrvGranted) _hrvType,
      ];
      for (final t in metricTypes) {
        try {
          metricPoints[t] = await _health.getHealthDataFromTypes(
              types: [t], startTime: start, endTime: now);
        } catch (_) {
          metricPoints[t] = const [];
        }
      }

      var nights = 0;
      for (final entry in groups.entries) {
        final dateKey = _fmt(entry.key);
        final segs = entry.value..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
        if (segs.isEmpty) continue;
        final bedStart = segs.first.dateFrom;
        final bedEnd = segs.last.dateTo;

        // 覆盖旧数据
        await (db.delete(db.sleepSessions)
              ..where((t) => t.date.equals(dateKey)))
            .go();
        await (db.delete(db.sleepStageRows)
              ..where((t) => t.date.equals(dateKey)))
            .go();
        await (db.delete(db.sleepMetrics)
              ..where((t) => t.date.equals(dateKey)))
            .go();

        await db.into(db.sleepSessions).insert(SleepSessionsCompanion.insert(
              date: dateKey,
              bedtimeStart: bedStart,
              bedtimeEnd: bedEnd,
              updatedAt: Value(DateTime.now()),
            ));
        for (final p in segs) {
          final stage = _stageOf(p.type);
          if (stage == null) continue;
          await db.into(db.sleepStageRows).insert(
              SleepStageRowsCompanion.insert(
                  date: dateKey,
                  stage: stage,
                  startAt: p.dateFrom,
                  endAt: p.dateTo));
        }

        // 体征聚合
        double? avgHr, minHr, maxHr, resp, spo2Avg, spo2Min, hrv;
        final hrVals = _numericIn(metricPoints[HealthDataType.HEART_RATE] ?? const [], bedStart, bedEnd);
        if (hrVals.isNotEmpty) {
          avgHr = hrVals.reduce((a, b) => a + b) / hrVals.length;
          minHr = hrVals.reduce((a, b) => a < b ? a : b);
          maxHr = hrVals.reduce((a, b) => a > b ? a : b);
        }
        final respVals = _numericIn(metricPoints[HealthDataType.RESPIRATORY_RATE] ?? const [], bedStart, bedEnd);
        if (respVals.isNotEmpty) {
          resp = respVals.reduce((a, b) => a + b) / respVals.length;
        }
        final spo2Vals = _numericIn(metricPoints[HealthDataType.BLOOD_OXYGEN] ?? const [], bedStart, bedEnd);
        if (spo2Vals.isNotEmpty) {
          spo2Avg = spo2Vals.reduce((a, b) => a + b) / spo2Vals.length;
          spo2Min = spo2Vals.reduce((a, b) => a < b ? a : b);
        }
        if (_hrvGranted) {
          final hrvVals = _numericIn(metricPoints[_hrvType] ?? const [], bedStart, bedEnd);
          if (hrvVals.isNotEmpty) {
            hrv = hrvVals.reduce((a, b) => a + b) / hrvVals.length;
          }
        }
        if (avgHr != null || resp != null || spo2Avg != null || hrv != null) {
          await db.into(db.sleepMetrics).insert(
                SleepMetricsCompanion.insert(
                  date: dateKey,
                  avgHr: Value(avgHr),
                  minHr: Value(minHr),
                  maxHr: Value(maxHr),
                  respirationRate: Value(resp),
                  spo2Avg: Value(spo2Avg),
                  spo2Min: Value(spo2Min),
                  hrvMs: Value(hrv),
                  updatedAt: Value(DateTime.now()),
                ),
              );
        }
        nights++;
      }
      return SleepSyncReport(nights: nights, hrvSupported: _hrvGranted);
    } catch (e) {
      return SleepSyncReport(nights: 0, hrvSupported: false, error: '$e');
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<double> _numericIn(
      List<HealthDataPoint> points, DateTime from, DateTime to) {
    final out = <double>[];
    for (final p in points) {
      if (p.dateFrom.isBefore(from) || p.dateTo.isAfter(to)) continue;
      final v = p.value;
      if (v is NumericHealthValue) out.add(v.numericValue.toDouble());
    }
    return out;
  }

  static String? _stageOf(HealthDataType t) {
    switch (t) {
      case HealthDataType.SLEEP_DEEP:
        return 'deep';
      case HealthDataType.SLEEP_LIGHT:
        return 'light';
      case HealthDataType.SLEEP_REM:
        return 'rem';
      case HealthDataType.SLEEP_AWAKE:
        return 'awake';
      case HealthDataType.SLEEP_ASLEEP:
        return 'light'; // 未细分的 asleep 按浅睡计
      default:
        return null;
    }
  }
}
