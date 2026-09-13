/// Drift 数据库全局 Provider（ARCHITECTURE F01）
/// 使用 drift_flutter.driftDatabase 在桌面/移动端均能自动选合适实现。
/// F04 之前数据库需要做 seed loader 的初始化，因此暴露一个 [databaseReadyProvider]
/// 持有 AppDatabase + 完成首次 seed 的 Future。
library;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/seed_loader.dart';

/// AppDatabase 单例。
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'mg'));
  ref.onDispose(db.close);
  return db;
});

/// 首次启动自动 seed（Exercises 表为空时灌入 42 个动作）。
/// 调用 `await ref.read(databaseReadyProvider.future)` 等待完成。
final databaseReadyProvider = FutureProvider<AppDatabase>((ref) async {
  final db = ref.watch(databaseProvider);
  await seedExercisesIfEmpty(db);
  return db;
});
