/// 饮食页 P-02/P-03（ARCHITECTURE F04 + F05 补全）
///   - 顶部今日总览（kcal + P/C/F 四段）+ 一键清空
///   - 4 个餐别 tab + 添加（食物选择器弹层：搜索/分类/餐别切换/撤销）
///   - 餐别命名编辑（AppSettings['mealNames']）
///   - 推荐食物清单（按蛋白优先排序，快速加入第 4 餐）
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/foods_provider.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/food_picker_sheet.dart';
import '../widgets/mg_widgets.dart';

class DietPage extends ConsumerStatefulWidget {
  const DietPage({super.key});

  @override
  ConsumerState<DietPage> createState() => _DietPageState();
}

class _DietPageState extends ConsumerState<DietPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: AppConfig.mealSlot.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(todayIntakeProvider);
    final goal = ref.watch(resolvedGoalProvider);
    final today = ref.watch(todayStringProvider);
    final logsAsync = ref.watch(todayFoodLogsProvider);
    final mealNames = ref.watch(mealNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('饮食'),
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
        bottom: TabBar(
          controller: _tab,
          labelColor: AppPalette.primary,
          unselectedLabelColor: AppPalette.textSub,
          indicatorColor: AppPalette.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [
            for (final m in AppConfig.mealSlot)
              Tab(text: mealNames[m] ?? (AppConfig.labels[m] ?? m)),
          ],
        ),
      ),
      body: Column(
        children: [
          _overviewCard(context, ref, intake, goal, logsAsync),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final m in AppConfig.mealSlot)
                  _MealTab(
                    meal: m,
                    logsAsync: logsAsync,
                    mealName: mealNames[m] ?? (AppConfig.labels[m] ?? m),
                  ),
              ],
            ),
          ),
          _recommendCard(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 推荐食物清单（按蛋白优先排序，快速加入第 4 餐）。
  Widget _recommendCard() {
    final foodsAsync = ref.watch(foodsProvider);
    final mealNames = ref.watch(mealNamesProvider);
    final all = foodsAsync.value ?? const <FoodLite>[];
    final rec = all
        .where((f) => f.category == 'meat')
        .toList()
      ..sort((a, b) => b.p.compareTo(a.p));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MgCard(
        title: '推荐食物清单',
        sub: '按蛋白优先排序 · 点 ＋ 快速加入${mealNames['snack'] ?? '加餐'}',
        right: TextButton.icon(
          onPressed: _editMealNames,
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('编辑命名', style: TextStyle(fontSize: 12)),
        ),
        child: Column(
          children: [
            for (final f in rec.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              style: const TextStyle(fontSize: 14)),
                          Text(
                            '${f.kcal.toInt()} kcal · '
                            '${f.p.toInt()}P/${f.c.toInt()}C/${f.f.toInt()}F',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppPalette.textSub),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 32,
                      child: IconButton.outlined(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        onPressed: () => _quickAdd(f),
                        icon: const Icon(Icons.add,
                            color: AppPalette.primary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickAdd(FoodLite f) async {
    final db = ref.read(databaseProvider);
    final today = ref.read(todayStringProvider);
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'fl_${DateTime.now().millisecondsSinceEpoch}',
          date: today,
          meal: 'snack',
          foodId: f.id,
          foodName: f.name,
          grams: f.servingGrams,
          kcal: f.kcal,
          p: f.p,
          c: f.c,
          f: f.f,
          isEstimate: Value(f.isEstimate),
          createdAt: Value(DateTime.now()),
        ));
    ref.invalidate(todayFoodLogsProvider);
    if (!mounted) return;
    final mealLabel = ref.read(mealNamesProvider)['snack'] ?? '加餐';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入$mealLabel · ${f.name} ${f.kcal.toInt()} kcal')),
    );
  }

  /// 餐别命名编辑弹层。
  Future<void> _editMealNames() async {
    final db = ref.read(databaseProvider);
    final current = ref.read(mealNamesProvider);
    final ctrls = {
      for (final k in AppConfig.mealSlot)
        k: TextEditingController(text: current[k] ?? k),
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              const Text('自定义餐别名称',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                '把 4 个餐别改成你习惯的叫法，比如「上午加餐」「练后餐」等。',
                style: TextStyle(fontSize: 13, color: AppPalette.textSub),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < AppConfig.mealSlot.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrls[AppConfig.mealSlot[i]],
                    decoration: InputDecoration(
                      labelText: '第 ${i + 1} 餐',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final names = {
      for (final k in AppConfig.mealSlot) k: ctrls[k]!.text.trim(),
    };
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'mealNames',
            value: jsonEncode(names),
          ),
        );
    ref.invalidate(appSettingsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存餐别命名')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 总览卡
// ════════════════════════════════════════════════════════════════════

Widget _overviewCard(
  BuildContext context,
  WidgetRef ref,
  TodayIntake intake,
  ResolvedGoalView goal,
  AsyncValue<List<FoodLogData>> logsAsync,
) {
  final remain = goal.kcal - intake.kcal;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: MgCard(
      title: '今日营养',
      sub: remain > 0
          ? '剩余可吃 ${remain.toInt()} kcal'
          : '已超 ${(-remain).toInt()} kcal',
      right: TextButton.icon(
        onPressed: () => _clearTodayFood(context, ref),
        icon: const Icon(Icons.delete_sweep_outlined,
            size: 16, color: AppPalette.danger),
        label: const Text('一键清空',
            style: TextStyle(fontSize: 12, color: AppPalette.danger)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: _kpi('${intake.kcal.toInt()}/${goal.kcal.toInt()}',
                  '热量 kcal'),
            ),
            Expanded(
              child: _kpi('${_g(intake.p)}/${_g(goal.protein)}', '蛋白 g'),
            ),
            Expanded(
              child: _kpi('${_g(intake.c)}/${_g(goal.carb)}', '碳水 g'),
            ),
            Expanded(
              child: _kpi('${_g(intake.f)}/${_g(goal.fat)}', '脂肪 g'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 一键清空今日所有饮食（确认后删除）。
Future<void> _clearTodayFood(BuildContext context, WidgetRef ref) async {
  final logs = ref.read(todayFoodLogsProvider).valueOrNull ?? const [];
  if (logs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今天还没有饮食记录')),
    );
    return;
  }
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清空今日所有饮食记录？'),
      content: const Text('将删除今天的所有餐别记录，此操作不可撤销。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('一键清空'),
        ),
      ],
    ),
  );
  if (res != true) return;
  final db = ref.read(databaseProvider);
  final today = ref.read(todayStringProvider);
  await (db.delete(db.foodLogs)..where((t) => t.date.equals(today))).go();
  ref.invalidate(todayFoodLogsProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已清空今日 ${logs.length} 条饮食记录')),
  );
}

Widget _kpi(String v, String l) {
  return Column(
    children: [
      Text(
        v,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        l,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          color: AppPalette.textSub,
        ),
      ),
    ],
  );
}

// ════════════════════════════════════════════════════════════════════
// 每个餐别的 tab 内容
// ════════════════════════════════════════════════════════════════════

class _MealTab extends ConsumerWidget {
  final String meal;
  final String mealName;
  final AsyncValue<List<FoodLogData>> logsAsync;

  const _MealTab({
    required this.meal,
    required this.mealName,
    required this.logsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return logsAsync.when(
      data: (all) {
        final logs = all.where((l) => l.meal == meal).toList();
        final sum = logs.fold<double>(0, (a, l) => a + l.kcal);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _mealHeader(context, logs.length, sum),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '暂无记录',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.textWeak,
                    ),
                  ),
                ),
              )
            else
              for (final l in logs) _mealRow(context, ref, l),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppPalette.primary),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('加载失败：$e'),
        ),
      ),
    );
  }

  Widget _mealHeader(BuildContext context, int count, double sumKcal) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mealName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count 项 · ${sumKcal.toInt()} kcal',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textSub,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              showFoodPickerSheet(context, initialMeal: meal),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加'),
        ),
      ],
    );
  }

  Widget _mealRow(
    BuildContext context,
    WidgetRef ref,
    FoodLogData l,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.foodName,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l.kcal.toInt()} kcal · '
                  '${_g(l.p)}P · ${_g(l.c)}C · ${_g(l.f)}F',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textSub,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            iconSize: 18,
            onPressed: () async {
              final ok = await _confirm(
                context,
                title: '删除这条记录？',
                message: '${l.foodName} · ${l.kcal.toInt()} kcal',
              );
              if (!ok) return;
              final db = ref.read(databaseProvider);
              await (db.delete(db.foodLogs)
                    ..where((t) => t.id.equals(l.id)))
                  .go();
              ref.invalidate(todayFoodLogsProvider);
              ref.invalidate(todayIntakeProvider);
            },
            icon: const Icon(Icons.delete_outline,
                color: AppPalette.textSub),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 工具
// ════════════════════════════════════════════════════════════════════

String _g(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(0);
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

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '删除',
  bool danger = true,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppPalette.danger : AppPalette.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return res ?? false;
}
