/// 添加饮食弹层（P-02 对齐 prototype app.js openAddFood）
///   - 4 餐别 SegmentedControl 切换
///   - 搜索（名称/拼音首字母）+ 分类 chips + 列表点击添加
///   - 添加成功 SnackBar 带撤销
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/foods_provider.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

/// 打开添加饮食弹层。[initialMeal] 可从外部指定餐别。
Future<void> showFoodPickerSheet(
  BuildContext context, {
  String initialMeal = 'snack',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => FoodPickerSheet(initialMeal: initialMeal),
  );
}

class FoodPickerSheet extends ConsumerStatefulWidget {
  final String initialMeal;
  const FoodPickerSheet({super.key, required this.initialMeal});

  @override
  ConsumerState<FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<FoodPickerSheet> {
  late String _meal;
  String _cat = 'all';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _meal = AppConfig.mealSlot.contains(widget.initialMeal)
        ? widget.initialMeal
        : 'snack';
  }

  @override
  Widget build(BuildContext context) {
    final foodsAsync = ref.watch(foodsProvider);
    final mealNames = ref.watch(mealNamesProvider);
    final list = filterFoods(
      foodsAsync.value ?? const <FoodLite>[],
      category: _cat,
      query: _q,
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Text('添加饮食',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                for (final m in AppConfig.mealSlot)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(mealNames[m] ?? m,
                          style: const TextStyle(fontSize: 13)),
                      selected: _meal == m,
                      selectedColor: AppPalette.primaryWeak,
                      labelStyle: TextStyle(
                          color: _meal == m
                              ? AppPalette.primaryDark
                              : AppPalette.textSub,
                          fontWeight: _meal == m
                              ? FontWeight.w600
                              : FontWeight.w400),
                      side: BorderSide(
                          color: _meal == m
                              ? AppPalette.primary
                              : AppPalette.border),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _meal = m),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: '搜索食物（名称或拼音首字母）',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              children: [
                _chip('all', '全部'),
                _chip('custom', '自定义'),
                for (final c in AppConfig.foodCategory)
                  _chip(c, AppConfig.labels[c] ?? c),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('没有找到，换个关键词试试',
                        style:
                            TextStyle(fontSize: 13, color: AppPalette.textSub)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      for (final f in list.take(60))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(f.name,
                                    style: const TextStyle(fontSize: 14)),
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
                          subtitle: Text(
                            '${f.kcal.toInt()} kcal · '
                            '${f.p.toInt()}P/${f.c.toInt()}C/${f.f.toInt()}F'
                            ' · ${f.servingGrams.toInt()}g/份',
                            style: const TextStyle(
                                fontSize: 12, color: AppPalette.textSub),
                          ),
                          trailing: const Icon(Icons.add,
                              color: AppPalette.primary),
                          onTap: () => _append(f),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _append(FoodLite f) async {
    final db = ref.read(databaseReadyProvider).requireValue;
    final today = ref.read(todayStringProvider);
    final logId = 'fl_${DateTime.now().millisecondsSinceEpoch}';
    await db.into(db.foodLogs).insert(FoodLogsCompanion.insert(
          id: logId,
          date: today,
          meal: _meal,
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
    final mealLabel = ref.read(mealNamesProvider)[_meal] ?? _meal;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已加入$mealLabel · ${f.name} ${f.kcal.toInt()} kcal'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await (db.delete(db.foodLogs)..where((t) => t.id.equals(logId)))
                .go();
            ref.invalidate(todayFoodLogsProvider);
          },
        ),
      ));
    Navigator.pop(context);
  }

  Widget _chip(String key, String label) {
    final sel = _cat == key;
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
        onSelected: (_) => setState(() => _cat = key),
      ),
    );
  }
}
