/// AI 周报编排（AI-WEEKLY-REVIEW-SPEC 落地实现）
///
/// 链路：周数据 → payload（spec 三节）→ prompt → 云 LLM 流式返回 → 合规过滤（spec 二节黑名单）
///       → 24h 缓存（spec 五节）→ 落库 WeeklyReviews
/// 降级：任何失败（断网 / 超时 / 额度 / 输出不合规）都回落到本地模板，并给出灰字提示，
///       绝不弹错误框、绝不空白（spec 五节 + AI-06）。
///
/// 重要：**所有数字都在调用前从算法层派生好**，不让模型自己算（spec 三节）。
library;

import 'dart:convert';

import '../../core/constants/app_config.dart';
import '../../core/constants/cloud_config.dart';
import '../../data/database.dart';
import '../../domain/calc/calc.dart';
import '../../domain/plan/plan.dart';
import '../providers/app_providers.dart' show ResolvedGoalView;
import '../weekly_review.dart';
import 'ai_review_text.dart';
import 'cloud_llm_client.dart';

/// 生成结果（UI 直接消费）。
class AiReviewOutcome {
  final String text;

  /// true = 云端 AI 生成；false = 本地模板降级
  final bool fromAi;

  /// 降级原因（灰字提示，null=正常）
  final String? note;

  /// 是否命中 24h 缓存
  final bool cached;

  /// 本地口径的 KPI（趋势/数字留档，UI 也要用）
  final WeeklyReviewResult local;

  const AiReviewOutcome({
    required this.text,
    required this.fromAi,
    required this.note,
    required this.cached,
    required this.local,
  });
}

/// 教练人设与输出合规过滤见 `ai_review_text.dart`（纯文本层，零 Flutter 依赖）。

// ════════════════════════════════════════════════════════════════
// payload（spec 三节字段，全部由算法层派生）
// ════════════════════════════════════════════════════════════════

/// 动作亮点（本周最好成绩 vs 上期最好成绩）。
class ExerciseHighlight {
  final String name;
  final double? lastWeight;
  final int? lastReps;
  final double? thisWeekWeight;
  final int? thisWeekReps;
  final String progress; // new | up | same | down

  const ExerciseHighlight({
    required this.name,
    required this.lastWeight,
    required this.lastReps,
    required this.thisWeekWeight,
    required this.thisWeekReps,
    required this.progress,
  });
}

/// 一周的聚合（自然周口径，周一为周始）。
class WeekAggregate {
  final String weekStart;
  final String weekEnd;
  final double? weightAvg;
  final int kcalAvg;
  final int kcalHitDays;
  final int proteinAvg;
  final int proteinHitDays;
  final int trainingCompleted;
  final double totalVolumeKg;
  final int avgSessionMinutes;
  final int loggedDays;

  const WeekAggregate({
    required this.weekStart,
    required this.weekEnd,
    required this.weightAvg,
    required this.kcalAvg,
    required this.kcalHitDays,
    required this.proteinAvg,
    required this.proteinHitDays,
    required this.trainingCompleted,
    required this.totalVolumeKg,
    required this.avgSessionMinutes,
    required this.loggedDays,
  });
}

WeekAggregate aggregateWeek({
  required String weekStart,
  required List<WeightPointData> weights,
  required List<FoodLogData> foodLogs,
  required List<TrainingSession> sessions,
  required ResolvedGoalView goal,
}) {
  final weekEnd = D.addDays(weekStart, 6);
  final lite = <WeightPointLite>[
    for (final w in weights) WeightPointLite(w.date, w.kg),
  ];
  final wAvg = weekAvg(lite, weekStart);

  final byDay = <String, List<FoodLogData>>{};
  for (final l in foodLogs) {
    if (l.date.compareTo(weekStart) < 0 || l.date.compareTo(weekEnd) > 0) {
      continue;
    }
    byDay.putIfAbsent(l.date, () => []).add(l);
  }
  var sumK = 0.0, sumP = 0.0;
  var kHit = 0, pHit = 0;
  for (final entry in byDay.entries) {
    final k = entry.value.fold<double>(0, (a, l) => a + l.kcal);
    final p = entry.value.fold<double>(0, (a, l) => a + l.p);
    sumK += k;
    sumP += p;
    if (k >= goal.kcal * (1 - AppConfig.kcalTolLower) &&
        k <= goal.kcal * (1 + AppConfig.kcalTolUpper)) {
      kHit++;
    }
    if (p >= goal.protein * AppConfig.proteinTol) pHit++;
  }
  final days = byDay.isEmpty ? 1 : byDay.length;

  final done = sessions
      .where((s) =>
          s.status == 'completed' &&
          s.date.compareTo(weekStart) >= 0 &&
          s.date.compareTo(weekEnd) <= 0)
      .toList();
  var volume = 0.0, dur = 0.0;
  for (final s in done) {
    volume += s.totalVolumeKg ?? 0;
    dur += s.durationSec ?? 0;
  }

  return WeekAggregate(
    weekStart: weekStart,
    weekEnd: weekEnd,
    weightAvg: wAvg,
    kcalAvg: (sumK / days).round(),
    kcalHitDays: kHit,
    proteinAvg: (sumP / days).round(),
    proteinHitDays: pHit,
    trainingCompleted: done.length,
    totalVolumeKg: R.r1(volume),
    avgSessionMinutes:
        done.isEmpty ? 0 : R.r0(dur / done.length / 60).toInt(),
    loggedDays: byDay.length,
  );
}

