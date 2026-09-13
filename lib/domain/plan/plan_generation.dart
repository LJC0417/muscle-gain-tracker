/// 训练计划生成（ARCHITECTURE 2.10 / A10）
///   availableExercises  — 按场景 + 器械过滤（requiredEquipment 语义 = ALL OF）
///   estimateMinutes     — 预计时长（含热身 10 分钟 + 每组动作/休息/转换时间）
///   defaultWeekPattern  — 周排期默认值（按 daysPerWeek 选）
///   templatePoolOf      — 模板池（5 天以下 vs 以上）
///   generatePlan        — 三级降级：精确 slot → 同部位不限 sub → FALLBACK_MAP 借近亲
///   getTodayPlan        — 取某天（weekday 1=周一）应练的模板
import '../../core/constants/app_config.dart';
import '../calc/calc.dart';

/// 单日训练模板（与 JS 版 Days 一致）。
class PlanDay {
  final String code;
  final String name;
  final List<PlanEntry> entries;
  final int estMinutes;
  const PlanDay({
    required this.code,
    required this.name,
    required this.entries,
    required this.estMinutes,
  });
}

/// 模板中一条动作槽位（无 reps 信息，由 defaultSets/repLow/repHigh 决定）。
class PlanEntry {
  final int sortOrder;
  final String exerciseId;
  final int targetSets;
  final num repLow;
  final num repHigh;
  const PlanEntry({
    required this.sortOrder,
    required this.exerciseId,
    required this.targetSets,
    required this.repLow,
    required this.repHigh,
  });
}

/// 内置动作定义（与 data/exercises.js 中 ex(...) 一致；只保留业务需要的字段）。
class Exercise {
  final String id;
  final String name;
  final String muscleGroup;
  final String? subGroup;
  final bool isCompound;
  final List<String> requiredEquipment;
  final List<String> scenes;
  final int defaultSets;
  final num repLow;
  final num repHigh;
  final bool isBodyweight;
  final int orderWeight;
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.subGroup,
    required this.isCompound,
    required this.requiredEquipment,
    required this.scenes,
    required this.defaultSets,
    required this.repLow,
    required this.repHigh,
    required this.isBodyweight,
    required this.orderWeight,
  });
}

/// 计划生成输入。
class GeneratePlanInput {
  final String scene;
  final int daysPerWeek;
  final List<String> equipment;
  final List<Exercise> allExercises;
  final List<DayTemplate> templates;
  final Map<String, List<String>> fallbackMap;
  final Map<int, WeekPattern> weekPatternDefault;
  final List<String> templatePoolLe5;
  final List<String> templatePoolAll;
  const GeneratePlanInput({
    required this.scene,
    required this.daysPerWeek,
    required this.equipment,
    required this.allExercises,
    required this.templates,
    required this.fallbackMap,
    required this.weekPatternDefault,
    required this.templatePoolLe5,
    required this.templatePoolAll,
  });
}

/// 单日分化模板（与 data/exercises.js 中 SPLIT_TEMPLATES 一致）。
class DayTemplate {
  final String code;
  final String name;
  final List<DaySlot> slots;
  const DayTemplate({required this.code, required this.name, required this.slots});
}

class DaySlot {
  final String mg;
  final String? sub;
  final int n;
  const DaySlot({required this.mg, required this.sub, required this.n});
}

/// 周排期：weekday(1..7) → code
class WeekPattern {
  final String w1;
  final String w2;
  final String w3;
  final String w4;
  final String w5;
  final String w6;
  final String w7;
  const WeekPattern(this.w1, this.w2, this.w3, this.w4, this.w5, this.w6, this.w7);
  String at(int weekday) {
    switch (weekday) {
      case 1: return w1;
      case 2: return w2;
      case 3: return w3;
      case 4: return w4;
      case 5: return w5;
      case 6: return w6;
      case 7: return w7;
    }
    return '';
  }
}

/// 计划输出（含 days 与 pattern）。
class PlanOutput {
  final List<PlanDay> days;
  final WeekPattern pattern;
  const PlanOutput({required this.days, required this.pattern});
}

/// 排序：复合优先 → orderWeight 升序 → id 稳定
int _byPriority(Exercise a, Exercise b) {
  if (a.isCompound != b.isCompound) return a.isCompound ? -1 : 1;
  if (a.orderWeight != b.orderWeight) return a.orderWeight - b.orderWeight;
  return a.id.compareTo(b.id);
}

