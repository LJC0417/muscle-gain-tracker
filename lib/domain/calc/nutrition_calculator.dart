/// 营养计算（ARCHITECTURE 2.1–2.5 / A1–A5）
///   bmr              — Mifflin-St Jeor
///   recommendFactor  — 按每周训练天数的活动系数
///   tdee             — TDEE = round10(BMR * factor)（传已 r0 取整的 BMR）
///   targetKcal       — 目标热量 = clamp(round10(TDEE + surplus), 0, 1000)
///   macros           — P/C/F（重要：第 3 步用「已取整」的 P/F 反推 C）
///   defaultRate      — 推荐增重速度
///   weeksToGoal      — 预计周数
///
/// 所有数字必须经 AppConfig 提供，禁止在调用方写死。
import '../../core/constants/app_config.dart';
import 'round.dart';

/// 三大营养素结果（克）。
class Macros {
  final num protein;
  final num carb;
  final num fat;
  const Macros(this.protein, this.carb, this.fat);
}

/// 1) BMR（Mifflin-St Jeor）
num bmr(String sex, num W, num H, num A) {
  final base = 10 * W + 6.25 * H - 5 * A;
  if (sex == 'female') {
    return R.r0(base + AppConfig.bmrFemaleOffset);
  }
  return R.r0(base + AppConfig.bmrMaleOffset);
}

/// 2) 活动系数（PRD R-02）
double recommendFactor(num daysPerWeek) {
  final d = clamp(daysPerWeek, 0, 7);
  if (d <= 1) return 1.2;
  if (d <= 3) return 1.375;
  if (d <= 5) return 1.55;
  return 1.725;
}

/// 3) TDEE（必须传已 r0 取整的 BMR）
num tdee(num bmrValue, num factor) => R.r10(bmrValue * factor);

/// 4) 目标热量
num targetKcal(num tdeeValue, num surplus) {
  final s = clamp(surplus, AppConfig.surplusMin, AppConfig.surplusMax);
  return R.r10(tdeeValue + s);
}

/// 5) 三大营养素（克）
/// 关键：第 3 步必须用「已取整」的 P/F 反推 C，否则 PRD 110/460/65 全部对不上。
Macros macros(num W, num K, {double? proteinPerKg, double? fatPerKg, double? fatPctMin, num? minCarbG}) {
  final pPerKg = proteinPerKg ?? AppConfig.proteinPerKg;
  final fPerKg = fatPerKg ?? AppConfig.fatPerKg;
  final fPctMin = fatPctMin ?? AppConfig.fatPctMin;
  final minCarb = minCarbG ?? AppConfig.minCarbG.toInt();
  // 1) 蛋白
  var P = R.r5(W * pPerKg);
  // 2) 脂肪：体重下限 与 热量占比下限 取大者
  final fatFloorByKg = W * fPerKg;
  final fatFloorByKcal = (K * fPctMin) / 9;
  var F = R.r5(fatFloorByKg > fatFloorByKcal ? fatFloorByKg : fatFloorByKcal);
  // 3) 碳水：用「已取整」的 P/F 兜底反推
  var C = R.r5((K - P * 4 - F * 9) / 4);
  // 4) 边界兜底：目标热量过低导致碳水不足时，压缩 P/F 保证最低碳水
  if (C < minCarb) {
    final avail = K * 0.85;
    final pfKcal = P * 4 + F * 9;
    if (pfKcal > 0) {
      final scale = avail / pfKcal;
      P = R.r5(P * scale);
      F = R.r5(F * scale);
    }
    C = R.r5((K - P * 4 - F * 9) / 4);
    if (C < 0) C = 0;
  }
  return Macros(P, C, F);
}

/// 默认增重速度（kg/周），clamp 到 [RATE_MIN, RATE_MAX]。
double defaultRate(num W, {double? ratePctPerWeek, num? rateMin, num? rateMax}) {
  final pct = ratePctPerWeek ?? AppConfig.ratePctPerWeek;
  final lo = (rateMin ?? AppConfig.rateMin).toDouble();
  final hi = (rateMax ?? AppConfig.rateMax).toDouble();
  final raw = R.r005(W * pct);
  return raw < lo ? lo : (raw > hi ? hi : raw);
}

/// 预计周数（向上取整）。非法参数返回 0。
int weeksToGoal(num? curW, num? targetW, num? rate) {
  if (rate == null || rate <= 0 || curW == null || targetW == null || targetW <= curW) {
    return 0;
  }
  return ((targetW - curW) / rate).ceil();
}
