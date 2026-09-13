/// 应用层 Provider 集合（ARCHITECTURE F03 + F04）
/// 全部手写 Provider，不引入 riverpod_generator / freezed。
///
/// 设计原则：
///   - 私有 Future：ref.read(...) 后取 Future.value
///   - 暴露统一的 FutureProvider 给 UI 层 await
library;

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/calc/calc.dart';
import '../../domain/plan/plan.dart';
import 'database_provider.dart';

// ════════════════════════════════════════════════════════════════════
//  通用工具
// ════════════════════════════════════════════════════════════════════

/// 当下日期 yyyy-MM-dd（业务入口，供 today_*_provider 用）。
final todayStringProvider = Provider<String>((ref) {
  final now = DateTime.now();
  return '${_p4(now.year)}-${_p2(now.month)}-${_p2(now.day)}';
});

String _p2(int n) => n < 10 ? '0$n' : '$n';
String _p4(int n) => n < 10 ? '0$n' : '$n';

/// 本周一（yyyy-MM-dd）。
final mondayOfTodayProvider = Provider<String>((ref) {
  final today = ref.watch(todayStringProvider);
  final d = DateTime.parse(today);
  // weekday: 1=Mon, 7=Sun → offset to Mon
  final offset = (d.weekday + 6) % 7;
  final monday = d.subtract(Duration(days: offset));
  return '${_p4(monday.year)}-${_p2(monday.month)}-${_p2(monday.day)}';
});

// ════════════════════════════════════════════════════════════════════
//  基础表读
// ════════════════════════════════════════════════════════════════════

/// 当前 profile（默认取第一行；空则 null）。
final profileProvider = FutureProvider<ProfileData?>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final rows = await db.select(db.profiles).get();
  if (rows.isEmpty) return null;
  return rows.first;
});

/// 当前 profile（stream 版本，DB 变更时自动重建）。
final profileStreamProvider = StreamProvider<ProfileData?>((ref) {
  final db = ref.watch(databaseReadyProvider).requireValue;
  return db.select(db.profiles).watchSingleOrNull();
});

/// 当前 goal（取第一行）。
final goalProvider = FutureProvider<GoalData?>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final rows = await db.select(db.goals).get();
  if (rows.isEmpty) return null;
  return rows.first;
});

/// 当前 goal（stream 版）。
final goalStreamProvider = StreamProvider<GoalData?>((ref) {
  final db = ref.watch(databaseReadyProvider).requireValue;
  return db.select(db.goals).watchSingleOrNull();
});

/// 全部 weight points（按 date 升序）。
final weightPointsProvider = FutureProvider<List<WeightPointData>>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final q = db.select(db.weightPoints)
    ..orderBy([(t) => OrderingTerm.asc(t.date)]);
  return q.get();
});

/// 全部 exercises（升序按 orderWeight）。
final exercisesProvider = FutureProvider<List<ExerciseData>>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final q = db.select(db.exercises)
    ..orderBy([(t) => OrderingTerm.asc(t.orderWeight)]);
  return q.get();
});

/// exercises stream（用于「重新生成计划」后的即时反映）。
final exercisesStreamProvider = StreamProvider<List<ExerciseData>>((ref) {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final q = db.select(db.exercises)
    ..orderBy([(t) => OrderingTerm.asc(t.orderWeight)]);
  return q.watch();
});

/// 今日 food logs。
final todayFoodLogsProvider = FutureProvider<List<FoodLogData>>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final today = ref.watch(todayStringProvider);
  final q = db.select(db.foodLogs)
    ..where((t) => t.date.equals(today))
    ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
  return q.get();
});

/// 今日 habits（可能 null）。
final todayHabitsProvider = FutureProvider<HabitData?>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final today = ref.watch(todayStringProvider);
  final q = db.select(db.habits)..where((t) => t.date.equals(today));
  return q.getSingleOrNull();
});

/// 全部 AppSettings（map 形式）。
final appSettingsProvider = FutureProvider<Map<String, String>>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final all = await db.select(db.appSettings).get();
  return {for (final r in all) r.key: r.value};
});

/// 今日训练 session 状态（取最近一场含 plan code 的）。
final todayTrainingSessionStreamProvider =
    StreamProvider<TrainingSessionData?>((ref) {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final today = ref.watch(todayStringProvider);
  final q = db.select(db.trainingSessions)
    ..where((t) => t.date.equals(today))
    ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
  return q.watchSingleOrNull();
});

// ════════════════════════════════════════════════════════════════════
//  派生：今日总摄入
// ════════════════════════════════════════════════════════════════════

class TodayIntake {
  final double kcal;
  final double p;
  final double c;
  final double f;
  const TodayIntake({
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
  });
  static const empty = TodayIntake(kcal: 0, p: 0, c: 0, f: 0);
}

final todayIntakeProvider = Provider<TodayIntake>((ref) {
  final logs = ref.watch(todayFoodLogsProvider).when(
        data: (v) => v,
        loading: () => const <FoodLogData>[],
        error: (_, __) => const <FoodLogData>[],
      );
  var k = 0.0, p = 0.0, c = 0.0, f = 0.0;
  for (final l in logs) {
    k += l.kcal;
    p += l.p;
    c += l.c;
    f += l.f;
  }
  return TodayIntake(kcal: k, p: p, c: c, f: f);
});

// ════════════════════════════════════════════════════════════════════
//  派生：resolved goal（kcal/p/c/f 显示用）
// ════════════════════════════════════════════════════════════════════

class ResolvedGoalView {
  final double kcal;
  final double protein;
  final double carb;
  final double fat;
  final double rate;
  const ResolvedGoalView({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.rate,
  });

