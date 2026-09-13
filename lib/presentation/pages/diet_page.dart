/// 饮食页 P-02（ARCHITECTURE F04）
///   - 顶部今日总览（kcal + P/C/F 四段）
///   - 4 个餐别 tab（早/午/晚/加）+ 每餐已记录食物 + 添加按钮（本迭代未包含）
///   - 「一键清空今日食物」按钮：AlertDialog 确认
///
/// 本期不实现：食物选择器、推荐食物清单、餐别命名编辑。
/// 所有「添加」按钮统一 SnackBar「本迭代未包含食物选择器」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';
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
              Tab(text: AppConfig.labels[m] ?? m),
          ],
        ),
      ),
      body: Column(
        children: [
          _overviewCard(intake, goal),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final m in AppConfig.mealSlot)
                  _MealTab(
                    meal: m,
                    logsAsync: logsAsync,
                    onAdd: _blockedAddSnack,
                    onClearAll: _blockedAddSnack,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _blockedAddSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本迭代未包含食物选择器')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 总览卡
// ════════════════════════════════════════════════════════════════════

Widget _overviewCard(TodayIntake intake, ResolvedGoalView goal) {
  final remain = goal.kcal - intake.kcal;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: MgCard(
      title: '今日营养',
      sub: remain > 0
          ? '剩余可吃 ${remain.toInt()} kcal'
          : '已超 ${(-remain).toInt()} kcal',
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
  final AsyncValue<List<FoodLogData>> logsAsync;
  final VoidCallback onAdd;
  final VoidCallback onClearAll;

  const _MealTab({
    required this.meal,
    required this.logsAsync,
    required this.onAdd,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = AppConfig.labels[meal] ?? meal;

    return logsAsync.when(
      data: (all) {
        final logs = all.where((l) => l.meal == meal).toList();
        final sum = logs.fold<double>(0, (a, l) => a + l.kcal);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _mealHeader(label, logs.length, sum, onAdd),
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('清空今日食物'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: AppPalette.danger,
                side: const BorderSide(color: Color(0xFFFEE2E2)),
              ),
            ),
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

  Widget _mealHeader(String label, int count, double sumKcal, VoidCallback onAdd) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
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
          onPressed: onAdd,
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
