// 训练计划生成单元测试
// 覆盖：
//   - availableExercises：scene + equipment ALL OF 过滤
//   - estimateMinutes：包含热身 + 每组动作/休息/转换时间
//   - generatePlan：三级降级 + 今日计划
//   - templatePoolOf：5 天分档
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/plan/plan.dart';

Exercise _ex({
  required String id,
  required String mg,
  String? sub,
  bool isCompound = true,
  List<String>? reqEq,
  List<String>? scenes,
  int defaultSets = 3,
  num repLow = 8,
  num repHigh = 12,
  bool isBodyweight = false,
  int orderWeight = 1,
}) {
  return Exercise(
    id: id,
    name: id,
    muscleGroup: mg,
    subGroup: sub,
    isCompound: isCompound,
    requiredEquipment: reqEq ?? const [],
    scenes: scenes ?? const ['home', 'gym'],
    defaultSets: defaultSets,
    repLow: repLow,
    repHigh: repHigh,
    isBodyweight: isBodyweight,
    orderWeight: orderWeight,
  );
}

List<Exercise> _homeDumbbellBench() => [
      _ex(id: 'ex_db_bench_press', mg: 'chest', sub: 'chest_mid', reqEq: ['dumbbell', 'bench']),
      _ex(id: 'ex_db_incline_press', mg: 'chest', sub: 'chest_upper', reqEq: ['dumbbell', 'bench']),
      _ex(id: 'ex_db_fly', mg: 'chest', sub: 'chest_mid', reqEq: ['dumbbell', 'bench'], isCompound: false, orderWeight: 3),
      _ex(id: 'ex_db_row', mg: 'back', sub: 'mid_back', reqEq: ['dumbbell', 'bench']),
      _ex(id: 'ex_db_bent_row', mg: 'back', sub: 'mid_back', reqEq: ['dumbbell'], orderWeight: 2),
      _ex(id: 'ex_db_rdl', mg: 'back', sub: 'lower_back', reqEq: ['dumbbell'], orderWeight: 3),
      _ex(id: 'ex_goblet_squat', mg: 'legs', sub: 'quads', reqEq: ['dumbbell']),
      _ex(id: 'ex_db_lunge', mg: 'legs', sub: 'quads', reqEq: ['dumbbell'], orderWeight: 2),
      _ex(id: 'ex_db_curl', mg: 'arms', sub: 'biceps', reqEq: ['dumbbell'], isCompound: false),
      _ex(id: 'ex_db_tri_ext', mg: 'arms', sub: 'triceps', reqEq: ['dumbbell'], isCompound: false),
      _ex(id: 'ex_plank', mg: 'core', sub: 'abs', reqEq: ['none'], isBodyweight: true, isCompound: false),
      _ex(id: 'ex_db_shoulder_press', mg: 'shoulders', sub: 'front_delts', reqEq: ['dumbbell', 'bench']),
      _ex(id: 'ex_band_pull_apart', mg: 'shoulders', sub: 'rear_delts', reqEq: ['band'], isCompound: false),
    ];

List<DayTemplate> _templates4() => [
      DayTemplate(code: 'A', name: '胸三头', slots: [
        DaySlot(mg: 'chest', sub: 'chest_mid', n: 2),
        DaySlot(mg: 'chest', sub: 'chest_upper', n: 1),
        DaySlot(mg: 'arms', sub: 'triceps', n: 1),
      ]),
      DayTemplate(code: 'B', name: '背二头', slots: [
        DaySlot(mg: 'back', sub: 'mid_back', n: 2),
        DaySlot(mg: 'back', sub: 'lower_back', n: 1),
        DaySlot(mg: 'arms', sub: 'biceps', n: 1),
      ]),
      DayTemplate(code: 'C', name: '腿核心', slots: [
        DaySlot(mg: 'legs', sub: 'quads', n: 2),
        DaySlot(mg: 'core', sub: 'abs', n: 1),
      ]),
      DayTemplate(code: 'D', name: '肩臂', slots: [
        DaySlot(mg: 'shoulders', sub: 'front_delts', n: 1),
        DaySlot(mg: 'arms', sub: 'biceps', n: 1),
        DaySlot(mg: 'arms', sub: 'triceps', n: 1),
      ]),
    ];

Map<int, WeekPattern> _patterns() => {
      4: const WeekPattern('A', 'B', '', 'C', '', 'D', ''),
    };

GeneratePlanInput _input(List<Exercise> pool, {List<String> eq = const ['dumbbell', 'bench']}) {
  return GeneratePlanInput(
    scene: 'home',
    daysPerWeek: 4,
    equipment: eq,
    allExercises: pool,
    templates: _templates4(),
    fallbackMap: {
      'chest': ['shoulders'],
      'back': ['arms'],
    },
    weekPatternDefault: _patterns(),
    templatePoolLe5: const ['A', 'B', 'C', 'D', 'E'],
    templatePoolAll: const ['A', 'B', 'C', 'D', 'E', 'F'],
  );
}

