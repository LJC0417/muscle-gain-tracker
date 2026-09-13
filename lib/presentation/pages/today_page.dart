/// 今日页 P-01（ARCHITECTURE F04）
///   - 顶栏：日期
///   - 热量卡：圆环 + P/C/F 三段
///   - 今日训练卡
///   - 今日打卡卡：喝水进度 / 睡眠 stepper
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(todayIntakeProvider);
    final goal = ref.watch(resolvedGoalProvider);
    final habitsAsync = ref.watch(todayHabitsProvider);
    final plan = ref.watch(planProvider);
    final profileAsync = ref.watch(profileStreamProvider);
    final today = ref.watch(todayStringProvider);
    final todayDay = _todayPlanInfo(plan, today);
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _formatDate(today),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textSub,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todayFoodLogsProvider);
          ref.invalidate(todayHabitsProvider);
          ref.invalidate(exercisesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kcalCard(goal, intake),
            const SizedBox(height: 12),
            _trainCard(context, todayDay, exercisesAsync),
            const SizedBox(height: 12),
            _habitCard(context, ref, habitsAsync),
            const SizedBox(height: 12),
            profileAsync.when(
              data: (p) {
                if (p == null) return const SizedBox.shrink();
                final goalAsync = ref.watch(goalStreamProvider);
                return goalAsync.when(
                  data: (g) => g == null
                      ? const SizedBox.shrink()
                      : _BasicInfoCard(p: p, g: g),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
              loading: () => const SizedBox(height: 80),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _kcalCard(ResolvedGoalView goal, TodayIntake intake) {
  final remain = goal.kcal - intake.kcal;
  return MgCard(
    title: '今日热量',
    sub: '目标 ${goal.kcal.toInt()} kcal',
    right: intake.kcal >= goal.kcal
        ? const MgBadge(
            text: '已达标',
            bg: Color(0xFFE7F8EE),
            fg: Color(0xFF177F45),
          )
        : const MgBadge(
            text: '进行中',
            bg: AppPalette.surfaceMuted,
            fg: AppPalette.textSub,
          ),
    child: Row(
      children: [
        RingProgress(
          value: intake.kcal,
          target: goal.kcal,
          centerLabel: intake.kcal.toInt().toString(),
          subLabel: '/ ${goal.kcal.toInt()} kcal',
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              MacroBar(
                pVal: intake.p,
                pTarget: goal.protein,
                cVal: intake.c,
                cTarget: goal.carb,
                fVal: intake.f,
                fTarget: goal.fat,
              ),
              const SizedBox(height: 4),
              Text(
                remain > 0
                    ? '还能吃 ${remain.toInt()} kcal'
                    : '已超 ${(-remain).toInt()} kcal',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textSub,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PlanLite {
  final String code;
  final String name;
  final int estMinutes;
  final List<_PlanEntryLite> entries;
  const _PlanLite({
    required this.code,
    required this.name,
    required this.estMinutes,
    required this.entries,
  });
}

class _PlanEntryLite {
  final int sortOrder;
  final String exerciseId;
  final int targetSets;
  const _PlanEntryLite({
    required this.sortOrder,
    required this.exerciseId,
    required this.targetSets,
  });
}

_PlanLite? _todayPlanInfo(StoredPlan plan, String today) {
  if (plan.isEmpty) return null;
  final wd = _weekday1to7(today);
  final code = plan.pattern[wd];
  if (code == null || code.isEmpty) return null;
  for (final d in plan.days) {
    if (d.code == code) {
      return _PlanLite(
        code: d.code,
        name: d.name,
        estMinutes: d.estMinutes,
        entries: d.entries
            .map((e) => _PlanEntryLite(
                sortOrder: e.sortOrder,
                exerciseId: e.exerciseId,
                targetSets: e.targetSets))
            .toList(),
      );
    }
  }
  return null;
}

int _weekday1to7(String iso) {
  final d = DateTime.parse(iso);
  return ((d.weekday + 6) % 7) + 1;
}

Widget _trainCard(
  BuildContext context,
  _PlanLite? todayDay,
  AsyncValue<List<ExerciseData>> exercisesAsync,
) {
  return MgCard(
    title: '今日训练',
    child: todayDay == null
        ? const _RestDayBody()
        : _TrainingDayBody(
            plan: todayDay,
            exercisesAsync: exercisesAsync,
            onStart: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('本迭代未包含训练执行')),
              );
            },
          ),
  );
}

class _RestDayBody extends StatelessWidget {
  const _RestDayBody();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天休息日',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '好好恢复，肌肉在休息时生长',
                style: TextStyle(
                  fontSize: 13,
                  color: AppPalette.textSub,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppPalette.primaryWeak,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bedtime, color: AppPalette.primary),
        ),
      ],
    );
  }
}

class _TrainingDayBody extends StatelessWidget {
  final _PlanLite plan;
  final AsyncValue<List<ExerciseData>> exercisesAsync;
  final VoidCallback onStart;
  const _TrainingDayBody({
    required this.plan,
    required this.exercisesAsync,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.entries.length} 个动作 · 约 ${plan.estMinutes} 分钟',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppPalette.textSub,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(onPressed: onStart, child: const Text('开始')),
          ],
        ),
        const SizedBox(height: 12),
        exercisesAsync.when(
          data: (all) {
            final map = {for (final e in all) e.id: e};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final en in plan.entries.take(3))
                  Builder(builder: (_) {
                    final ex = map[en.exerciseId];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.fitness_center,
                              size: 16, color: AppPalette.textSub),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ex?.name ?? en.exerciseId,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Text(
                            '${en.targetSets} 组',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppPalette.textSub,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                if (plan.entries.length > 3)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '…等更多动作',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.textWeak,
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: AppPalette.primary,
              backgroundColor: AppPalette.surfaceMuted,
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

Widget _habitCard(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<HabitData?> habitsAsync,
) {
  final water = habitsAsync.value?.waterCups ?? 0;
  final sleep = habitsAsync.value?.sleepHours ?? AppConfig.sleepDefaultH;

  return MgCard(
    title: '今日打卡',
    onTap: () => _openHabitSheet(context, ref, habitsAsync.value),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.water_drop,
                      size: 14, color: AppPalette.textSub),
                  SizedBox(width: 4),
                  Text(
                    '喝水',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.textSub,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$water / ${AppConfig.waterGoalCups} 杯',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _bumpWater(context, ref, water),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (water / AppConfig.waterGoalCups).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppPalette.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppPalette.primary),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '点 +1，长按重置',
                style: TextStyle(
                  fontSize: 11,
                  color: AppPalette.textWeak,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bedtime,
                      size: 14, color: AppPalette.textSub),
                  SizedBox(width: 4),
                  Text(
                    '睡眠',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.textSub,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${sleep.toStringAsFixed(1)} h',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _stepperBtn(
                    onTap: () => _bumpSleep(ref, sleep, -0.5),
                    icon: Icons.remove,
                  ),
                  const SizedBox(width: 8),
                  _stepperBtn(
                    onTap: () => _bumpSleep(ref, sleep, 0.5),
                    icon: Icons.add,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _stepperBtn({required VoidCallback onTap, required IconData icon}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Icon(icon, size: 16, color: AppPalette.textSub),
    ),
  );
}

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 13,
              color: AppPalette.textSub,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

String _formatDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    const wk = ['一', '二', '三', '四', '五', '六', '日'];
    final w = wk[((d.weekday + 6) % 7)];
    return '${d.month}月${d.day}日 · 周$w';
  } catch (_) {
    return iso;
  }
}

Future<void> _bumpWater(
    BuildContext context, WidgetRef ref, int current) async {
  final db = ref.read(databaseProvider);
  final today = ref.read(todayStringProvider);
  final newVal = current + 1;
  final todayHabits = await (db.select(db.habits)
        ..where((t) => t.date.equals(today)))
      .getSingleOrNull();
  final sleepKeep = todayHabits?.sleepHours ?? AppConfig.sleepDefaultH;
  await db.into(db.habits).insertOnConflictUpdate(
        HabitsCompanion.insert(
          date: today,
          waterCups: Value(newVal),
          sleepHours: Value(sleepKeep),
        ),
      );
  ref.invalidate(todayHabitsProvider);
}

Future<void> _bumpSleep(
    WidgetRef ref, double current, double delta) async {
  final db = ref.read(databaseProvider);
  final today = ref.read(todayStringProvider);
  final newSleep = (current + delta).clamp(0.0, 16.0);
  final todayHabits = await (db.select(db.habits)
        ..where((t) => t.date.equals(today)))
      .getSingleOrNull();
  final waterKeep = todayHabits?.waterCups ?? 0;
  await db.into(db.habits).insertOnConflictUpdate(
        HabitsCompanion.insert(
          date: today,
          waterCups: Value(waterKeep),
          sleepHours: Value(newSleep),
        ),
      );
  ref.invalidate(todayHabitsProvider);
}

/// 点击卡片时打开的 sheet（保留入口；F04 不强制展开）。
Future<void> _openHabitSheet(
  BuildContext context,
  WidgetRef ref,
  HabitData? current,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      int water = current?.waterCups ?? 0;
      double sleep = current?.sleepHours ?? AppConfig.sleepDefaultH;
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '今日打卡',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '喝水（目标 ${AppConfig.waterGoalCups} 杯）',
                      style: TextStyle(fontSize: 14),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(
                              () => water = (water - 1).clamp(0, 20)),
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '$water',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => water = (water + 1).clamp(0, 20)),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('睡眠（h）',
                        style: TextStyle(fontSize: 14)),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(
                              () => sleep = (sleep - 0.5).clamp(0.0, 16.0)),
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text(
                            sleep.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(
                              () => sleep = (sleep + 0.5).clamp(0.0, 16.0)),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    final today = ref.read(todayStringProvider);
                    await db.into(db.habits).insertOnConflictUpdate(
                          HabitsCompanion.insert(
                            date: today,
                            waterCups: Value(water),
                            sleepHours: Value(sleep),
                          ),
                        );
                    ref.invalidate(todayHabitsProvider);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('保存打卡'),
                ),
              ],
            ),
          );
},
    );
  },
  );
}

int math_max(int a, int b) => a > b ? a : b;

/// 「基础信息」卡（PROFILE 已 ready + GOAL 已 ready 才渲染）。
class _BasicInfoCard extends StatelessWidget {
  final ProfileData p;
  final GoalData g;
  const _BasicInfoCard({required this.p, required this.g});

  @override
  Widget build(BuildContext context) {
    return MgCard(
      title: '基础信息',
      child: Column(
        children: [
          _kv('性别 / 年龄',
              '${AppConfig.labels[p.sex] ?? p.sex} · ${p.age} 岁'),
          _kv('身高', '${p.heightCm.toStringAsFixed(0)} cm'),
          _kv('活动系数', p.activityFactor.toStringAsFixed(2)),
          _kv(
            '当前 → 目标体重',
            '${g.currentWeightKg.toStringAsFixed(1)} → '
            '${g.targetWeightKg.toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
  }
}
