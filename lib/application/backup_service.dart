/// JSON 备份导出 / 导入（P-10 数据管理）
///   - 导出：11 张用户表 → 单个 JSON → share_plus 分享（可存网盘/发给自己）
///   - 导入：校验格式 → 清空用户表 → 原样恢复（不动 Exercises 内置动作库）
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../data/seed_loader.dart' show wipeAllUserData;
import 'backup_row_mapping.dart' show backupDateColumns, mapBackupRow;

export 'backup_row_mapping.dart' show camelToSnake, mapBackupRow;

const _backupVersion = 1;

/// 各表中的 DateTime 列定义见 backup_row_mapping.dart（backupDateColumns）。
final _dateColumns = backupDateColumns;

Future<List<Map<String, dynamic>>> _rows(
  AppDatabase db,
  TableInfo<Table, dynamic> table,
) async {
  final list = await db.select(table).get();
  return [
    for (final r in list) (r as dynamic).toJson() as Map<String, dynamic>,
  ];
}

Future<Map<String, dynamic>> _dumpAll(AppDatabase db) async {
  final profiles = await _rows(db, db.profiles);
  final goals = await _rows(db, db.goals);
  final weightPoints = await _rows(db, db.weightPoints);
  final foodLogs = await _rows(db, db.foodLogs);
  final trainingSessions = await _rows(db, db.trainingSessions);
  final workoutSets = await _rows(db, db.workoutSets);
  final habits = await _rows(db, db.habits);
  final weeklyReviews = await _rows(db, db.weeklyReviews);
  final mealNames = await _rows(db, db.mealNames);
  final appSettings = await _rows(db, db.appSettings);
  final customFoods = await _rows(db, db.customFoods);
  final sleepSessions = await _rows(db, db.sleepSessions);
  final sleepStageRows = await _rows(db, db.sleepStageRows);
  final sleepMetrics = await _rows(db, db.sleepMetrics);

  return {
    'app': 'muscle-gain-tracker',
    'version': _backupVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'profiles': profiles,
    'goals': goals,
    'weightPoints': weightPoints,
    'foodLogs': foodLogs,
    'trainingSessions': trainingSessions,
    'workoutSets': workoutSets,
    'habits': habits,
    'weeklyReviews': weeklyReviews,
    'mealNames': mealNames,
    'appSettings': appSettings,
    'customFoods': customFoods,
    'sleepSessions': sleepSessions,
    'sleepStageRows': sleepStageRows,
    'sleepMetrics': sleepMetrics,
  };
}

/// 导出备份并调起系统分享。返回是否成功。
Future<bool> exportBackup(AppDatabase db) async {
  try {
    final json = jsonEncode(await _dumpAll(db));
    final now = DateTime.now();
    final name =
        'mg-backup-${now.year}${_p2(now.month)}${_p2(now.day)}-${_p2(now.hour)}${_p2(now.minute)}.json';
    final file = XFile.fromData(
      utf8.encode(json),
      name: name,
      mimeType: 'application/json',
    );
    await Share.shareXFiles([file], text: '增肌管理数据备份');
    return true;
  } catch (_) {
    return false;
  }
}

/// 导入备份。成功返回恢复的行数摘要；失败抛异常。
Future<String> importBackup(AppDatabase db, String content) async {
  final m = jsonDecode(content) as Map<String, dynamic>;
  if (m['app'] != 'muscle-gain-tracker') {
    throw const FormatException('不是本应用的备份文件');
  }

  Future<List<Map<String, dynamic>>> arr(String key) async {
    final l = m[key] as List<dynamic>? ?? const [];
    return [for (final e in l) Map<String, dynamic>.from(e as Map)];
  }

  final profiles = await arr('profiles');
  final goals = await arr('goals');
  final weightPoints = await arr('weightPoints');
  final foodLogs = await arr('foodLogs');
  final trainingSessions = await arr('trainingSessions');
  final workoutSets = await arr('workoutSets');
  final habits = await arr('habits');
  final weeklyReviews = await arr('weeklyReviews');
  final mealNames = await arr('mealNames');
  final appSettings = await arr('appSettings');
  final customFoods = await arr('customFoods');
  final sleepSessions = await arr('sleepSessions');
  final sleepStageRows = await arr('sleepStageRows');
  final sleepMetrics = await arr('sleepMetrics');

  await db.transaction(() async {
    // 清空 + 恢复必须在同一个事务里：任何一步失败整体回滚，
    // 不能像以前那样先清空再插入（插入失败 = 用户数据被清空且没有恢复）。
    await wipeAllUserData(db);
    await _insertAll(db, db.profiles, profiles);
    await _insertAll(db, db.goals, goals);
    await _insertAll(db, db.weightPoints, weightPoints);
    await _insertAll(db, db.foodLogs, foodLogs);
    await _insertAll(db, db.trainingSessions, trainingSessions);
    await _insertAll(db, db.workoutSets, workoutSets);
    await _insertAll(db, db.habits, habits);
    await _insertAll(db, db.weeklyReviews, weeklyReviews);
    await _insertAll(db, db.mealNames, mealNames);
    await _insertAll(db, db.appSettings, appSettings);
    await _insertAll(db, db.customFoods, customFoods);
    await _insertAll(db, db.sleepSessions, sleepSessions);
    await _insertAll(db, db.sleepStageRows, sleepStageRows);
    await _insertAll(db, db.sleepMetrics, sleepMetrics);
  });

  final total = profiles.length +
      goals.length +
      weightPoints.length +
      foodLogs.length +
      trainingSessions.length +
      habits.length +
      appSettings.length;
  return '已恢复 $total 条记录';
}

/// 原始 map 逐行插入；先按实际表列做映射，再用参数化 SQL 写入。
Future<void> _insertAll(
  AppDatabase db,
  TableInfo<Table, dynamic> table,
  List<Map<String, dynamic>> rows,
) async {
  if (rows.isEmpty) return;
  final dateCols = _dateColumns[table.actualTableName] ?? const <String>{};
  final colsInTable = await _actualColumns(db, table.actualTableName);
  for (final raw in rows) {
    final row = mapBackupRow(raw, colsInTable, dateCols);
    if (row.isEmpty) continue;
    final cols = row.keys.toList();
    final placeholders = List.filled(cols.length, '?').join(', ');
    await db.customStatement(
      'INSERT OR REPLACE INTO ${table.actualTableName} '
      '(${cols.join(', ')}) VALUES ($placeholders)',
      [for (final c in cols) row[c]],
    );
  }
}

/// 实际存在于 SQLite 表中的列名（PRAGMA table_info）。
Future<Set<String>> _actualColumns(AppDatabase db, String tableName) async {
  final rows = await db.customSelect('PRAGMA table_info($tableName)').get();
  return {
    for (final r in rows)
      if (r.data['name'] is String) r.data['name'] as String,
  };
}

String _p2(int n) => n < 10 ? '0$n' : '$n';
