/// 热量自动微调建议（ARCHITECTURE 2.9 / A9 / R-11 / R-48）
///   suggestCalorieAdjust  — 闸门 + 趋势判定 + 软边界（BMR 倍数）
///   applyAdjustment       — 把建议写入 goal.kcalAutoOffset（保持 manual 不被覆盖）
import '../../core/constants/app_config.dart';
import 'round.dart';

/// 微调建议结果。
class CalorieAdjust {
  /// 'increase' | 'decrease' | 'maintain'
  final String type;
  final int amount;
  final num newKcal;
  final String reason;
  final int severity;
  const CalorieAdjust({
    required this.type,
    required this.amount,
    required this.newKcal,
    required this.reason,
    required this.severity,
  });
}

/// 微调上下文（缺失日 / 趋势 / 目标 / BMR / 上次调整周）。
class AdjustCtx {
  final num? weekAvg;
  final num? prevWeekAvg;
  final num? delta;
  final num? targetRate;
  final num targetKcal;
  final num? bmr;
  final int weeksOfData;
  final String? lastAdjustWeek;
  final String thisWeekKey;

  const AdjustCtx({
    required this.weekAvg,
    required this.prevWeekAvg,
    required this.delta,
    required this.targetRate,
    required this.targetKcal,
    required this.bmr,
    required this.weeksOfData,
    required this.lastAdjustWeek,
    required this.thisWeekKey,
  });
}

/// 计算微调建议（纯函数，不修改 goal）。
CalorieAdjust suggestCalorieAdjust(AdjustCtx ctx) {
  // 闸门 1：本周/上周记录不足
  if (ctx.weekAvg == null || ctx.prevWeekAvg == null) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      reason: '本周或上周记录不足 ${AppConfig.weekAvgMinDays} 天，暂不调整',
      severity: 0,
    );
  }
  // 闸门 2：数据不足 N 周
  if (ctx.weeksOfData < AppConfig.minWeeksBeforeAdjust) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      reason: '数据不足 ${AppConfig.minWeeksBeforeAdjust} 周，先观察',
      severity: 0,
    );
  }
  // 闸门 3：本周已调整
  if (ctx.lastAdjustWeek != null && ctx.lastAdjustWeek == ctx.thisWeekKey) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      reason: '本周已调整过，下周再看',
      severity: 0,
    );
  }
  // 趋势判定（与 trend_analyzer.trendStatus 同步语义；这里复刻以便 amount 计算）
  if (ctx.targetRate == null || ctx.delta == null) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      reason: '趋势未知',
      severity: 0,
    );
  }
  if (ctx.delta! >= ctx.targetRate! - AppConfig.tolSlow &&
      ctx.delta! <= ctx.targetRate! + AppConfig.tolFast) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      severity: 0,
      reason: '体重节奏正好（${ctx.delta} kg/周，目标 ${ctx.targetRate}）',
    );
  }
  int sev;
  int amount;
  String reason;
  if (ctx.delta! < ctx.targetRate! - AppConfig.tolSlow) {
    final deficit = (ctx.targetRate! - AppConfig.tolSlow) - ctx.delta!;
    sev = clamp((deficit / AppConfig.slowSeverityUnit).ceil(), 1, 2).toInt();
    amount = sev * AppConfig.adjustStepKcal.round();
    reason =
        '近一周增重 ${ctx.delta} kg，低于目标 ${ctx.targetRate}，建议每天多吃 $amount kcal';
  } else {
    final excess = ctx.delta! - (ctx.targetRate! + AppConfig.tolFast);
    sev = clamp((excess / AppConfig.fastSeverityUnit).ceil(), 1, 2).toInt();
    amount = -1 * sev * AppConfig.adjustStepKcal.round();
    reason =
        '近一周增重 ${ctx.delta} kg，快于目标，长肥风险高，建议每天少吃 ${amount.abs()} kcal';
  }
  // 软边界：BMR × 倍数
  final bmrVal = ctx.bmr ?? 0;
  final lo = bmrVal * AppConfig.kcalFloorBmrMult;
  final hi = bmrVal * AppConfig.kcalCeilBmrMult;
  final clampedKcal =
      ctx.targetKcal + amount < lo ? lo : ((ctx.targetKcal + amount > hi) ? hi : ctx.targetKcal + amount);
  amount = (clampedKcal - ctx.targetKcal).toInt();
  if (amount == 0) {
    return CalorieAdjust(
      type: 'maintain',
      amount: 0,
      newKcal: ctx.targetKcal,
      reason: '目标已达安全边界，维持当前热量',
      severity: 0,
    );
  }
  return CalorieAdjust(
    type: amount > 0 ? 'increase' : 'decrease',
    amount: amount,
    newKcal: clampedKcal,
    reason: reason,
    severity: sev,
  );
}

/// 应用建议到 goal 副本。返回新 Map，原 goal 不变。
/// - 若 kcalMode='manual' 且 type≠'maintain'：自动解除锁定（UI 已二次确认）
/// - 始终累加 kcalAutoOffset + 写 lastAdjustWeek / lastAdjustedAt
Map<String, dynamic> applyAdjustment(
  CalorieAdjust? suggest,
  Map<String, dynamic> goal,
  String thisWeekKey,
) {
  if (suggest == null) return goal;
  final next = Map<String, dynamic>.from(goal);
  final nowIso = DateTime.now().toIso8601String();
  if (suggest.type == 'maintain' || suggest.amount == 0) {
    next['lastAdjustWeek'] = thisWeekKey;
    next['lastAdjustedAt'] = nowIso;
    return next;
  }
  if (next['kcalMode'] == 'manual') {
    next['kcalMode'] = 'auto';
    next['kcalManual'] = null;
    next['kcalAutoOffset'] = 0;
  }
  final cur = (next['kcalAutoOffset'] as num?)?.toInt() ?? 0;
  next['kcalAutoOffset'] = cur + suggest.amount;
  next['lastAdjustWeek'] = thisWeekKey;
  next['lastAdjustedAt'] = nowIso;
  return next;
}