/// 器械过滤（requiredEquipment 语义 = ALL OF）。
List<Exercise> availableExercises(
  String scene,
  List<String> equipmentSet,
  List<Exercise> allExercises,
) {
  final set = equipmentSet.toSet();
  return allExercises.where((e) {
    final sceneOk = e.scenes.contains(scene);
    if (!sceneOk) return false;
    return e.requiredEquipment.every((eq) => eq == 'none' || set.contains(eq));
  }).toList();
}

/// 预计时长（分钟）。
int estimateMinutes(List<PlanEntry> entries) {
  double sec = AppConfig.warmupSec.toDouble();
  for (final en in entries) {
    final avgReps = ((en.repLow + en.repHigh) / 2).toDouble();
    sec += en.targetSets *
        (avgReps * AppConfig.timePerRepSec +
            AppConfig.restDefaultSec +
            AppConfig.transitionPerSetSec);
    sec += AppConfig.setupPerExerciseSec.round();
  }
  return (sec / 60).round();
}

/// 周排期默认值（按 daysPerWeek 选；越界回退到 4 天）。
WeekPattern defaultWeekPattern(
  int daysPerWeek, {
  required Map<int, WeekPattern> weekPatternDefault,
}) {
  final d = (daysPerWeek < 2 || daysPerWeek > 6) ? 4 : daysPerWeek;
  return weekPatternDefault[d] ?? weekPatternDefault[4]!;
}

/// 模板池（5 天以下 vs 以上）。
List<String> templatePoolOf(int days, List<String> le5, List<String> all) {
  if (days <= 5) return le5;
  return all;
}

/// 计划生成（三级降级）。
///   1) 精确 slot（mg + sub）
///   2) 同部位不限 sub
///   3) FALLBACK_MAP 借近亲部位
PlanOutput generatePlan(GeneratePlanInput input) {
  final daysCount = (input.daysPerWeek < 2 || input.daysPerWeek > 6) ? 4 : input.daysPerWeek;
  final tpl = input.templates; // 与 daysCount 等长（业务约定）
  final pool = availableExercises(input.scene, input.equipment, input.allExercises);
  final outDays = <PlanDay>[];

  for (final dayTpl in tpl) {
    final entries = <PlanEntry>[];
    final usedInDay = <String>{};

    for (final slot in dayTpl.slots) {
      // ① 同 mg + 同 sub + 未用
      var cand = pool.where((e) {
        return e.muscleGroup == slot.mg &&
            (slot.sub == null || e.subGroup == slot.sub) &&
            !usedInDay.contains(e.id);
      }).toList();
      cand.sort(_byPriority);
      var picked = cand.take(slot.n).toList();

      // 不足则降级
      if (picked.length < slot.n) {
        final need = slot.n - picked.length;
        final pickedIds = picked.map((e) => e.id).toSet();
        // ② 同 mg 但不限 sub
        var more = pool.where((e) {
          return e.muscleGroup == slot.mg &&
              !usedInDay.contains(e.id) &&
              !pickedIds.contains(e.id);
        }).toList();
        more.sort(_byPriority);
        // ③ FALLBACK_MAP 借近亲
        if (more.length < need) {
          final fbIds = input.fallbackMap[slot.mg] ?? const <String>[];
          final fbCand = pool.where((e) {
            return fbIds.contains(e.muscleGroup) &&
                !usedInDay.contains(e.id) &&
                !pickedIds.contains(e.id);
          }).toList();
          fbCand.sort(_byPriority);
          more = [...more, ...fbCand];
        }
        picked = [...picked, ...more.take(need)];
      }

      for (final ex in picked) {
        usedInDay.add(ex.id);
        entries.add(PlanEntry(
          sortOrder: entries.length + 1,
          exerciseId: ex.id,
          targetSets: ex.defaultSets,
          repLow: ex.repLow,
          repHigh: ex.repHigh,
        ));
      }
    }

    outDays.add(PlanDay(
      code: dayTpl.code,
      name: dayTpl.name,
      entries: entries,
      estMinutes: estimateMinutes(entries),
    ));
  }

  return PlanOutput(
    days: outDays,
    pattern: defaultWeekPattern(daysCount, weekPatternDefault: input.weekPatternDefault),
  );
}

/// 取某天应练的模板（weekday 1=周一）。
PlanDay? getTodayPlan(PlanOutput? plan, String dateStr) {
  if (plan == null) return null;
  final wd = D.weekday1to7(dateStr);
  final code = plan.pattern.at(wd);
  if (code.isEmpty) return null;
  for (final d in plan.days) {
    if (d.code == code) return d;
  }
  return null;
}
