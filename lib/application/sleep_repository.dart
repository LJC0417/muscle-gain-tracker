/// 睡眠仓储：DB 行 ↔ SleepDay 模型。
library;

import '../data/database.dart';
import 'sleep_models.dart';

/// 读一晚睡眠（无数据返回 null）。
Future<SleepDay?> loadSleepDay(AppDatabase db, String date) async {
  final session = await (db.select(db.sleepSessions)
        ..where((t) => t.date.equals(date)))
      .getSingleOrNull();
  if (session == null) return null;

  final stageRows = await (db.select(db.sleepStageRows)
        ..where((t) => t.date.equals(date)))
      .get();
  final metric = await (db.select(db.sleepMetrics)
        ..where((t) => t.date.equals(date)))
      .getSingleOrNull();

  // 相对分钟：以入床日 0 点为基准（23:00 = 1380，次日 07:00 = 1860）
  final base = DateTime(session.bedtimeStart.year, session.bedtimeStart.month,
      session.bedtimeStart.day);
  int rel(DateTime dt) => dt.difference(base).inMinutes;

  final segments = [
    for (final r in stageRows)
      SleepSegment(_stageFromString(r.stage), rel(r.startAt), rel(r.endAt)),
  ]..sort((a, b) => a.startMin.compareTo(b.startMin));

  // 时间轴窗口：入床向下取整点，起床向上取整点（至少覆盖到 07:00 视觉更稳）
  final windowStart = (rel(session.bedtimeStart) ~/ 60) * 60;
  var windowEnd = ((rel(session.bedtimeEnd) + 59) ~/ 60) * 60;
  if (windowEnd - windowStart < 6 * 60) windowEnd = windowStart + 6 * 60;

  return SleepDay(
    date: date,
    windowStartMin: windowStart,
    windowEndMin: windowEnd,
    bedtimeMin: rel(session.bedtimeStart),
    wakeMin: rel(session.bedtimeEnd),
    segments: segments,
    avgHr: metric?.avgHr,
    minHr: metric?.minHr,
    maxHr: metric?.maxHr,
    respirationRate: metric?.respirationRate,
    spo2Avg: metric?.spo2Avg,
    spo2Min: metric?.spo2Min,
    hrvMs: metric?.hrvMs,
  );
}

SleepStage _stageFromString(String s) {
  switch (s) {
    case 'deep':
      return SleepStage.deep;
    case 'rem':
      return SleepStage.rem;
    case 'awake':
      return SleepStage.awake;
    default:
      return SleepStage.light;
  }
}
