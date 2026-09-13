// 营养计算单元测试（ARCHITECTURE F02 验收）
// 覆盖 PRD R-02 / R-04 / v1.1 精度表硬规则：
//   bmr('male', 62, 175, 25) → 1594
//   tdee(1594, 1.55)         → 2470
//   targetKcal(2470, 400)    → 2870
//   macros(62, 2870)         → {110, 460, 65}
//   defaultRate(62)          → 0.25
//   weeksToGoal(62, 67, 0.25)→ 20
//
// 边界：
//   - 不足碳水时压 P/F 兜底（K=1500）
//   - surplus 超出范围时 clamp
//   - 三项宏量取整后用整后值反推 C（不是 raw 111.6 / 63.78）
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/calc/calc.dart';

void main() {
  group('A1 BMR (Mifflin-St Jeor)', () {
    test('male / 62 / 175 / 25 → 1594', () {
      // 10*62 + 6.25*175 - 5*25 + 5 = 620 + 1093.75 - 125 + 5 = 1593.75 → r0 = 1594
      expect(bmr('male', 62, 175, 25), 1594);
    });

    test('female / 55 / 165 / 28 → 1279', () {
      // 10*55 + 6.25*165 - 5*28 - 161 = 550 + 1031.25 - 140 - 161 = 1280.25 → r0 = 1280
      // 重新算：10*55=550; 6.25*165=1031.25; 5*28=140; 550+1031.25-140=1441.25; -161 = 1280.25 → 1280
      expect(bmr('female', 55, 165, 28), 1280);
    });

    test('non-binary 兜底按男', () {
      expect(bmr('other', 62, 175, 25), 1594);
    });
  });

  group('A2 活动系数与 TDEE', () {
    test('recommendFactor 分档', () {
      expect(recommendFactor(0), 1.2);
      expect(recommendFactor(1), 1.2);
      expect(recommendFactor(2), 1.375);
      expect(recommendFactor(3), 1.375);
      expect(recommendFactor(4), 1.55);
      expect(recommendFactor(5), 1.55);
      expect(recommendFactor(6), 1.725);
      expect(recommendFactor(7), 1.725);
    });

    test('tdee(1594, 1.55) → 2470', () {
      expect(tdee(1594, 1.55), 2470);
    });
  });

  group('A3 目标热量', () {
    test('targetKcal(2470, 400) → 2870', () {
      expect(targetKcal(2470, 400), 2870);
    });

    test('surplus 超出范围 clamp', () {
      expect(targetKcal(2470, -100), 2470); // < min(0)
      expect(targetKcal(2470, 1500), 3470); // > max(1000)
    });
  });

  group('A4 三大营养素', () {
    test('macros(62, 2870) → {110, 460, 65}', () {
      final m = macros(62, 2870);
      expect(m.protein, 110);
      expect(m.carb, 460);
      expect(m.fat, 65);
    });

    test('校验和 = 440+1840+585 = 2865（与 2870 差 5 是预期）', () {
      final m = macros(62, 2870);
      final sum = m.protein * 4 + m.carb * 4 + m.fat * 9;
      expect(sum, 2865);
      expect((sum - 2870).abs() <= 20, true);
    });

    test('C 用「整后 P/F」反推（最易错的一条）', () {
      // 若用 raw 111.6 / 63.78 → C = r5(463) = 465；现必须 = 460
      final m = macros(62, 2870);
      expect(m.carb, 460);
    });

    test('目标热量过低触发压 P/F 兜底（K=1500）', () {
      // 1500 kcal 不足以维持 P110/F65 → 触发 minCarb 兜底
      final m = macros(62, 1500);
      expect(m.carb, greaterThanOrEqualTo(20));
      expect(m.protein, greaterThan(0));
      expect(m.fat, greaterThan(0));
    });
  });

  group('A5 增重速度与预计周数', () {
    test('defaultRate(62) → 0.25', () {
      // 62 * 0.004 = 0.248 → r005 = 0.25
      expect(defaultRate(62), 0.25);
    });

    test('weeksToGoal(62, 67, 0.25) → 20', () {
      // ceil((67-62)/0.25) = ceil(20) = 20
      expect(weeksToGoal(62, 67, 0.25), 20);
    });

    test('weeksToGoal 非法参数返回 0', () {
      expect(weeksToGoal(null, 67, 0.25), 0);
      expect(weeksToGoal(62, null, 0.25), 0);
      expect(weeksToGoal(62, 60, 0.25), 0); // 目标 <= 当前
      expect(weeksToGoal(62, 67, 0), 0);
      expect(weeksToGoal(62, 67, -1), 0);
    });

    test('defaultRate clamp 到 [0.1, 0.8]', () {
      expect(defaultRate(10), 0.1); // 0.04 → 0.1
      expect(defaultRate(250), 0.8); // 1.0 → 0.8
    });
  });

  group('R utilities', () {
    test('取整粒度', () {
      expect(R.r0(1593.75), 1594);
      expect(R.r1(2.46), 2.5);
      expect(R.r2(2.456), 2.46);
      expect(R.r005(0.248), 0.25);
      expect(R.r5(111.6), 110);
      expect(R.r10(2470.7), 2470);
    });

    test('clamp', () {
      expect(clamp(null, 0, 10), 0);
      expect(clamp(double.nan, 0, 10), 0);
      expect(clamp(-5, 0, 10), 0);
      expect(clamp(15, 0, 10), 10);
      expect(clamp(5, 0, 10), 5);
    });
  });
}
