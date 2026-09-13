/// 训练历史查询（ARCHITECTURE 2.12 / A12 / R-29 / R-30）
///   lastPerformance    — 该动作最近一次的所有组（按 date + startedAt 降序）
///   prefillSet         — 组预填（第 1 组用上次成绩，第 N 组用上一组）
///   compareBadge       — 与参考组对比（↑/↓/持平/首次）
///   rolling7TrainingStats — 近 7 天训练统计
import '../../core/constants/app_config.dart';
import '../calc/calc.dart';
import 'plan_metrics.dart';

/// 一场训练（精简字段，与 JS 版的 allSessions[i] 对齐）。
class TrainingSession {
  final String id;
  final String date;
  final String? startedAt;
  final String status; // 'ongoing' | 'completed' | 'abandoned'
  final num? totalVolumeKg;
  final num? durationSec;
  final List<WorkoutSet> sets;
  const TrainingSession({
    required this.id,
    required this.date,
    required this.startedAt,
    required this.status,
    required this.totalVolumeKg,
    required this.durationSec,
    required this.sets,
  });
}

/// 单组预填结果。
class PrefillSetResult {
  final num weight;
  final num reps;
  const PrefillSetResult(this.weight, this.reps);
}

/// 上次该动作的所有组（按 setIndex 升序）。
/// `beforeSessionId` 不为空时排除该 session。
List<WorkoutSet> lastPerformance(
  List<TrainingSession> allSessions,
  String exerciseId, {
  String? beforeSessionId,
}) {
  final list = allSessions.where((s) {
    if (beforeSessionId != null && s.id == beforeSessionId) return false;
    return s.sets.any((x) => x.exerciseId == exerciseId);
  }).toList();
  if (list.isEmpty) return <WorkoutSet>[];
  list.sort((a, b) {
    final d = a.date.compareTo(b.date);
    if (d != 0) return d > 0 ? -1 : 1;
    return (b.startedAt ?? '').compareTo(a.startedAt ?? '');
  });
  final latest = list.first;
  // JS 用 setIndex 排序；WorkoutSet 没有 setIndex，由业务侧在写入时按序排列
  return latest.sets.where((x) => x.exerciseId == exerciseId).toList();
}

/// 组预填（setIndex 1-based）：
///   - setIndex == 1 → 用上次第一组（无则 fallback 默认）
///   - setIndex > 1  → 用 currentSets[setIndex-2]（上一组）
PrefillSetResult prefillSet(
  List<TrainingSession> allSessions,
  String exerciseId,
  int setIndex,
  List<WorkoutSet> currentSets, {
  String? currentSessionId,
}) {
  final fallback = PrefillSetResult(
    AppConfig.defaultWeightKg,
    AppConfig.defaultReps,
  );
  if (setIndex <= 1) {
    final last = lastPerformance(allSessions, exerciseId, beforeSessionId: currentSessionId);
    if (last.isNotEmpty) {
      return PrefillSetResult(last.first.weightKg, last.first.reps);
    }
    return fallback;
  }
  if (setIndex - 2 < currentSets.length) {
    final prev = currentSets[setIndex - 2];
    return PrefillSetResult(prev.weightKg, prev.reps);
  }
  return fallback;
}

/// 与参考组对比（badge 文案 + tone）。
/// tone: 'good' / 'neutral' / 'muted'
({String text, String tone}) compareBadge(WorkoutSet cur, WorkoutSet? ref) {
  if (ref == null) return (text: '首次', tone: 'neutral');
  final dKg = R.r1(cur.weightKg - ref.weightKg);
  final dRep = cur.reps - ref.reps;
  if (dKg > 0) return (text: '↑ +${dKg.toStringAsFixed(1)} kg', tone: 'good');
  if (dKg == 0 && dRep > 0) return (text: '↑ +${dRep.toInt()} 次', tone: 'good');
  if (dKg < 0 || (dKg == 0 && dRep < 0)) return (text: '↓', tone: 'muted');
  return (text: '持平', tone: 'neutral');
}

/// 近 7 天训练统计（滚动窗口）。
class Rolling7Stats {
  final int count;
  final num totalVolumeKg;
  final num avgDurationSec;
  const Rolling7Stats({
    required this.count,
    required this.totalVolumeKg,
    required this.avgDurationSec,
  });
}

Rolling7Stats rolling7TrainingStats(
  ({String from, String to}) range,
  List<TrainingSession> sessions,
) {
  final from = range.from;
  final to = range.to;
  final done = sessions
      .where((s) => s.status == 'completed' && s.date.compareTo(from) >= 0 && s.date.compareTo(to) <= 0)
      .toList();
  final count = done.length;
  var total = num.zero;
  var durSum = num.zero;
  for (final s in done) {
    total += s.totalVolumeKg ?? 0;
    durSum += s.durationSec ?? 0;
  }
  return Rolling7Stats(
    count: count,
    totalVolumeKg: R.r1(total),
    avgDurationSec: count > 0 ? R.r0(durSum / count) : 0,
  );
}
