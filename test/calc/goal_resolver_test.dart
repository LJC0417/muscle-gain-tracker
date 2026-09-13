// 目标解析单元测试（ARCHITECTURE F02 验收）
// 覆盖：
//   - computeAutoGoal（与 JS 版完全一致）
//   - isManualField（单/多字段判定）
//   - resolveGoal：
//     * 全自动基线
//     * 手动覆盖 kcal/protein/carb/fat
//     * 三项宏量全锁 → 热量反推
//     * 热量+蛋白+脂肪 → 碳水吸收差额
//     * 热量+蛋白+碳水 → 脂肪反推
//   - onWeightLogged：diff < threshold 不联动；> threshold 触发
//   - hit（kcalHit / proteinHit）
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/calc/calc.dart';

Map<String, dynamic> _profile({
  String sex = 'male',
  num age = 25,
  num heightCm = 175,
  num activityFactor = 1.55,
}) {
  return {
    'sex': sex,
    'age': age,
    'heightCm': heightCm,
    'activityFactor': activityFactor,
  };
}

Map<String, dynamic> _goal({
  double surplus = 400,
  double offset = 0,
  double currentWeightKg = 62,
  double targetWeightKg = 67,
}) {
  return {
    'surplusKcal': surplus,
    'kcalAutoOffset': offset,
    'currentWeightKg': currentWeightKg,
    'targetWeightKg': targetWeightKg,
  };
}

