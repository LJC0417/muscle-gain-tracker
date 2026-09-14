/// 食物数据 Provider（P-02/P-03）
/// 数据源：
///   1) assets/data/foods.json（内置 300+ 食物，每份营养）
///   2) CustomFoods 表（用户自定义，每 100g 营养 + 默认克数）
/// 合并后统一为 FoodLite（每份口径），source='builtin' | 'custom'。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import 'database_provider.dart';
import 'providers/app_providers.dart' show appSettingsProvider;

/// 统一食物模型（每份口径）。
class FoodLite {
  final String id;
  final String name;
  final String py; // 拼音首字母，小写
  final String category;
  final double servingGrams;
  final double kcal;
  final double p;
  final double c;
  final double f;
  final bool isEstimate;
  final String source; // builtin | custom

  const FoodLite({
    required this.id,
    required this.name,
    required this.py,
    required this.category,
    required this.servingGrams,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    required this.isEstimate,
    required this.source,
  });
}

final foodsProvider = FutureProvider<List<FoodLite>>((ref) async {
  final db = await ref.watch(databaseReadyProvider.future);

  // 1) 内置食物（每份口径）
  final raw = await rootBundle.loadString('assets/data/foods.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final list = <FoodLite>[];
  for (final f in (decoded['foods'] as List<dynamic>? ?? const [])) {
    final m = Map<String, dynamic>.from(f as Map);
    list.add(FoodLite(
      id: m['id'] as String,
      name: m['name'] as String,
      py: (m['py'] as String?) ?? '',
      category: m['category'] as String,
      servingGrams: (m['servingGrams'] as num?)?.toDouble() ?? 100,
      kcal: (m['kcal'] as num?)?.toDouble() ?? 0,
      p: (m['p'] as num?)?.toDouble() ?? 0,
      c: (m['c'] as num?)?.toDouble() ?? 0,
      f: (m['f'] as num?)?.toDouble() ?? 0,
      isEstimate: (m['isEstimate'] as bool?) ?? false,
      source: 'builtin',
    ));
  }

  // 2) 用户自定义食物（每 100g → 按 defaultGrams 折算每份）
  final customs = await db.select(db.customFoods).get();
  for (final c in customs) {
    final g = c.defaultGrams <= 0 ? 100.0 : c.defaultGrams;
    final k = g / 100.0;
    list.add(FoodLite(
      id: c.id,
      name: c.name,
      py: '',
      category: c.category,
      servingGrams: g,
      kcal: c.kcalPer100 * k,
      p: c.pPer100 * k,
      c: c.cPer100 * k,
      f: c.fPer100 * k,
      isEstimate: false,
      source: 'custom',
    ));
  }
  return list;
});

/// 食物搜索（名称包含 或 拼音首字母前缀/包含）。
List<FoodLite> filterFoods(
  List<FoodLite> all, {
  String category = 'all',
  String query = '',
}) {
  Iterable<FoodLite> out = all;
  if (category != 'all' && category != 'custom') {
    out = out.where((f) => f.category == category);
  } else if (category == 'custom') {
    out = out.where((f) => f.source == 'custom');
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    out = out.where((f) =>
        f.name.contains(query.trim()) || (f.py.isNotEmpty && f.py.contains(q)));
  }
  return out.toList();
}

/// 餐别命名（AppSettings.key='mealNames'，JSON map）。
final mealNamesProvider = Provider<Map<String, String>>((ref) {
  final settings = ref.watch(appSettingsProvider).when(
        data: (v) => v,
        loading: () => <String, String>{},
        error: (_, __) => <String, String>{},
      );
  const fallback = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '额外摄入',
  };
  final raw = settings['mealNames'];
  if (raw == null || raw.isEmpty) return fallback;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final k in fallback.keys)
        k: (m[k] as String?)?.isNotEmpty == true ? m[k] as String : fallback[k]!,
    };
  } catch (_) {
    return fallback;
  }
});
