/// 本地 AI 周报（P-09 / AI-WEEKLY-REVIEW-SPEC 的 v1 模板实现）
/// 专业口吻、零成本、无网络；与 prototype pages/app.js 的 MG.advisor.weeklyReview 逐行对齐。
library;

import 'package:drift/drift.dart' show Value;

import '../core/constants/app_config.dart';
import '../data/database.dart';
import '../domain/calc/calc.dart';
import '../domain/plan/plan.dart';
import 'providers/app_providers.dart' show ResolvedGoalView;

class WeeklyReviewResult {
  final String text;
  final String weekStart;
  final String weekEnd;
  final String trend; // slow | onTrack | fast | unknown
  final double? thisWeekAvg;
  final double? prevWeekAvg;
  final double? delta;
  final int avgKcal;
  final int avgP;
  final int trainCount;
  final double volume;
  const WeeklyReviewResult({
    required this.text,
    required this.weekStart,
    required this.weekEnd,
    required this.trend,
    required this.thisWeekAvg,
    required this.prevWeekAvg,
    required this.delta,
    required this.avgKcal,
    required this.avgP,
    required this.trainCount,
    required this.volume,
  });
}

/// 把 DB 行转成 calc 需要的轻量体重点。
List<WeightPointLite> _toLite(Iterable<WeightPointData> rows) =>
    [for (final r in rows) WeightPointLite(r.date, r.kg)];

WeeklyReviewResult buildWeeklyReview({
  required String today,
  required List<WeightPointData> weights,
  required List<FoodLogData> foodLogs,
  required List<TrainingSession> sessions,
  required ResolvedGoalView goal,
  List<HabitData> habits = const [],
  double? currentWeightKg,
}) {
  final lite = _toLite(weights);
  final monday = D.mondayOf(today);
  final thisWeek = weekAvg(lite, monday);
  final prevWeek = weekAvg(lite, D.addDays(monday, -7));
  final d = delta(thisWeek, prevWeek);
  final trend = trendStatus(d, goal.rate);
  final trendLabel = AppConfig.labels[trend] ?? '数据不足';

  final range = rangeOf('week', today, null);
  final logs = foodLogs
      .where((l) => l.date.compareTo(range.from) >= 0 && l.date.compareTo(range.to) <= 0)
      .toList();
  final daySet = <String>{};
  var sumK = 0.0, sumP = 0.0;
  for (final l in logs) {
    daySet.add(l.date);
    sumK += l.kcal;
    sumP += l.p;
  }
  final dayCount = daySet.isEmpty ? 1 : daySet.length;
  final avgKcal = (sumK / dayCount).round();
  final avgP = (sumP / dayCount).round();

  final tStats = rolling7TrainingStats(range, sessions);

  final parts = <String>[];
  if (thisWeek != null && prevWeek != null) {
    parts.add('本周你的体重 7 日均线落在 ${thisWeek.toStringAsFixed(2)} kg，'
        '较上周 ${prevWeek.toStringAsFixed(2)} kg 变化 '
        '${d == null ? '—' : (d >= 0 ? '+' : '') + d.toStringAsFixed(2)} kg，'
        '整体节奏「$trendLabel」。');
  } else if (currentWeightKg != null) {
    parts.add('本周体重记录还不完整；当前体重 ${currentWeightKg.toStringAsFixed(1)} kg。'
        '建议每天晨起空腹称重，数据足够后才能评估增重节奏。');
  } else {
    parts.add('还没有体重记录。先连续记录 3 天以上，我才能给出节奏评估。');
  }
  parts.add('饮食侧日均摄入约 $avgKcal kcal，距目标 ${goal.kcal.toInt()} kcal'
      '${avgKcal >= goal.kcal * 0.9 ? '已贴近' : '尚有缺口'}；'
      '蛋白日均 $avgP g（目标 ${goal.protein.toInt()} g）'
      '${avgP >= goal.protein * 0.9 ? '基本到位' : '建议再补'}。');
  if (tStats.count > 0) {
    parts.add('本周完成 ${tStats.count} 次训练，累计容量 ${tStats.totalVolumeKg.toStringAsFixed(1)} kg，'
        '平均单次 ${(tStats.avgDurationSec / 60).round()} 分钟。');
  } else {
    parts.add('本周暂无训练记录，建议按排期补齐频率，循序渐进才能稳定增肌。');
  }

  // 睡眠（打卡记录；sleepHours<=0 视为未记录）
  final sleepRows = [
    for (final h in habits)
      if (h.date.compareTo(range.from) >= 0 &&
          h.date.compareTo(range.to) <= 0 &&
          h.sleepHours > 0)
        h,
  ];
  if (sleepRows.isNotEmpty) {
    final sleepAvg = sleepRows.map((h) => h.sleepHours).reduce((a, b) => a + b) /
        sleepRows.length;
    parts.add(sleepAvg < 7
        ? '睡眠周均 ${sleepAvg.toStringAsFixed(1)} 小时（${sleepRows.length}/7 天记录），'
            '低于 7 小时——恢复不足时体重不涨未必是吃不够，优先补觉。'
        : '睡眠周均 ${sleepAvg.toStringAsFixed(1)} 小时（${sleepRows.length}/7 天记录），恢复状态良好。');
  }

  final String advice;
  if (trend == 'slow') {
    advice = '体重节奏偏慢，下周可把每日热量上调约 ${AppConfig.adjustStepKcal.toInt()} kcal，'
        '并优先保证蛋白吃满；训练维持当前容量，避免虚耗。';
  } else if (trend == 'fast') {
    advice = '体重偏快，提示脂肪占比可能偏高，下周把每日热量下调约 '
        '${AppConfig.adjustStepKcal.toInt()} kcal，训练容量保持不变即可。';
  } else {
    advice = '节奏正好，下周保持训练频率与热量不变，把动作质量做扎实，形体就在按预期推进。';
  }
  parts.add(advice);
  parts.add('坚持记录体重与饮食，数据会替你说话——下一周见。');

  return WeeklyReviewResult(
    text: parts.join('\n'),
    weekStart: monday,
    weekEnd: D.addDays(monday, 6),
    trend: trend,
    thisWeekAvg: thisWeek,
    prevWeekAvg: prevWeek,
    delta: d,
    avgKcal: avgKcal,
    avgP: avgP,
    trainCount: tStats.count,
    volume: tStats.totalVolumeKg.toDouble(),
  );
}

/// 把生成结果落库（WeeklyReviews，weekStart 主键，重复生成覆盖）。
Future<void> saveWeeklyReview(AppDatabase db, WeeklyReviewResult r) async {
  await db.into(db.weeklyReviews).insertOnConflictUpdate(
        WeeklyReviewsCompanion.insert(
          weekStart: r.weekStart,
          weekEnd: r.weekEnd,
          trendStatus: r.trend,
          summary: r.text,
          weightDeltaKg: Value(r.delta),
          createdAt: DateTime.now(),
        ),
      );
}