void main() {
  group('computeAutoGoal 全自动基线', () {
    test('男 / 25 / 175 / 62 / surplus=400 → 2870/110/460/65', () {
      final a = computeAutoGoal(_profile(), 62, _goal());
      expect(a.bmr, 1594);
      expect(a.tdee, 2470);
      expect(a.kcal, 2870);
      expect(a.protein, 110);
      expect(a.carb, 460);
      expect(a.fat, 65);
      expect(a.rate, 0.25);
    });

    test('kcalAutoOffset 累加到 kcal', () {
      final a = computeAutoGoal(_profile(), 62, _goal(offset: 100));
      expect(a.kcal, 2970);
      // macros 用 kcal+offset 计算：2970/62 → P=110, F=65, C=r5((2970-440-585)/4)
      // = r5(1945/4) = r5(486.25) = 485
      expect(a.protein, 110);
      expect(a.carb, 485);
    });
  });

  group('isManualField', () {
    test('空 goal → false', () {
      expect(isManualField(null, 'kcal'), false);
    });

    test('mode=auto → false', () {
      expect(isManualField({'kcalMode': 'auto', 'kcalManual': 2870}, 'kcal'), false);
    });

    test('mode=manual 且 value 非空 → true', () {
      expect(isManualField({'kcalMode': 'manual', 'kcalManual': 2870}, 'kcal'), true);
    });

    test('mode=manual 但 value 为 null → false', () {
      expect(isManualField({'kcalMode': 'manual', 'kcalManual': null}, 'kcal'), false);
    });
  });

  group('resolveGoal 全 APP 唯一目标出口', () {
    test('全自动 → 与 computeAutoGoal 一致', () {
      final r = resolveGoal(_profile(), 62, _goal());
      expect(r.kcal, 2870);
      expect(r.protein, 110);
      expect(r.carb, 460);
      expect(r.fat, 65);
      expect(r.kcalFromMacros, 2865);
      expect(r.isOverDetermined, false);
    });

    test('仅手动 kcal', () {
      final g = _goal()..['kcalMode'] = 'manual'..['kcalManual'] = 3000;
      final r = resolveGoal(_profile(), 62, g);
      expect(r.kcal, 3000);
      expect(r.protein, 110); // 自动
      expect(r.fat, 65); // 自动
      // C = r5((3000-440-585)/4) = r5(493.75) = 495
      expect(r.carb, 495);
    });

    test('三项宏量全锁 → 热量反推', () {
      final g = _goal()
        ..['proteinMode'] = 'manual'
        ..['proteinManual'] = 120
        ..['carbMode'] = 'manual'
        ..['carbManual'] = 400
        ..['fatMode'] = 'manual'
        ..['fatManual'] = 70;
      final r = resolveGoal(_profile(), 62, g);
      // 120*4 + 400*4 + 70*9 = 480 + 1600 + 630 = 2710
      expect(r.kcal, 2710);
      expect(r.isOverDetermined, true);
    });

    test('热量+蛋白+脂肪锁 → 碳水吸收差额', () {
      final g = _goal()
        ..['kcalMode'] = 'manual'
        ..['kcalManual'] = 2900
        ..['proteinMode'] = 'manual'
        ..['proteinManual'] = 120
        ..['fatMode'] = 'manual'
        ..['fatManual'] = 70;
      final r = resolveGoal(_profile(), 62, g);
      // C = r5((2900-480-630)/4) = r5(447.5) = 450
      expect(r.carb, 450);
      expect(r.kcal, 2900);
    });

    test('热量+蛋白+碳水锁 → 脂肪反推', () {
      final g = _goal()
        ..['kcalMode'] = 'manual'
        ..['kcalManual'] = 2900
        ..['proteinMode'] = 'manual'
        ..['proteinManual'] = 120
        ..['carbMode'] = 'manual'
        ..['carbManual'] = 400;
      final r = resolveGoal(_profile(), 62, g);
      // F = r5((2900-480-1600)/9) = r5(820/9) = r5(91.11) = 90
      expect(r.fat, 90);
      expect(r.kcal, 2900);
    });

    test('kcalManual 锁定时 bmr/tdee 仍显示基线', () {
      final g = _goal()..['kcalMode'] = 'manual'..['kcalManual'] = 3000;
      final r = resolveGoal(_profile(), 62, g);
      expect(r.bmr, 1594);
      expect(r.tdee, 2470);
    });
  });

  group('onWeightLogged 体重联动', () {
    test('diff < threshold → 不联动', () {
      final g = _goal()..['lastWeightUsed'] = 62.0;
      final r = onWeightLogged(62.1, _profile(), g);
      expect(r.changed, false);
      expect(r.fields, isEmpty);
    });

    test('diff > threshold + 自动 → 联动全部', () {
      final g = _goal()..['lastWeightUsed'] = 62.0;
      final r = onWeightLogged(63.0, _profile(), g);
      expect(r.changed, true);
      expect(r.fields, contains('热量'));
      expect(r.nextGoal['lastWeightUsed'], 63.0);
      expect(r.message, contains('体重变化'));
    });

    test('kcal 手动锁 → 不联动 kcal', () {
      final g = _goal()
        ..['lastWeightUsed'] = 62.0
        ..['kcalMode'] = 'manual'
        ..['kcalManual'] = 3000;
      final r = onWeightLogged(63.0, _profile(), g);
      // kcal 锁定 → fields 中不应包含「热量」
      expect(r.fields.contains('热量'), false);
      // 但 63.0kg 时蛋白/碳水/脂肪变化，仍可能联动
      // 主要验证 kcal 未被覆盖
      expect(r.nextGoal['kcalManual'], 3000);
    });

    test('newKg=null → 不联动', () {
      final r = onWeightLogged(null, _profile(), _goal());
      expect(r.changed, false);
    });

    test('无 lastWeightUsed → 以 newKg 作为 prev（不触发）', () {
      final g = _goal();
      // 第一次：prevW = newKg → diff = 0 → 不联动
      final r = onWeightLogged(62.0, _profile(), g);
      expect(r.changed, false);
      // 但 nextGoal.lastWeightUsed 应被写入
      expect(r.nextGoal['lastWeightUsed'], 62.0);
    });
  });

  group('hit（达标率）', () {
    test('kcalHit 区间内', () {
      // K=2870, ±10% → [2583, 3157]
      expect(kcalHit(2870, 2870), true);
      expect(kcalHit(2600, 2870), true);
      expect(kcalHit(3150, 2870), true);
      expect(kcalHit(2582, 2870), false);
      expect(kcalHit(3158, 2870), false);
    });

    test('proteinHit >= 95% P', () {
      // proteinTol = 0.95; 110*0.95 = 104.5
      expect(proteinHit(110, 110), true);
      expect(proteinHit(105, 110), true); // 105 >= 104.5
      expect(proteinHit(104, 110), false); // 104 < 104.5
      expect(proteinHit(103, 110), false);
    });

    test('kcal/protein null → false', () {
      expect(kcalHit(null, 2870), false);
      expect(kcalHit(2000, null), false);
      expect(proteinHit(null, 110), false);
      expect(proteinHit(80, null), false);
    });
  });
}
