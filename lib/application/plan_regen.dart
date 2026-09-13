/// 训练计划重新生成辅助（ARCHITECTURE F04 · me_page 用）
/// 集中放：onboarding 用过的那一套 4/5 天模板 + fallbackMap，
/// 以及「读 profile + exercises → 调 generatePlan → 写 AppSettings['plan']」的封装。
///
/// 注意：不在这里改 lib/domain/plan/* —— generatePlan 是上游纯函数，
/// 这里只负责把模板数据传进去。
library;

import 'dart:convert';

import '../data/database.dart';
import '../domain/plan/plan.dart';

/// ════════ 单日分化模板（与 prototype/data/exercises.js 一致） ════════

List<DayTemplate> _templates4() => const [
      DayTemplate(code: 'A', name: '胸 + 三头', slots: [
        DaySlot(mg: 'chest', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: 'triceps', n: 1),
      ]),
      DayTemplate(code: 'B', name: '背 + 二头', slots: [
        DaySlot(mg: 'back', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: 'biceps', n: 1),
      ]),
      DayTemplate(code: 'C', name: '腿 + 核心', slots: [
        DaySlot(mg: 'legs', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 1),
      ]),
      DayTemplate(code: 'D', name: '肩 + 手臂', slots: [
        DaySlot(mg: 'shoulders', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: null, n: 1),
      ]),
    ];

List<DayTemplate> _templates5() => const [
      DayTemplate(code: 'A', name: '胸', slots: [
        DaySlot(mg: 'chest', sub: null, n: 5),
      ]),
      DayTemplate(code: 'B', name: '背', slots: [
        DaySlot(mg: 'back', sub: null, n: 5),
      ]),
      DayTemplate(code: 'C', name: '腿', slots: [
        DaySlot(mg: 'legs', sub: null, n: 5),
      ]),
      DayTemplate(code: 'D', name: '肩 + 核心', slots: [
        DaySlot(mg: 'shoulders', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 1),
      ]),
      DayTemplate(code: 'E', name: '手臂 + 核心', slots: [
        DaySlot(mg: 'arms', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 1),
      ]),
    ];

Map<String, List<String>> _fallbackMap() => const {
      'chest': ['shoulders'],
      'back': ['arms'],
      'legs': ['core'],
      'shoulders': ['arms'],
      'arms': ['back'],
      'core': ['legs'],
    };

const _week4 = WeekPattern('A', 'B', '', 'C', '', 'D', '');
const _week5 = WeekPattern('A', 'B', '', 'C', 'D', 'E', '');

/// 把 ExerciseData 转成 plan 域的 Exercise 纯对象。
Exercise _toDomain(ExerciseData e) => Exercise(
      id: e.id,
      name: e.name,
      muscleGroup: e.muscleGroup,
      subGroup: e.subGroup,
      isCompound: e.isCompound,
      requiredEquipment: AppDatabase.decodeStrList(e.requiredEquipmentJson),
      scenes: AppDatabase.decodeStrList(e.scenesJson),
      defaultSets: e.defaultSets,
      repLow: e.repLow,
      repHigh: e.repHigh,
      isBodyweight: e.isBodyweight,
      orderWeight: e.orderWeight,
    );

/// 重新生成训练计划（me_page「重新生成训练计划」按钮使用）。
///
///   - 读 profile（已有则用其 daysPerWeek/scene/equipment；没有则直接抛错）
///   - 拉全部 exercises，调 generatePlan
///   - 序列化写进 AppSettings[key='plan']
///
/// 失败抛 [StateError]，调用方在 UI 层捕获。
Future<void> regenerateTrainingPlan(AppDatabase db) async {
  final profiles = await db.select(db.profiles).get();
  if (profiles.isEmpty) {
    throw StateError('尚未完成引导，无法重新生成计划');
  }
  final p = profiles.first;
  final scene = p.scene;
  final daysPerWeek = p.daysPerWeek;
  final equipment = AppDatabase.decodeStrList(p.equipmentJson);

  final allRows = await db.select(db.exercises).get();
  final exList = allRows.map(_toDomain).toList();

  final input = GeneratePlanInput(
    scene: scene,
    daysPerWeek: daysPerWeek,
    equipment: equipment,
    allExercises: exList,
    templates: daysPerWeek >= 5 ? _templates5() : _templates4(),
    fallbackMap: _fallbackMap(),
    weekPatternDefault: const {4: _week4, 5: _week5},
    templatePoolLe5: const ['A', 'B', 'C', 'D', 'E'],
    templatePoolAll: const ['A', 'B', 'C', 'D', 'E', 'F'],
  );
  final plan = generatePlan(input);

  final planJson = <String, dynamic>{
    'days': plan.days
        .map((d) => <String, dynamic>{
              'code': d.code,
              'name': d.name,
              'estMinutes': d.estMinutes,
              'entries': d.entries
                  .map((e) => <String, dynamic>{
                        'sortOrder': e.sortOrder,
                        'exerciseId': e.exerciseId,
                        'targetSets': e.targetSets,
                        'repLow': e.repLow,
                        'repHigh': e.repHigh,
                      })
                  .toList(),
            })
        .toList(),
    'pattern': <int, String>{
      for (var i = 1; i <= 7; i++) i: plan.pattern.at(i),
    },
  };

  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'plan',
          value: jsonEncode(planJson),
        ),
      );
}
