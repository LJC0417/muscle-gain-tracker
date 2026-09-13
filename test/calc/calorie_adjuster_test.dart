// 热量自动微调单元测试（ARCHITECTURE F02 验收）
// 覆盖：
//   - 闸门 1：本周/上周记录 < 3 天 → maintain
//   - 闸门 2：数据不足 N 周 → maintain
//   - 闸门 3：本周已调整 → maintain
//   - onTrack：不动
//   - slow：增加；fast：减少
//   - 软边界：BMR 倍数夹紧
//   - applyAdjustment：累加 kcalAutoOffset；manual → auto 解锁
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/calc/calc.dart';

AdjustCtx _ctx({
  num? weekAvg = 62.2,
  num? prevWeekAvg = 62.0,
  num? delta = 0.2,
  num? targetRate = 0.25,
  num targetKcal = 2870,
  num bmr = 1594,
  int weeksOfData = 3,
  String? lastAdjustWeek,
  String thisWeekKey = '2025-W11',
}) {
  return AdjustCtx(
    weekAvg: weekAvg,
    prevWeekAvg: prevWeekAvg,
    delta: delta,
    targetRate: targetRate,
    targetKcal: targetKcal,
    bmr: bmr,
    weeksOfData: weeksOfData,
    lastAdjustWeek: lastAdjustWeek,
    thisWeekKey: thisWeekKey,
  );
}

