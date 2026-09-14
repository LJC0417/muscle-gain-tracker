/// 备份导入的纯文本/纯数据映射层（零 Flutter、零 drift 依赖）。
///
/// 抽成纯函数的原因：
///   1. 能在 `flutter test` 断言（CI 硬门禁）
///   2. 能在命令行用裸 Dart 直接跑真实实现做回归
///
/// 真实线上 bug 背景：drift 默认把 Dart 驼峰字段名转成蛇形 SQLite 列名
/// （heightCm → height_cm），而数据类 toJson() 输出的是驼峰键。备份导入用
/// 这些键拼裸 SQL，直接报 "table profiles has no column named heightCm"。
/// 导入因此从第一版起就没成功过，且失败发生在「清空之后、恢复之前」，
/// 用户数据被清掉还没恢复。本层负责把 JSON 行正确映射到实际表列。
library;

/// 驼峰 → 蛇形（drift 默认列名规则）。
String camelToSnake(String s) =>
    s.replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}');

/// 各表中的 DateTime 列（导出 JSON 键，驼峰）。
/// toJson 把 DateTime 输出为 ISO 字符串；drift 默认存秒级 Unix 时间戳。
const backupDateColumns = <String, Set<String>>{
  'profiles': {'createdAt', 'updatedAt'},
  'goals': {'lastAdjustedAt', 'updatedAt'},
  'foodLogs': {'createdAt'},
  'trainingSessions': {'startedAt', 'finishedAt'},
  'workoutSets': {'createdAt'},
  'weeklyReviews': {'createdAt'},
  'customFoods': {'createdAt'},
  'sleepSessions': {'bedtimeStart', 'bedtimeEnd', 'updatedAt'},
  'sleepStageRows': {'startAt', 'endAt'},
  'sleepMetrics': {'updatedAt'},
};

/// 把备份 JSON 的一行映射成「实际表列 → SQLite 值」：
///   - 键名驼峰→蛇形；表里不存在的列直接丢弃（跨版本兼容，不再抛异常）
///   - DateTime：ISO 字符串 → 秒级时间戳整数；数值视为已是时间戳
///   - bool → 1/0
/// [colsInTable] 由调用方用 `PRAGMA table_info` 取出。
Map<String, Object?> mapBackupRow(
  Map<String, dynamic> raw,
  Set<String> colsInTable,
  Set<String> dateCols,
) {
  final mapped = <String, Object?>{};
  raw.forEach((key, value) {
    var col = camelToSnake(key);
    if (!colsInTable.contains(col)) col = key; // 兼容已是蛇形/原名一致的键
    if (!colsInTable.contains(col)) return; // 未知列：跳过而不是炸
    Object? v = value;
    if (dateCols.contains(key)) {
      if (v is String) {
        final d = DateTime.tryParse(v);
        v = d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
      } else if (v is num) {
        v = v.toInt(); // 已是时间戳
      } else {
        v = null;
      }
    } else if (v is bool) {
      v = v ? 1 : 0;
    }
    mapped[col] = v;
  });
  return mapped;
}
