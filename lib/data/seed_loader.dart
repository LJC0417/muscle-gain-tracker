/// Seed loader（ARCHITECTURE F01）
/// 从 assets/data/exercises.json 读 42 个动作灌入 Exercises 表。
/// 启动时由 main 调一次；idempotent（Exercises 表已有数据就跳过）。
///
/// 食物 assets/data/foods.json 暂不写入 DB（13 张表里未设计 Foods 表，F04 砍掉了食物选择器）；
/// 留 foods.json 仅为下一版准备。如需追加食物，可在 CustomFoods 表写入。
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'database.dart';

/// 动作 JSON 顶层结构（取自 prototype/data/exercises.js）。
class ExercisesSeed {
  final int version;
  final List<Map<String, dynamic>> exercises;
  const ExercisesSeed({required this.version, required this.exercises});
}

/// 食物 JSON 顶层结构（取自 prototype/data/foods.js）。
class FoodsSeed {
  final int version;
  final List<Map<String, dynamic>> foods;
  const FoodsSeed({required this.version, required this.foods});
}

/// 读取并解析 assets/data/exercises.json。
Future<ExercisesSeed> loadExercisesSeed() async {
  final raw = await rootBundle.loadString('assets/data/exercises.json');
  final m = jsonDecode(raw) as Map<String, dynamic>;
  return ExercisesSeed(
    version: (m['version'] as num).toInt(),
    exercises: (m['exercises'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

/// 读取并解析 assets/data/foods.json。
Future<FoodsSeed> loadFoodsSeed() async {
  final raw = await rootBundle.loadString('assets/data/foods.json');
  final m = jsonDecode(raw) as Map<String, dynamic>;
  return FoodsSeed(
    version: (m['version'] as num).toInt(),
    foods: (m['foods'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

/// 把 seed 写进 Exercises 表（仅当表为空时）。
/// 返回写入的条数（0 = 已存在，跳过）。
Future<int> seedExercisesIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.exercises).get();
  if (existing.isNotEmpty) return 0;

  final seed = await loadExercisesSeed();
  await db.batch((b) {
    for (final e in seed.exercises) {
      b.insert(
        db.exercises,
        ExercisesCompanion.insert(
          id: e['id'] as String,
          name: e['name'] as String,
          muscleGroup: e['muscleGroup'] as String,
          subGroup: Value<String?>(e['subGroup'] as String?),
          isCompound: Value<bool>(e['isCompound'] as bool? ?? true),
          requiredEquipmentJson: Value<String>(
            jsonEncode((e['requiredEquipment'] as List<dynamic>)
                .map((s) => s.toString())
                .toList()),
          ),
          scenesJson: Value<String>(
            jsonEncode((e['scenes'] as List<dynamic>)
                .map((s) => s.toString())
                .toList()),
          ),
          defaultSets: Value<int>(e['defaultSets'] as int? ?? 3),
          repLow: Value<double>(
            ((e['repLow'] as num?)?.toDouble() ?? 8),
          ),
          repHigh: Value<double>(
            ((e['repHigh'] as num?)?.toDouble() ?? 12),
          ),
          isBodyweight: Value<bool>(e['isBodyweight'] as bool? ?? false),
          orderWeight: Value<int>(e['orderWeight'] as int? ?? 99),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });
  return seed.exercises.length;
}

/// 灌完后清掉 CustomFoods + FoodLogs（保留内置 Exercises）。
/// F04 「我的 · 清空所有数据」按钮会触发。
Future<void> wipeAllUserData(AppDatabase db) async {
  await db.transaction(() async {
    await db.delete(db.weightPoints).go();
    await db.delete(db.foodLogs).go();
    await db.delete(db.trainingSessions).go();
    await db.delete(db.workoutSets).go();
    await db.delete(db.habits).go();
    await db.delete(db.weeklyReviews).go();
    await db.delete(db.mealNames).go();
    await db.delete(db.appSettings).go();
    await db.delete(db.customFoods).go();
    await db.delete(db.aiReviewMeta).go();
    await db.delete(db.sleepSessions).go();
    await db.delete(db.sleepStageRows).go();
    await db.delete(db.sleepMetrics).go();
    // Profiles / Goals 整行删除，重新走引导；Exercises 表保留内置。
    await db.delete(db.profiles).go();
    await db.delete(db.goals).go();
  });
}
