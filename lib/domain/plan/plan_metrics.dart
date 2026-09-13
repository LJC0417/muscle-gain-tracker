/// 训练容量与 PR（ARCHITECTURE 2.11 / A11）
///   setVolume     — 单组容量 = weight × reps（含自重选项）
///   e1RM          — Epley 估算 1RM = w × (1 + reps / E1RM_DIVISOR)
///   sessionVolume — 整场容量（求和）
///   checkPR       — 命中 PR 时返回 kind 列表（maxWeight / maxVolume / est1RM）
import '../../core/constants/app_config.dart';
import '../calc/round.dart';

/// 单组记录（与 JS 版一致）。
class WorkoutSet {
  final String exerciseId;
  final num weightKg;
  final num reps;
  final bool isBodyweight;
  final num? volumeKg;
  const WorkoutSet({
    required this.exerciseId,
    required this.weightKg,
    required this.reps,
    required this.isBodyweight,
    this.volumeKg,
  });
}

/// 历史 PR 基线（聚合后的最大）。
class PrHistory {
  final num bestWeightKg;
  final num bestSingleVolume;
  final num bestEst1Rm;
  const PrHistory({
    required this.bestWeightKg,
    required this.bestSingleVolume,
    required this.bestEst1Rm,
  });
}

/// 单条 PR 命中。
class PrHit {
  final String kind; // 'maxWeight' | 'maxVolume' | 'est1RM'
  final num value;
  final num old;
  final num? reps; // only for maxWeight
  const PrHit({
    required this.kind,
    required this.value,
    required this.old,
    this.reps,
  });
}

/// 单组容量（kg × reps）。
num setVolume(num weightKg, num reps, bool isBodyweight) {
  if (isBodyweight && !AppConfig.countBodyweightVolume) return 0;
  return R.r1((weightKg) * (reps));
}

/// Epley 估算 1RM。
num e1RM(num weightKg, num reps) {
  final w = weightKg;
  if (w <= 0) return 0;
  return R.r1(w * (1 + reps / AppConfig.e1rmDivisor));
}

/// 整场容量（kg）。
num sessionVolume(List<WorkoutSet> sets) {
  if (sets.isEmpty) return 0;
  final sum = sets.fold<num>(0, (a, s) => a + (s.volumeKg ?? 0));
  return R.r1(sum);
}

/// PR 检查（命中 maxWeight/maxVolume/est1RM）。
List<PrHit> checkPR(WorkoutSet newSet, PrHistory history) {
  final prs = <PrHit>[];
  final maxWeight = history.bestWeightKg;
  final maxVolume = history.bestSingleVolume;
  final maxEst1Rm = history.bestEst1Rm;
  final w = newSet.weightKg;
  final r = newSet.reps;
  final vol = setVolume(w, r, newSet.isBodyweight);
  final est = e1RM(w, r);

  if (w > maxWeight) {
    prs.add(PrHit(kind: 'maxWeight', value: w, reps: r, old: maxWeight));
  }
  if (vol > maxVolume) {
    prs.add(PrHit(kind: 'maxVolume', value: vol, old: maxVolume));
  }
  if (est > maxEst1Rm && est > 0) {
    prs.add(PrHit(kind: 'est1RM', value: est, old: maxEst1Rm));
  }
  return prs;
}