void main() {
  group('闸门（gating）', () {
    test('本周记录不足 → maintain', () {
      final s = suggestCalorieAdjust(_ctx(weekAvg: null, prevWeekAvg: 62.0));
      expect(s.type, 'maintain');
      expect(s.amount, 0);
      expect(s.reason, contains('不足'));
    });

    test('上周记录不足 → maintain', () {
      final s = suggestCalorieAdjust(_ctx(weekAvg: 62.2, prevWeekAvg: null));
      expect(s.type, 'maintain');
    });

    test('数据不足 2 周 → maintain', () {
      final s = suggestCalorieAdjust(_ctx(weeksOfData: 1));
      expect(s.type, 'maintain');
      expect(s.reason, contains('先观察'));
    });

    test('本周已调整 → maintain', () {
      final s = suggestCalorieAdjust(_ctx(lastAdjustWeek: '2025-W11'));
      expect(s.type, 'maintain');
      expect(s.reason, contains('已调整'));
    });
  });

  group('onTrack 不变', () {
    test('delta=0.25 命中区间 → maintain', () {
      final s = suggestCalorieAdjust(_ctx(delta: 0.25, targetRate: 0.25));
      expect(s.type, 'maintain');
      expect(s.amount, 0);
      expect(s.reason, contains('节奏正好'));
    });
  });

  group('slow → increase', () {
    test('delta=0.10（远低于 0.20）→ +100', () {
      // deficit = (0.25 - 0.05) - 0.10 = 0.10; sev = ceil(0.10/0.10) = 1; amount = 1*100 = 100
      final s = suggestCalorieAdjust(_ctx(delta: 0.10, targetRate: 0.25));
      expect(s.type, 'increase');
      expect(s.amount, 100);
      expect(s.severity, 1);
    });

    test('delta=0（远低）→ +200', () {
      // deficit = 0.20; sev = ceil(0.20/0.10) = 2; amount = 200
      final s = suggestCalorieAdjust(_ctx(delta: 0.0, targetRate: 0.25));
      expect(s.type, 'increase');
      expect(s.amount, 200);
      expect(s.severity, 2);
    });
  });

  group('fast → decrease', () {
    test('delta=0.50（远高于 0.40）→ -100', () {
      // excess = 0.50 - 0.40 = 0.10; sev = ceil(0.10/0.15) = 1; amount = -100
      final s = suggestCalorieAdjust(_ctx(delta: 0.50, targetRate: 0.25));
      expect(s.type, 'decrease');
      expect(s.amount, -100);
      expect(s.severity, 1);
    });

    test('delta=0.80（极高）→ -200', () {
      // excess = 0.40; sev = ceil(0.40/0.15) = 3 → clamp 到 2; amount = -200
      final s = suggestCalorieAdjust(_ctx(delta: 0.80, targetRate: 0.25));
      expect(s.type, 'decrease');
      expect(s.amount, -200);
      expect(s.severity, 2);
    });
  });

  group('软边界（BMR 倍数夹紧）', () {
    test('增加时 hit 上限 → maintain', () {
      // bmr=1594; hi = 1594 * 2.2 = 3506.8; lo = 1594 * 1.2 = 1912.8
      // targetKcal=3500, +100 = 3600 → clamp 到 3506.8, amount = 6.8 → 整数 = 6
      // amount ≠ 0 仍会返回 increase（不命中 0 边界）
      final s = suggestCalorieAdjust(_ctx(
        delta: 0.0,
        targetRate: 0.25,
        targetKcal: 3500,
        bmr: 1594,
      ));
      // 3506.8 - 3500 = 6.8 → int amount = 6 → 不为 0 → increase
      expect(s.type, 'increase');
      expect(s.amount, lessThanOrEqualTo(7));
    });

    test('命中 0 → maintain with 边界文案', () {
      // targetKcal = 3506 (几乎贴 hi)，amount 6.8 → clamp 后 amount=6（不减）
      // 构造真正命中 0 的场景：把 targetKcal 推到 bmr * 2.2 上方刚好
      // bmr * 2.2 = 1594 * 2.2 = 3506.8
      // targetKcal = 3506, +100 = 3606 → clamp 3506.8 → amount = 0.8 → int = 0 → maintain
      final s = suggestCalorieAdjust(_ctx(
        delta: 0.0,
        targetRate: 0.25,
        targetKcal: 3506,
        bmr: 1594,
      ));
      expect(s.type, 'maintain');
      expect(s.reason, contains('安全边界'));
    });

    test('减少时 hit 下限 → 截到 lo', () {
      // bmr=1594; lo = 1912.8
      // 假设 targetKcal=1920, amount=-200 → 1720 < 1912.8 → clamp 到 1912.8
      // amount = 1912.8 - 1920 = -7.2 → int = -7
      final s = suggestCalorieAdjust(_ctx(
        delta: 0.80,
        targetRate: 0.25,
        targetKcal: 1920,
        bmr: 1594,
      ));
      expect(s.type, 'decrease');
      expect(s.newKcal, 1912.8);
      expect(s.amount, greaterThanOrEqualTo(-10));
    });
  });

  group('applyAdjustment', () {
    test('maintain → 仅写 lastAdjustWeek / lastAdjustedAt', () {
      final goal = {'kcalAutoOffset': 0};
      final suggest = CalorieAdjust(
        type: 'maintain',
        amount: 0,
        newKcal: 2870,
        reason: '...',
        severity: 0,
      );
      final next = applyAdjustment(suggest, goal, '2025-W11');
      expect(next['lastAdjustWeek'], '2025-W11');
      expect(next['lastAdjustedAt'], isNotNull);
      expect(next['kcalAutoOffset'], 0);
    });

    test('increase → 累加 kcalAutoOffset', () {
      final goal = {'kcalAutoOffset': 100, 'kcalMode': 'auto'};
      final suggest = CalorieAdjust(
        type: 'increase',
        amount: 100,
        newKcal: 2970,
        reason: '...',
        severity: 1,
      );
      final next = applyAdjustment(suggest, goal, '2025-W11');
      expect(next['kcalAutoOffset'], 200);
    });

    test('manual 模式 + increase → 解除锁定并应用', () {
      final goal = {
        'kcalAutoOffset': 0,
        'kcalMode': 'manual',
        'kcalManual': 2870,
      };
      final suggest = CalorieAdjust(
        type: 'increase',
        amount: 100,
        newKcal: 2970,
        reason: '...',
        severity: 1,
      );
      final next = applyAdjustment(suggest, goal, '2025-W11');
      expect(next['kcalMode'], 'auto');
      expect(next['kcalManual'], isNull);
      expect(next['kcalAutoOffset'], 100);
    });

    test('suggest=null → 返回原 goal', () {
      final goal = {'kcalAutoOffset': 0};
      expect(applyAdjustment(null, goal, '2025-W11'), goal);
      expect(applyAdjustment(null, <String, dynamic>{}, '2025-W11'),
          <String, dynamic>{});
    });
  });
}
