/// 饮食页 P-02/P-03（ARCHITECTURE F04 + F05 补全）
///
/// 布局对齐原型 prototype/pages/diet.js —— **单页滚动，四餐别同页可见**：
///   ① 今日营养概览卡（kcal + P/C/F）+ 一键清空
///   ② 营养摄入卡：早/午/晚/加 四个 section 依次展开，每条记录可直接删除
///   ③ 推荐食物清单卡：分类 chips 切换 + 最多 24 条，点 ＋ 快速加入加餐
///
/// 历史问题：早期版本用 TabBarView 分餐别 + 底部固定高度的推荐卡，
/// 把「已记录食物」的列表高度挤到几乎为 0，用户看不到自己加了什么，
/// 也看不到单项删除按钮。现已改为与原型一致的全量滚动布局。
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

class _DietPageState extends ConsumerState<DietPage> {
  /// 推荐清单当前分类（原型默认「肉蛋」）。
  String _recCat = 'meat';

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(todayIntakeProvider);
    final goal = ref.watch(resolvedGoalProvider);
    final today = ref.watch(todayStringProvider);
    final logsAsync = ref.watch(todayFoodLogsProvider);
    final mealNames = ref.watch(mealNamesProvider);
    final logs = logsAsync.value ?? const <FoodLogData>[];

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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _overviewCard(intake, goal),
          const SizedBox(height: 12),
          _intakeCard(logs, mealNames),
          const SizedBox(height: 12),
          _recommendCard(mealNames),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ① 今日营养概览
  // ════════════════════════════════════════════════════════════════

