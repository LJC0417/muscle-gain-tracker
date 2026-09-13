/// 目标解析（ARCHITECTURE 2.6 / 2.7 / A6 / A7）
///   computeAutoGoal     — 全自动基线（活动系数 + surplus + macros + 速度）
///   isManualField       — 检查某字段是否被「手动锁定」
///   resolveGoal         — 全 APP 唯一目标出口（手动 > 自动 > 自洽修正）
///   onWeightLogged      — 体重变动后的 goal 联动（diff < threshold 不触发）
import '../../core/constants/app_config.dart';
import 'nutrition_calculator.dart';
import 'round.dart';

/// 自动基线目标（中间结果）。
class AutoGoal {
  final num bmr;
  final num tdee;
  final num kcal;
  final num protein;
  final num carb;
  final num fat;
  final double rate;
  const AutoGoal({
    required this.bmr,
    required this.tdee,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.rate,
  });
}

/// 最终目标（手动覆盖 + 自洽修正后）。
class ResolvedGoal {
  final num kcal;
  final num protein;
  final num carb;
  final num fat;
  final double rate;
  final num bmr;
  final num tdee;
  final num kcalFromMacros;
  final bool isOverDetermined;
  const ResolvedGoal({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.rate,
    required this.bmr,
    required this.tdee,
    required this.kcalFromMacros,
    required this.isOverDetermined,
  });
}

/// 体重联动结果。
class WeightLinkResult {
  final bool changed;
  final List<String> fields;
  final String message;
  final Map<String, dynamic> nextGoal;
  const WeightLinkResult({
    required this.changed,
    required this.fields,
    required this.message,
    required this.nextGoal,
  });
}

/// 全自动基线。`goal` 仅读 `kcalAutoOffset` 与 `surplusKcal`。
AutoGoal computeAutoGoal(
  Map<String, dynamic> profile,
  num W,
  Map<String, dynamic> goal,
) {
  final bmrVal = R.r0(bmr(
    profile['sex'] as String,
    W,
    profile['heightCm'] as num,
    profile['age'] as num,
  ));
  final tdeeVal = tdee(bmrVal, profile['activityFactor'] as num);
  final surplus = (goal['surplusKcal'] as num?)?.toInt() ?? AppConfig.defaultSurplus.toInt();
  var kcal = targetKcal(tdeeVal, surplus);
  final offset = (goal['kcalAutoOffset'] as num?)?.toInt() ?? 0;
  final m = macros(W, kcal + offset);
  kcal = kcal + offset; // 含微调累计的最终基线
  return AutoGoal(
    bmr: bmrVal,
    tdee: tdeeVal,
    kcal: kcal,
    protein: m.protein,
    carb: m.carb,
    fat: m.fat,
    rate: defaultRate(W),
  );
}

/// 检查某字段是否被「手动锁定」。
bool isManualField(Map<String, dynamic>? goal, String field) {
  if (goal == null) return false;
  return goal['${field}Mode'] == 'manual' && goal['${field}Manual'] != null;
}

/// 全 APP 唯一目标出口。
/// manual > auto > 自洽修正：
///   - 三项宏量全锁：热量由三要素反推
///   - 热量+蛋白+脂肪：碳水吸收差额
///   - 热量+蛋白+碳水：脂肪反推
ResolvedGoal resolveGoal(
  Map<String, dynamic> profile,
  num W,
  Map<String, dynamic> goal,
) {
  final base = computeAutoGoal(profile, W, goal);
  num kcal = isManualField(goal, 'kcal') ? goal['kcalManual'] as num : base.kcal;
  num protein = isManualField(goal, 'protein')
      ? goal['proteinManual'] as num
      : base.protein;
  num fat = isManualField(goal, 'fat') ? goal['fatManual'] as num : base.fat;
  num carb =
      isManualField(goal, 'carb') ? goal['carbManual'] as num : base.carb;

  final manualMacros = isManualField(goal, 'protein') &&
      isManualField(goal, 'carb') &&
      isManualField(goal, 'fat');
  final manualKcalPlusPF = isManualField(goal, 'kcal') &&
      isManualField(goal, 'protein') &&
      isManualField(goal, 'fat');

  if (manualMacros) {
    kcal = protein * 4 + carb * 4 + fat * 9;
  } else if (manualKcalPlusPF && !isManualField(goal, 'carb')) {
    final derived = R.r5((kcal - protein * 4 - fat * 9) / 4);
    if (derived >= 0) carb = derived;
  } else if (isManualField(goal, 'kcal') &&
      isManualField(goal, 'protein') &&
      isManualField(goal, 'carb')) {
    fat = R.r5((kcal - protein * 4 - carb * 4) / 9);
  }

  final rate = isManualField(goal, 'rate') ? (goal['rateManual'] as num).toDouble() : base.rate;
  final lockedCount = ['kcal', 'protein', 'carb', 'fat']
      .where((k) => isManualField(goal, k))
      .length;

  return ResolvedGoal(
    kcal: kcal,
    protein: protein,
    carb: carb,
    fat: fat,
    rate: rate,
    bmr: base.bmr,
    tdee: base.tdee,
    kcalFromMacros: protein * 4 + carb * 4 + fat * 9,
    isOverDetermined: lockedCount >= 3,
  );
}

/// 体重变动后的 goal 联动（纯函数，返回新 goal 副本）。
/// - diff < WEIGHT_LINK_THRESHOLD：不联动
/// - 仅联动「未手动锁定」的字段
WeightLinkResult onWeightLogged(
  num? newKg,
  Map<String, dynamic> profile,
  Map<String, dynamic> goal,
) {
  if (newKg == null || goal == null) {
    return WeightLinkResult(
      changed: false,
      fields: const [],
      message: '',
      nextGoal: goal,
    );
  }
  final prevW = goal['lastWeightUsed'] != null
      ? goal['lastWeightUsed'] as num
      : newKg;
  if ((newKg - prevW).abs() < AppConfig.weightLinkThreshold) {
    return WeightLinkResult(
      changed: false,
      fields: const [],
      message: '',
      nextGoal: goal,
    );
  }
  final prevAuto = computeAutoGoal(profile, prevW, goal);
  final nextAuto = computeAutoGoal(profile, newKg, goal);
  final fields = <String>[];
  if (!isManualField(goal, 'kcal') && prevAuto.kcal != nextAuto.kcal) {
    fields.add('热量');
  }
  if (!isManualField(goal, 'protein') && prevAuto.protein != nextAuto.protein) {
    fields.add('蛋白');
  }
  if (!isManualField(goal, 'carb') && prevAuto.carb != nextAuto.carb) {
    fields.add('碳水');
  }
  if (!isManualField(goal, 'fat') && prevAuto.fat != nextAuto.fat) {
    fields.add('脂肪');
  }
  // 深拷贝
  final next = Map<String, dynamic>.from(goal);
  next['lastWeightUsed'] = newKg;
  final message = fields.isNotEmpty
      ? '因体重变化已更新目标（${fields.join('/')}）'
      : '';
  return WeightLinkResult(
    changed: fields.isNotEmpty,
    fields: fields,
    message: message,
    nextGoal: next,
  );
}