/// 动作亮点：本周最好一组 vs 本周之前的最高重量（最多 4 条）。
List<ExerciseHighlight> buildHighlights({
  required String weekStart,
  required String weekEnd,
  required List<TrainingSession> sessions,
  required List<ExerciseData> exercises,
}) {
  final nameOf = <String, String>{for (final e in exercises) e.id: e.name};
  final before = <String, double>{};
  final thisWeek = <String, List<WorkoutSet>>{};
  for (final s in sessions) {
    if (s.status != 'completed') continue;
    for (final st in s.sets) {
      if (st.weightKg <= 0) continue;
      if (s.date.compareTo(weekStart) >= 0 &&
          s.date.compareTo(weekEnd) <= 0) {
        thisWeek.putIfAbsent(st.exerciseId, () => []).add(st);
      } else if (s.date.compareTo(weekStart) < 0) {
        final cur = before[st.exerciseId];
        if (cur == null || st.weightKg > cur) {
          before[st.exerciseId] = st.weightKg.toDouble();
        }
      }
    }
  }
  final out = <ExerciseHighlight>[];
  for (final entry in thisWeek.entries) {
    WorkoutSet? best;
    for (final st in entry.value) {
      if (best == null ||
          st.weightKg > best.weightKg ||
          (st.weightKg == best.weightKg && st.reps > best.reps)) {
        best = st;
      }
    }
    if (best == null) continue;
    final prev = before[entry.key];
    final progress = prev == null
        ? 'new'
        : (best.weightKg > prev ? 'up' : (best.weightKg == prev ? 'same' : 'down'));
    out.add(ExerciseHighlight(
      name: nameOf[entry.key] ?? entry.key,
      lastWeight: prev,
      lastReps: null,
      thisWeekWeight: best.weightKg.toDouble(),
      thisWeekReps: best.reps.toInt(),
      progress: progress,
    ));
  }
  // 优先报进步/新增，其次按本周重量降序
  out.sort((a, b) {
    int rank(ExerciseHighlight h) => h.progress == 'new'
        ? 0
        : h.progress == 'up'
            ? 1
            : h.progress == 'same'
                ? 2
                : 3;
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return (b.thisWeekWeight ?? 0).compareTo(a.thisWeekWeight ?? 0);
  });
  return out.take(4).toList();
}