  Widget _overviewCard(TodayIntake intake, ResolvedGoalView goal) {
    final remain = goal.kcal - intake.kcal;
    return MgCard(
      title: '今日营养',
      sub: remain > 0
          ? '剩余可吃 ${remain.toInt()} kcal'
          : '已超 ${(-remain).toInt()} kcal',
      right: TextButton.icon(
        onPressed: _clearTodayFood,
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
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ② 营养摄入（4 餐别同页展开）
  // ════════════════════════════════════════════════════════════════

  Widget _intakeCard(
    List<FoodLogData> logs,
    Map<String, String> mealNames,
  ) {
    final meals = AppConfig.mealSlot;
    return MgCard(
      title: '营养摄入',
      sub: '点餐别右侧「添加」记一条；点右侧垃圾桶删除单条',
      right: TextButton.icon(
        onPressed: _editMealNames,
        icon: const Icon(Icons.edit_outlined, size: 14),
        label: const Text('编辑命名', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < meals.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            _mealSection(
              meal: meals[i],
              label: mealNames[meals[i]] ?? (AppConfig.labels[meals[i]] ?? meals[i]),
              logs: logs.where((l) => l.meal == meals[i]).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mealSection({
    required String meal,
    required String label,
    required List<FoodLogData> logs,
  }) {
    final sum = logs.fold<double>(0, (a, l) => a + l.kcal);
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
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${logs.length} 项 · ${sum.toInt()} kcal',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppPalette.textSub,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => showFoodPickerSheet(context, initialMeal: meal),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (logs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '暂无记录',
              style: TextStyle(fontSize: 13, color: AppPalette.textWeak),
            ),
          )
        else
          for (final l in logs) _mealRow(l),
      ],
    );
  }

  Widget _mealRow(FoodLogData l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l.foodName,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (l.isEstimate) ...[
                      const SizedBox(width: 4),
                      const MgBadge(
                        text: '估',
                        bg: AppPalette.surfaceMuted,
                        fg: AppPalette.textSub,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_g(l.grams)}g · ${l.kcal.toInt()} kcal · '
                  '${_g(l.p)}P/${_g(l.c)}C/${_g(l.f)}F',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textSub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 单条删除（原型 meal-row-del）：图标按钮本身可见，无需长按或滑动
          SizedBox(
            width: 36,
            height: 34,
            child: IconButton.outlined(
              tooltip: '删除这一条',
              padding: EdgeInsets.zero,
              iconSize: 17,
              onPressed: () => _removeLog(l),
              icon: const Icon(Icons.delete_outline,
                  color: AppPalette.textSub),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ③ 推荐食物清单（分类切换 + 最多 24 条）
  // ════════════════════════════════════════════════════════════════

  Widget _recommendCard(Map<String, String> mealNames) {
    final foods = ref.watch(foodsProvider).value ?? const <FoodLite>[];
    final snackName = mealNames['snack'] ?? '加餐';

    final pool = (_recCat == 'all'
            ? foods
            : foods.where((f) => f.category == _recCat))
        .toList()
      ..sort((a, b) => b.p.compareTo(a.p));
    final shown = pool.take(24).toList();

    return MgCard(
      title: '推荐食物清单',
      sub: '按蛋白优先排序 · 共 ${pool.length} 种 · 点 ＋ 快速加入$snackName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _recChip('all', '全部'),
                for (final c in AppConfig.foodCategory)
                  _recChip(c, AppConfig.labels[c] ?? c),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '该分类下暂无食物',
                style: TextStyle(fontSize: 13, color: AppPalette.textWeak),
              ),
            )
          else
            for (final f in shown) _recRow(f),
          if (pool.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '仅显示蛋白含量最高的 ${shown.length} 种（共 ${pool.length} 种），'
                '其它可用上方「添加」搜索',
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textWeak),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recChip(String key, String label) {
    final sel = _recCat == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        selectedColor: AppPalette.primaryWeak,
        labelStyle: TextStyle(
            color: sel ? AppPalette.primaryDark : AppPalette.textSub,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
        side: BorderSide(color: sel ? AppPalette.primary : AppPalette.border),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _recCat = key),
      ),
    );
  }

  Widget _recRow(FoodLite f) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        f.name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (f.isEstimate) ...[
                      const SizedBox(width: 4),
                      const MgBadge(
                        text: '估',
                        bg: AppPalette.surfaceMuted,
                        fg: AppPalette.textSub,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${f.servingGrams.toInt()}g/份 · ${f.kcal.toInt()} kcal · '
                  '${f.p.toInt()}P/${f.c.toInt()}C/${f.f.toInt()}F',
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.textSub),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            height: 34,
            child: IconButton.outlined(
              tooltip: '加入加餐',
              padding: EdgeInsets.zero,
              iconSize: 17,
              onPressed: () => _quickAdd(f),
              icon: const Icon(Icons.add, color: AppPalette.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 行为
  // ════════════════════════════════════════════════════════════════

  /// 推荐清单「＋」：加入加餐（对齐原型 quickAdd）。
  Future<void> _quickAdd(FoodLite f) async {
    final db = ref.read(databaseProvider);
    final today = ref.read(todayStringProvider);
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: 'fl_${DateTime.now().microsecondsSinceEpoch}',
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
    ref.invalidate(todayIntakeProvider);
    if (!mounted) return;
    final mealLabel = ref.read(mealNamesProvider)['snack'] ?? '加餐';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('已加入$mealLabel · ${f.name} ${f.kcal.toInt()} kcal')),
      );
  }

  /// 删除单条记录（对齐原型 removeLog：确认后删除）。
  Future<void> _removeLog(FoodLogData l) async {
    final ok = await _confirm(
      context,
      title: '删除这条记录？',
      message: '${l.foodName} · ${l.kcal.toInt()} kcal',
    );
    if (!ok) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.foodLogs)..where((t) => t.id.equals(l.id))).go();
    ref.invalidate(todayFoodLogsProvider);
    ref.invalidate(todayIntakeProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已删除 ${l.foodName}')));
  }

  /// 一键清空今日所有饮食。
  Future<void> _clearTodayFood() async {
    final logs = ref.read(todayFoodLogsProvider).valueOrNull ?? const [];
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今天还没有饮食记录')),
      );
      return;
    }
    final ok = await _confirm(
      context,
      title: '清空今日所有饮食记录？',
      message: '将删除今天 ${logs.length} 条记录，此操作不可撤销。',
      confirmText: '一键清空',
    );
    if (!ok) return;
    final db = ref.read(databaseProvider);
    final today = ref.read(todayStringProvider);
    await (db.delete(db.foodLogs)..where((t) => t.date.equals(today))).go();
    ref.invalidate(todayFoodLogsProvider);
    ref.invalidate(todayIntakeProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清空今日 ${logs.length} 条饮食记录')),
    );
  }

  /// 餐别命名编辑弹层。
  Future<void> _editMealNames() async {
    final db = ref.read(databaseProvider);
    final current = ref.read(mealNamesProvider);
    final ctrls = {
      for (final k in AppConfig.mealSlot)
        k: TextEditingController(
            text: current[k] ?? (AppConfig.labels[k] ?? k)),
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
        child: ListView(
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
    );
    if (saved != true) return;
    final names = <String, String>{
      for (final k in AppConfig.mealSlot)
        k: ctrls[k]!.text.trim().isEmpty
            ? (AppConfig.labels[k] ?? k)
            : ctrls[k]!.text.trim(),
    };
    for (final c in ctrls.values) {
      c.dispose();
    }
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
// 工具
// ════════════════════════════════════════════════════════════════════

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

/// 宏量/克数展示：不补小数位（46.0 → 46，46.5 → 46）。
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
