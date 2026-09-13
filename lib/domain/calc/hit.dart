/// 摄入达标率（ARCHITECTURE 2.13 / A13）
///   kcalHit    — 热量区间 [K*(1-10%), K*(1+10%)]
///   proteinHit — 蛋白 ≥ P*95%
import '../../core/constants/app_config.dart';

bool kcalHit(num? intakeKcal, num? K) {
  if (intakeKcal == null || K == null) return false;
  return intakeKcal >= K * (1 - AppConfig.kcalTolLower) &&
      intakeKcal <= K * (1 + AppConfig.kcalTolUpper);
}

bool proteinHit(num? intakeProtein, num? P) {
  if (intakeProtein == null || P == null) return false;
  return intakeProtein >= P * AppConfig.proteinTol;
}
