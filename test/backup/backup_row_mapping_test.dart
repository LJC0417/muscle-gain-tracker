// 备份导入行映射回归测试
//
// 背景（真实线上 bug）：drift 默认把驼峰字段名转成蛇形 SQLite 列名
// （heightCm → height_cm），而数据类 toJson() 输出驼峰键。旧版导入用驼峰键
// 拼裸 SQL，报 "table profiles has no column named heightCm"——备份导入
// 从第一版起就没成功过，且失败发生在「清空之后、恢复之前」，用户数据丢失。
//
// 本测试锁死 mapBackupRow 的三个契约：
//   1. 驼峰键 → 蛇形列名，只保留实际存在的列
//   2. DateTime 列：ISO 字符串 → 秒级 Unix 时间戳（drift 默认存储格式）
//   3. bool → 1/0；未知列跳过不抛
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/application/backup_row_mapping.dart';

void main() {
  // 模拟 PRAGMA table_info(profiles) 的真实结果（drift 蛇形命名）
  const profileCols = {
    'id', 'sex', 'age', 'height_cm', 'scene', 'equipment_json',
    'days_per_week', 'activity_factor', 'activity_factor_locked',
    'onboarding_done', 'created_at', 'updated_at',
  };
  const dateCols = {'createdAt', 'updatedAt'};

  test('camelToSnake 基本转换', () {
    expect(camelToSnake('heightCm'), 'height_cm');
    expect(camelToSnake('equipmentJson'), 'equipment_json');
    expect(camelToSnake('id'), 'id');
    expect(camelToSnake('sex'), 'sex');
    expect(camelToSnake('activityFactorLocked'), 'activity_factor_locked');
  });

  test('profiles 真实行：驼峰键全部映射到蛇形列（曾经的崩溃现场）', () {
    final raw = <String, dynamic>{
      'id': 1,
      'sex': 'male',
      'age': 25,
      'heightCm': 175.0, // ← 旧版在这里炸：no column named heightCm
      'scene': 'home',
      'equipmentJson': '["dumbbell"]',
      'daysPerWeek': 4,
      'activityFactor': 1.55,
      'activityFactorLocked': false,
      'onboardingDone': true,
      'createdAt': '2026-09-14T09:00:00.000',
      'updatedAt': '2026-09-14T10:00:00.000',
    };
    final got = mapBackupRow(raw, profileCols, dateCols);

    expect(got['height_cm'], 175.0);
    expect(got['equipment_json'], '["dumbbell"]');
    expect(got['days_per_week'], 4);
    expect(got['activity_factor_locked'], 0);
    expect(got['onboarding_done'], 1);
    // DateTime：ISO 字符串 → 秒级时间戳
    final expectedTs =
        DateTime.parse('2026-09-14T09:00:00.000').millisecondsSinceEpoch ~/ 1000;
    expect(got['created_at'], expectedTs);
    // 不应残留任何驼峰键
    expect(got.keys.any((k) => k.contains('C') && k != ''), isFalse,
        reason: '所有键必须是蛇形：${got.keys.toList()}');
    expect(got.length, 12);
  });

  test('未知列被跳过而不是抛异常（跨版本兼容）', () {
    final raw = <String, dynamic>{
      'id': 1,
      'sex': 'male',
      'heightCm': 175.0,
      'futureColumn': 'whatever', // 表里没有 → 丢弃
    };
    final got = mapBackupRow(raw, profileCols, dateCols);
    expect(got.containsKey('future_column'), isFalse);
    expect(got.containsKey('futureColumn'), isFalse);
    expect(got['height_cm'], 175.0);
  });

  test('时间列已是时间戳数字时保持整数', () {
    final got = mapBackupRow(
      {'createdAt': 1789000000},
      {'created_at'},
      {'createdAt'},
    );
    expect(got['created_at'], 1789000000);
  });

  test('时间列脏数据 → null（不抛）', () {
    final got = mapBackupRow({'createdAt': '不是时间'}, {'created_at'}, {'createdAt'});
    expect(got['created_at'], isNull);
  });
}
