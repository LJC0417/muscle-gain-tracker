/// 训练历史 / 体重历史 Provider（P-05 prefill、P-06 PR、P-08 趋势）
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/plan/plan.dart';
import 'app_providers.dart';
import 'database_provider.dart';

/// 体重点流（DB 变化自动刷新，趋势图/体重卡用）。
final weightPointsStreamProvider =
    StreamProvider<List<WeightPointData>>((ref) {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final q = db.select(db.weightPoints)
    ..orderBy([(t) => OrderingTerm.asc(t.date)]);
  return q.watch();
});

/// 全部已完成训练（含各组），供 prefillSet / lastPerformance / 统计用。
/// UI 写入 session 后 invalidate 本 provider。
final allSessionsProvider =
    FutureProvider<List<TrainingSession>>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final sessions = await (db.select(db.trainingSessions)
        ..where((t) => t.status.equals('completed'))
        ..orderBy([
          OrderingTerm.desc(t.date),
          OrderingTerm.desc(t.startedAt),
        ]))
      .get();
  if (sessions.isEmpty) return const <TrainingSession>[];
  final allSets = await db.select(db.workoutSets).get();
  final bySession = <String, List<WorkoutSet>>{};
  for (final s in allSets) {
    bySession.putIfAbsent(s.sessionId, () => []).add(WorkoutSet(
          exerciseId: s.exerciseId,
          weightKg: s.weightKg,
          reps: s.reps,
          isBodyweight: s.isBodyweight,
          volumeKg: s.volumeKg,
        ));
  }
  return [
    for (final s in sessions)
      TrainingSession(
        id: s.id,
        date: s.date,
        startedAt: s.startedAt?.toIso8601String(),
        status: s.status,
        totalVolumeKg: s.totalVolumeKg,
        durationSec: s.durationSec,
        sets: bySession[s.id] ?? const <WorkoutSet>[],
      ),
  ];
});

/// 某动作的历史 PR 基线（从全部组聚合，排除 excludeSessionId）。
PrHistory prHistoryFor(
  List<TrainingSession> sessions,
  String exerciseId, {
  String? excludeSessionId,
}) {
  var bestW = 0.0, bestVol = 0.0, bestE1rm = 0.0;
  for (final s in sessions) {
    if (excludeSessionId != null && s.id == excludeSessionId) continue;
    for (final st in s.sets) {
      if (st.exerciseId != exerciseId) continue;
      final w = st.weightKg.toDouble();
      final vol = setVolume(st.weightKg, st.reps, st.isBodyweight).toDouble();
      final e = e1RM(st.weightKg, st.reps).toDouble();
      if (w > bestW) bestW = w;
      if (vol > bestVol) bestVol = vol;
      if (e > bestE1rm) bestE1rm = e;
    }
  }
  return PrHistory(
    bestWeightKg: bestW,
    bestSingleVolume: bestVol,
    bestEst1Rm: bestE1rm,
  );
}

/// 某范围（yyyy-MM-dd from..to）内的已完成 session。
Future<List<TrainingSessionData>> sessionsInRange(
  AppDatabase db,
  String from,
  String to,
) {
  return (db.select(db.trainingSessions)
        ..where((t) => t.date.isBetweenValues(from, to))
        ..where((t) => t.status.equals('completed'))
        ..orderBy([(t) => OrderingTerm.desc(t.date)]))
      .get();
}

/// 今日体重（null = 今天还没称）。
final todayWeightProvider = FutureProvider<WeightPointData?>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final today = ref.watch(todayStringProvider);
  final q = db.select(db.weightPoints)..where((t) => t.date.equals(today));
  return q.getSingleOrNull();
});

/// 今日体重相对上一次记录的变化（kg，今天有记录才算）。
final weightDeltaProvider = FutureProvider<double?>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final today = ref.watch(todayStringProvider);
  final q = db.select(db.weightPoints)
    ..orderBy([(t) => OrderingTerm.asc(t.date)]);
  final rows = await q.get();
  var idx = -1;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].date == today) {
      idx = i;
      break;
    }
  }
  if (idx <= 0) return null;
  return (rows[idx].kg - rows[idx - 1].kg).toDouble();
});