  static const empty = ResolvedGoalView(
    kcal: 2870,
    protein: 110,
    carb: 460,
    fat: 65,
    rate: 0.25,
  );
}

/// 单一出口：任何页面的「目标热量」都来自这里。
final resolvedGoalProvider = Provider<ResolvedGoalView>((ref) {
  final p = ref.watch(profileStreamProvider).when(
        data: (v) => v,
        loading: () => null,
        error: (_, __) => null,
      );
  final g = ref.watch(goalStreamProvider).when(
        data: (v) => v,
        loading: () => null,
        error: (_, __) => null,
      );
  final currentKg = g?.currentWeightKg ?? 62.0;

  if (p == null || g == null) {
    // 引导期/无 profile：用 62kg 男 25 岁 175cm 1.55 活动系数兜底
    return const ResolvedGoalView(
      kcal: 2870, protein: 110, carb: 460, fat: 65, rate: 0.25,
    );
  }

  // 走现成的 calc 逻辑
  final profileMap = <String, dynamic>{
    'sex': p.sex,
    'age': p.age,
    'heightCm': p.heightCm,
    'scene': p.scene,
    'equipment': AppDatabase.decodeStrList(p.equipmentJson),
    'daysPerWeek': p.daysPerWeek,
    'activityFactor': p.activityFactor,
    'activityFactorLocked': p.activityFactorLocked,
    'onboardingDone': p.onboardingDone,
  };
  final goalMap = <String, dynamic>{
    'kcalMode': g.kcalMode,
    'kcalManual': g.kcalManual,
    'kcalAutoOffset': g.kcalAutoOffset,
    'proteinMode': g.proteinMode,
    'proteinManual': g.proteinManual,
    'carbMode': g.carbMode,
    'carbManual': g.carbManual,
    'fatMode': g.fatMode,
    'fatManual': g.fatManual,
    'rateMode': g.rateMode,
    'rateManual': g.rateManual,
    'surplusKcal': g.surplusKcal,
    'lastWeightUsed': g.lastWeightUsed,
  };
  final resolved = resolveGoal(profileMap, currentKg, goalMap);
  return ResolvedGoalView(
    kcal: (resolved.kcal as num).toDouble(),
    protein: (resolved.protein as num).toDouble(),
    carb: (resolved.carb as num).toDouble(),
    fat: (resolved.fat as num).toDouble(),
    rate: resolved.rate,
  );
});

// ════════════════════════════════════════════════════════════════════
//  派生：plan（从 AppSettings.key='plan' 的 JSON 反序列化）
// ════════════════════════════════════════════════════════════════════

/// 单日 plan + 周排期（与 plan_generation.dart 中的 PlanDay 一致）。
class StoredPlan {
  final List<PlanDay> days;
  final Map<int, String> pattern; // 1..7 → code
  const StoredPlan({required this.days, required this.pattern});

  static const empty = StoredPlan(days: [], pattern: {});

  bool get isEmpty => days.isEmpty;

  /// 对齐 prototype 行为：plan.days 为空时也算「未生成」。
  factory StoredPlan.fromAppSettingsValue(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final days = <PlanDay>[];
      for (final d
          in (m['days'] as List<dynamic>? ?? const <dynamic>[])) {
        final dm = Map<String, dynamic>.from(d as Map);
        final entries = <PlanEntry>[];
        for (final e in (dm['entries'] as List<dynamic>? ??
            const <dynamic>[])) {
          final em = Map<String, dynamic>.from(e as Map);
          entries.add(PlanEntry(
            sortOrder: (em['sortOrder'] as num).toInt(),
            exerciseId: em['exerciseId'] as String,
            targetSets: (em['targetSets'] as num).toInt(),
            repLow: em['repLow'] as num,
            repHigh: em['repHigh'] as num,
          ));
        }
        days.add(PlanDay(
          code: dm['code'] as String,
          name: dm['name'] as String,
          entries: entries,
          estMinutes: (dm['estMinutes'] as num).toInt(),
        ));
      }
      final pattern = <int, String>{};
      ((m['pattern'] as Map<dynamic, dynamic>?) ?? const {})
          .forEach((k, v) => pattern[(k as num).toInt()] = v as String);
      return StoredPlan(days: days, pattern: pattern);
    } catch (_) {
      return empty;
    }
  }

  Map<String, dynamic> toJson() => {
        'days': days.map((d) {
          return {
            'code': d.code,
            'name': d.name,
            'estMinutes': d.estMinutes,
            'entries': d.entries
                .map((e) => {
                      'sortOrder': e.sortOrder,
                      'exerciseId': e.exerciseId,
                      'targetSets': e.targetSets,
                      'repLow': e.repLow,
                      'repHigh': e.repHigh,
                    })
                .toList(),
          };
        }).toList(),
        'pattern': pattern,
      };

  /// 适配 generatePlan/getTodayPlan 的 PlanOutput（一次性转换）。
  PlanOutput toPlanOutput() => PlanOutput(days: days, pattern: _patternAdapter());

  /// WeekPattern 适配器（Map<int,String> → WeekPattern）
  WeekPattern _patternAdapter() {
    String at(int i) => pattern[i] ?? '';
    return WeekPattern(at(1), at(2), at(3), at(4), at(5), at(6), at(7));
  }
}

/// 当前 plan（从 AppSettings 读）。
final planProvider = Provider<StoredPlan>((ref) {
  final settings = ref.watch(appSettingsProvider).when(
        data: (v) => v,
        loading: () => <String, String>{},
        error: (_, __) => <String, String>{},
      );
  return StoredPlan.fromAppSettingsValue(settings['plan']);
});
