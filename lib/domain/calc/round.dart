/// 舍入工具（ARCHITECTURE 7.1 精度表）
/// 业务取整粒度统一在此：
///   r0:  1 kcal  (BMR)
///   r1:  0.1 单位 (展示)
///   r2:  0.01 单位 (体重)
///   r005:0.05 kg  (增重速度)
///   r5:  5 g      (P/C/F)
///   r10: 10 kcal  (TDEE / 目标热量)
class R {
  R._();

  static num r0(num x) => x.round();
  static double r1(num x) => (x * 10).round() / 10.0;
  static double r2(num x) => (x * 100).round() / 100.0;
  static double r005(num x) => (x / 0.05).round() * 0.05;
  static num r5(num x) => (x / 5).round() * 5;
  static num r10(num x) => (x / 10).round() * 10;
}

/// 把 [x] 限制在 [lo, hi] 区间。空/NaN 时返回 [lo]（与 JS 版本一致）。
num clamp(num? x, num lo, num hi) {
  if (x == null || x.isNaN) return lo;
  return x < lo ? lo : (x > hi ? hi : x);
}