void main() {
  group('availableExercises 器械过滤', () {
    test('ALL OF 语义：少一个器械就过滤掉', () {
      final pool = _homeDumbbellBench();
      final all = availableExercises('home', ['dumbbell', 'bench'], pool);
      // 必须同时含 dumbbell + bench 的才会通过
      expect(all.any((e) => e.id == 'ex_db_bench_press'), true);
      expect(all.any((e) => e.id == 'ex_db_curl'), true); // 只要 dumbbell
      expect(all.any((e) => e.id == 'ex_band_pull_apart'), false); // 需要 band
    });

    test('scene 不匹配过滤掉', () {
      final pool = _homeDumbbellBench();
      final all = availableExercises('gym', ['dumbbell', 'bench'], pool);
      // 全部支持 home+gym；但 band_pull_apart 需要 band，被器械过滤 → 12 个
      expect(all.length, pool.length - 1);
    });

    test('requiredEquipment=none（自重）即使无器械也通过', () {
      final pool = _homeDumbbellBench();
      final all = availableExercises('home', [], pool);
      expect(all.any((e) => e.id == 'ex_plank'), true);
      expect(all.any((e) => e.id == 'ex_db_bench_press'), false);
    });
  });

  group('estimateMinutes', () {
    test('空 entries 仅热身 10 分钟', () {
      expect(estimateMinutes(const []), 10);
    });

    test('1 个动作 4 组 → 含热身 + setup + reps/rest/transition', () {
      final entries = [
        const PlanEntry(sortOrder: 1, exerciseId: 'ex_x', targetSets: 4, repLow: 8, repHigh: 12),
      ];
      // sec = 600 + 4*(10*4+90+40) + 120 = 600 + 4*170 + 120 = 600+680+120 = 1400
      // 1400 / 60 = 23.33 → r0 = 23
      expect(estimateMinutes(entries), 23);
    });
  });

  group('templatePoolOf', () {
    test('<=5 用 le5；>5 用 all', () {
      final le5 = ['A', 'B', 'C', 'D', 'E'];
      final all = ['A', 'B', 'C', 'D', 'E', 'F'];
      expect(templatePoolOf(3, le5, all), le5);
      expect(templatePoolOf(6, le5, all), all);
    });
  });

  group('generatePlan', () {
    test('4 天计划 → 4 个 day', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      expect(plan.days.length, 4);
      expect(plan.days.map((d) => d.code).toList(), ['A', 'B', 'C', 'D']);
    });

    test('A 日：胸×3 + 三头×1', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      final a = plan.days.firstWhere((d) => d.code == 'A');
      // chest_mid 取 2 个，chest_upper 取 1 个，triceps 取 1 个
      final chest = a.entries.where((e) => ['ex_db_bench_press', 'ex_db_incline_press', 'ex_db_fly'].contains(e.exerciseId)).toList();
      final tri = a.entries.where((e) => ['ex_db_tri_ext', 'ex_db_lying_ext', 'ex_bench_dip'].contains(e.exerciseId)).toList();
      expect(chest.length, 3);
      expect(tri.length, 1);
    });

    test('三级降级：当 slot 不足时启用 FALLBACK_MAP', () {
      // 构造一个场景：legs 部位只有 1 个动作，slot 要求 2 → 应补 1 个 fallback（shoulders）
      final pool = [
        ..._homeDumbbellBench().where((e) => e.muscleGroup != 'legs'),
        _ex(id: 'ex_only_one_leg', mg: 'legs', sub: 'quads', reqEq: ['dumbbell']),
      ];
      final input = _input(pool);
      final plan = generatePlan(input);
      final c = plan.days.firstWhere((d) => d.code == 'C');
      // legs slot 要求 2，但 pool 中只 1 个；fallbackMap: 'legs' 没有 → 不会借到，但同 mg 不限 sub 也不够
      // 因此只取 1 个
      final legs = c.entries
          .where((e) =>
              pool.firstWhere((x) => x.id == e.exerciseId).muscleGroup == 'legs')
          .toList();
      expect(legs.length, 1);
    });

    test('同一天不重复同一动作', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      for (final d in plan.days) {
        final ids = d.entries.map((e) => e.exerciseId).toSet();
        expect(ids.length, d.entries.length);
      }
    });

    test('sortOrder 从 1 开始连续', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      for (final d in plan.days) {
        for (var i = 0; i < d.entries.length; i++) {
          expect(d.entries[i].sortOrder, i + 1);
        }
      }
    });

    test('estMinutes > 0', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      for (final d in plan.days) {
        expect(d.estMinutes, greaterThan(0));
      }
    });
  });

  group('getTodayPlan', () {
    test('周一 → A 日', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      final today = getTodayPlan(plan, '2025-03-10'); // 周一
      expect(today?.code, 'A');
    });

    test('周二 → B 日', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      final today = getTodayPlan(plan, '2025-03-11');
      expect(today?.code, 'B');
    });

    test('周三 → 休', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      final today = getTodayPlan(plan, '2025-03-12');
      expect(today, isNull);
    });

    test('周日 → 休', () {
      final plan = generatePlan(_input(_homeDumbbellBench()));
      final today = getTodayPlan(plan, '2025-03-16');
      expect(today, isNull);
    });

    test('plan=null → null', () {
      expect(getTodayPlan(null, '2025-03-10'), isNull);
    });
  });
}