/// 组装发给模型的文本（中文、纯文本；不要让模型做算术）。
String buildReviewPrompt({
  required WeekAggregate thisWeek,
  required WeekAggregate lastWeek,
  required ResolvedGoalView goal,
  required ProfileData? profile,
  required GoalData? goalRow,
  required List<WeightPointData> weights,
  required List<ExerciseHighlight> highlights,
  required String trendLabel,
  required double? weightDelta,
}) {
  String f1(double? v) => v == null ? '无记录' : v.toStringAsFixed(1);
  final b = StringBuffer();
  b.writeln('【学员档案】');
  if (profile != null) {
    b.writeln('性别/年龄：${AppConfig.labels[profile.sex] ?? profile.sex} / ${profile.age} 岁');
    b.writeln('身高：${profile.heightCm.toStringAsFixed(0)} cm');
    b.writeln('训练场景：${AppConfig.labels[profile.scene] ?? profile.scene}，每周 ${profile.daysPerWeek} 天');
    b.writeln('活动系数：${profile.activityFactor.toStringAsFixed(2)}');
  } else {
    b.writeln('档案未填写完整');
  }
  if (goalRow != null) {
    b.writeln('初始体重 ${goalRow.startWeightKg.toStringAsFixed(1)} kg → '
        '当前 ${goalRow.currentWeightKg.toStringAsFixed(1)} kg → '
        '目标 ${goalRow.targetWeightKg.toStringAsFixed(1)} kg');
  }
  b.writeln('目标增重速度：${goal.rate.toStringAsFixed(2)} kg/周');
  b.writeln();
  b.writeln('【本周 ${thisWeek.weekStart} ~ ${thisWeek.weekEnd}】');
  b.writeln('体重周均：${f1(thisWeek.weightAvg)} kg；'
      '较上周变化：${weightDelta == null ? '数据不足' : '${weightDelta >= 0 ? '+' : ''}${weightDelta.toStringAsFixed(2)} kg'}；'
      '节奏判定：$trendLabel');
  b.writeln('日均热量：${thisWeek.kcalAvg} kcal（目标 ${goal.kcal.toInt()}，'
      '达标 ${thisWeek.kcalHitDays}/7 天）');
  b.writeln('日均蛋白：${thisWeek.proteinAvg} g（目标 ${goal.protein.toInt()}，'
      '达标 ${thisWeek.proteinHitDays}/7 天）');
  b.writeln('训练：完成 ${thisWeek.trainingCompleted} 次，'
      '总容量 ${thisWeek.totalVolumeKg.toStringAsFixed(1)} kg，'
      '平均单次 ${thisWeek.avgSessionMinutes} 分钟');
  if (thisWeek.loggedDays < 3) {
    b.writeln('提示：本周饮食记录天数偏少（${thisWeek.loggedDays} 天），日均值参考性有限');
  }
  b.writeln();
  b.writeln('【上周对比】');
  b.writeln('体重周均：${f1(lastWeek.weightAvg)} kg；'
      '日均热量 ${lastWeek.kcalAvg} kcal；日均蛋白 ${lastWeek.proteinAvg} g；'
      '训练 ${lastWeek.trainingCompleted} 次，容量 ${lastWeek.totalVolumeKg.toStringAsFixed(1)} kg');
  b.writeln();
  if (highlights.isNotEmpty) {
    b.writeln('【动作进展】');
    for (final h in highlights) {
      final progress = h.progress == 'new'
          ? '本周新练'
          : h.progress == 'up'
              ? '较此前最好成绩有进步'
              : h.progress == 'same'
                  ? '与此前最好成绩持平'
                  : '低于此前最好成绩';
      b.writeln('- ${h.name}：本周最好 '
          '${h.thisWeekWeight?.toStringAsFixed(1)} kg × ${h.thisWeekReps} 次，'
          '此前最高 ${h.lastWeight == null ? '无记录' : '${h.lastWeight!.toStringAsFixed(1)} kg'}，$progress');
    }
  } else {
    b.writeln('【动作进展】本周没有可比较的重量训练记录');
  }
  final weightCount = weights.length;
  b.writeln();
  b.writeln('【累计】体重记录 $weightCount 条。');
  b.writeln();
  b.writeln('请按系统要求写这段周评：一段 90–150 字的中文，先点出这周整体节奏，'
      '再指出最该改的一个具体问题（带数字），最后给出下周一个可执行目标。不要分点、不要 Markdown。');
  return b.toString();
}

// ════════════════════════════════════════════════════════════════
// 缓存与额度（存 AppSettings KV，避免动 DB schema）
// ════════════════════════════════════════════════════════════════

String _cacheKey(String weekStart) => 'aiReview:$weekStart';
String _quotaKey(String today) => 'aiReviewQuota:$today';

Future<String?> _readSetting(AppDatabase db, String key) async {
  final row = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  return row?.value;
}

Future<void> _writeSetting(AppDatabase db, String key, String value) async {
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
}

class _CacheHit {
  final String text;
  final bool fromAi;
  const _CacheHit(this.text, this.fromAi);
}

Future<_CacheHit?> _readCache(AppDatabase db, String weekStart) async {
  final raw = await _readSetting(db, _cacheKey(weekStart));
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final text = j['text'];
    if (at == null || text is! String || text.isEmpty) return null;
    if (DateTime.now().difference(at) > CloudConfig.cacheTtl) return null;
    return _CacheHit(text, j['fromAi'] == true);
  } catch (_) {
    return null;
  }
}

Future<void> _writeCache(
  AppDatabase db,
  String weekStart,
  String text, {
  required bool fromAi,
}) async {
  await _writeSetting(
    db,
    _cacheKey(weekStart),
    jsonEncode({
      'text': text,
      'at': DateTime.now().toIso8601String(),
      'fromAi': fromAi,
    }),
  );
}

