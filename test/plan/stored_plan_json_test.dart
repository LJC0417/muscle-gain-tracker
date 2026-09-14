// 训练计划持久化回归测试
//
// 背景（真实线上 bug）：StoredPlan.pattern 是 Map<int, String>，
// 之前直接交给 jsonEncode，而 dart:convert 遇到非 String 键会抛
// JsonUnsupportedObjectError。后果是三条链路同时静默失败：
//   1) 引导页「开始使用」→ 计划从未写入，且按钮永远停在转圈（用户看到的是"卡加载"）
//   2) 「我的」→ 重新生成训练计划 → 报"生成失败"
//   3) 自定义训练日 → 保存无反应
// 这个测试锁死「pattern 必须能安全 JSON 化并原样读回」。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/application/providers/app_providers.dart';
import 'package:muscle_gain_tracker/domain/plan/plan.dart';

void main() {
  group('StoredPlan JSON 往返', () {
    const plan = StoredPlan(
      days: [
        PlanDay(
          code: 'A',
          name: '胸 + 三头',
          estMinutes: 46,
          entries: [
            PlanEntry(
              sortOrder: 1,
              exerciseId: 'bench_press',
              targetSets: 3,
              repLow: 8,
              repHigh: 12,
            ),
          ],
        ),
      ],
      pattern: {1: 'A', 2: 'B', 3: '', 4: 'C', 5: '', 6: 'D', 7: ''},
    );

    test('toJson 能被 jsonEncode 编码（pattern 用 String 键）', () {
      final json = plan.toJson();
      expect(json['pattern'], isA<Map<String, String>>());
      expect(
        () => jsonEncode(json),
        returnsNormally,
        reason: 'pattern 若用 int 键，jsonEncode 会抛 JsonUnsupportedObjectError',
      );
    });

    test('编码后能原样解码回 StoredPlan', () {
      final raw = jsonEncode(plan.toJson());
      final back = StoredPlan.fromAppSettingsValue(raw);

      expect(back.isEmpty, isFalse);
      expect(back.days.length, 1);
      expect(back.days.first.code, 'A');
      expect(back.days.first.estMinutes, 46);
      expect(back.days.first.entries.single.exerciseId, 'bench_press');
      // 7 个工作日键必须全部还原成 int
      expect(back.pattern[1], 'A');
      expect(back.pattern[3], '');
      expect(back.pattern[6], 'D');
      expect(back.pattern.length, 7);
    });

    test('userOverrides 一起往返', () {
      const withOv = StoredPlan(
        days: [],
        pattern: {1: 'A'},
        overrides: {
          'A': PlanOverride(
            name: '我的胸日',
            entries: [
              PlanEntry(
                sortOrder: 0,
                exerciseId: 'push_up',
                targetSets: 4,
                repLow: 10,
                repHigh: 15,
              ),
            ],
          ),
        },
      );
      final back =
          StoredPlan.fromAppSettingsValue(jsonEncode(withOv.toJson()));
      expect(back.isCustom('A'), isTrue);
      expect(back.effectiveDay('A')?.name, '我的胸日');
      expect(back.effectiveDay('A')?.entries.single.targetSets, 4);
    });

    test('空串 / 脏数据不抛异常，退回空计划', () {
      expect(StoredPlan.fromAppSettingsValue(null).isEmpty, isTrue);
      expect(StoredPlan.fromAppSettingsValue('').isEmpty, isTrue);
      expect(StoredPlan.fromAppSettingsValue('不是JSON').isEmpty, isTrue);
      expect(StoredPlan.fromAppSettingsValue('{"days":1}').isEmpty, isTrue);
    });

    test('兼容历史数字键写法（k as num 分支）', () {
      // 手写一份 pattern 为数字键的对象，确保解析不会因 cast 失败而整份丢弃
      const raw = '{"days":[],"pattern":{"1":"A","2":"B"}}';
      final p = StoredPlan.fromAppSettingsValue(raw);
      expect(p.pattern[1], 'A');
      expect(p.pattern[2], 'B');
    });
  });
}