/// 记一次调用；超过当日上限返回 -1（不写入）。
Future<int> _bumpQuota(AppDatabase db, String today) async {
  final key = _quotaKey(today);
  final raw = await _readSetting(db, key);
  final used = int.tryParse(raw ?? '0') ?? 0;
  if (used >= CloudConfig.dailyCallLimit) return -1;
  final next = used + 1;
  await _writeSetting(db, key, '$next');
  return next;
}

// ════════════════════════════════════════════════════════════════
// 入口
// ════════════════════════════════════════════════════════════════

/// 生成周报：优先命中 24h 缓存；否则调云端 AI；任何失败回落本地模板。
Future<AiReviewOutcome> generateAiWeeklyReview({
  required AppDatabase db,
  required String today,
  required ResolvedGoalView goal,
  required List<WeightPointData> weights,
  required List<FoodLogData> foodLogs,
  required List<TrainingSession> sessions,
  required List<ExerciseData> exercises,
  ProfileData? profile,
  GoalData? goalRow,
  double? currentWeightKg,
  bool force = false,
  CloudLlmClient? client,
}) async {
  // 本地口径：既做降级文案，也提供趋势/KPI（算法层派生，绝不让模型算）
  final localResult = buildWeeklyReview(
    today: today,
    weights: weights,
    foodLogs: foodLogs,
    sessions: sessions,
    goal: goal,
    currentWeightKg: currentWeightKg,
  );

  if (!force) {
    final hit = await _readCache(db, localResult.weekStart);
    if (hit != null) {
      return AiReviewOutcome(
        text: hit.text,
        fromAi: hit.fromAi,
        note: null,
        cached: true,
        local: localResult,
      );
    }
  }

  final quota = await _bumpQuota(db, today);
  if (quota < 0) {
    return AiReviewOutcome(
      text: localResult.text,
      fromAi: false,
      note: '今天 AI 调用已达上限（${CloudConfig.dailyCallLimit} 次），显示本地建议',
      cached: false,
      local: localResult,
    );
  }

  final thisWeek = aggregateWeek(
    weekStart: localResult.weekStart,
    weights: weights,
    foodLogs: foodLogs,
    sessions: sessions,
    goal: goal,
  );
  final lastWeek = aggregateWeek(
    weekStart: D.addDays(localResult.weekStart, -7),
    weights: weights,
    foodLogs: foodLogs,
    sessions: sessions,
    goal: goal,
  );
  final highlights = buildHighlights(
    weekStart: thisWeek.weekStart,
    weekEnd: thisWeek.weekEnd,
    sessions: sessions,
    exercises: exercises,
  );
  final prompt = buildReviewPrompt(
    thisWeek: thisWeek,
    lastWeek: lastWeek,
    goal: goal,
    profile: profile,
    goalRow: goalRow,
    weights: weights,
    highlights: highlights,
    trendLabel: AppConfig.labels[localResult.trend] ?? '数据不足',
    weightDelta: localResult.delta,
  );

  Future<AiReviewOutcome> fallback(String note) async {
    await _writeCache(db, localResult.weekStart, localResult.text,
        fromAi: false);
    return AiReviewOutcome(
      text: localResult.text,
      fromAi: false,
      note: note,
      cached: false,
      local: localResult,
    );
  }

  try {
    final raw = await (client ?? CloudLlmClient.instance).complete(
      system: kAiSystemPrompt,
      user: prompt,
      temperature: 0.85,
      timeout: CloudConfig.requestTimeout,
    );
    final text = sanitizeAiText(raw);
    if (text.isEmpty) {
      return fallback('AI 返回内容未通过合规校验，显示本地建议');
    }
    await _writeCache(db, localResult.weekStart, text, fromAi: true);
    await saveWeeklyReview(
      db,
      WeeklyReviewResult(
        text: text,
        weekStart: localResult.weekStart,
        weekEnd: localResult.weekEnd,
        trend: localResult.trend,
        thisWeekAvg: localResult.thisWeekAvg,
        prevWeekAvg: localResult.prevWeekAvg,
        delta: localResult.delta,
        avgKcal: localResult.avgKcal,
        avgP: localResult.avgP,
        trainCount: localResult.trainCount,
        volume: localResult.volume,
      ),
    );
    return AiReviewOutcome(
      text: text,
      fromAi: true,
      note: null,
      cached: false,
      local: localResult,
    );
  } on CloudLlmException catch (e) {
    return fallback('${e.friendly}，显示本地建议');
  } catch (_) {
    return fallback('网络不可用，显示本地建议');
  }
}
