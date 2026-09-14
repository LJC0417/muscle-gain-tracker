/// Drift 数据库（ARCHITECTURE F01 完成版）
/// 共 16 张表：
///   - 核心 6 张：profile / goal / weight_point / food_log /
///                  training_session / workout_set
///   - 扩展 7 张：exercise / habit / weekly_review /
///                  meal_names / app_settings / custom_food / ai_review_meta
///   - 睡眠 3 张（v2）：sleep_session / sleep_stage_row / sleep_metric
///
/// 设计原则：
///   - 所有时间字段用本地 DateTime（存为 Unix 毫秒或 yyyy-MM-dd 字符串，避免时区错乱）
///   - 体重 / 重量一律 kg（展示层转换）
///   - 容量字段预计算持久化（避免每次查询都跑算法）
///   - List<String> / Map 类型一律 JSON 字符串持久化（dart:convert）
library;

import 'dart:convert';

import 'package:drift/drift.dart';

part 'database.g.dart';

/// ════════ 核心 6 张 ════════

/// 用户档案。
@DataClassName('ProfileData')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sex => text().withLength(min: 1, max: 16)();
  IntColumn get age => integer()();
  RealColumn get heightCm => real()();
  TextColumn get scene => text().withLength(min: 1, max: 16)();
  TextColumn get equipmentJson => text().withDefault(const Constant('[]'))(); // List<String> JSON
  IntColumn get daysPerWeek => integer().withDefault(const Constant(4))();
  RealColumn get activityFactor => real().withDefault(const Constant(1.55))();
  BoolColumn get activityFactorLocked => boolean().withDefault(const Constant(false))();
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// 目标（kcal/protein/carb/fat/rate 的 mode + manual + autoOffset）。
@DataClassName('GoalData')
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get startWeightKg => real()();
  RealColumn get currentWeightKg => real()();
  RealColumn get targetWeightKg => real()();
  TextColumn get kcalMode => text().withDefault(const Constant('auto'))();
  RealColumn get kcalManual => real().nullable()();
  RealColumn get kcalAutoOffset => real().withDefault(const Constant(0))();
  TextColumn get proteinMode => text().withDefault(const Constant('auto'))();
  RealColumn get proteinManual => real().nullable()();
  TextColumn get carbMode => text().withDefault(const Constant('auto'))();
  RealColumn get carbManual => real().nullable()();
  TextColumn get fatMode => text().withDefault(const Constant('auto'))();
  RealColumn get fatManual => real().nullable()();
  TextColumn get rateMode => text().withDefault(const Constant('auto'))();
  RealColumn get rateManual => real().nullable()();
  RealColumn get surplusKcal => real().withDefault(const Constant(400))();
  RealColumn get lastWeightUsed => real().nullable()();
  TextColumn get lastAdjustWeek => text().nullable()();
  DateTimeColumn get lastAdjustedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// 体重点（yyyy-MM-dd 主键）。
@DataClassName('WeightPointData')
class WeightPoints extends Table {
  TextColumn get date => text().withLength(min: 10, max: 10)();
  RealColumn get kg => real()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

/// 食物日志。
@DataClassName('FoodLogData')
class FoodLogs extends Table {
  TextColumn get id => text()();
  TextColumn get date => text().withLength(min: 10, max: 10)();
  TextColumn get meal => text()(); // breakfast | lunch | dinner | snack
  TextColumn get foodId => text()();
  TextColumn get foodName => text()();
  RealColumn get servings => real().withDefault(const Constant(1))();
  RealColumn get grams => real()();
  RealColumn get kcal => real()();
  RealColumn get p => real()();
  RealColumn get c => real()();
  RealColumn get f => real()();
  BoolColumn get isEstimate => boolean().withDefault(const Constant(false))();
  BoolColumn get isUserModified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 训练会话（一行一场训练）。
@DataClassName('TrainingSessionData')
class TrainingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get date => text().withLength(min: 10, max: 10)();
  TextColumn get templateCode => text().nullable()();
  TextColumn get status => text()(); // ongoing | completed | abandoned
  RealColumn get totalVolumeKg => real().nullable()();
  IntColumn get durationSec => integer().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 单组记录。
@DataClassName('WorkoutSetData')
class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get setIndex => integer()();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  BoolColumn get isBodyweight => boolean().withDefault(const Constant(false))();
  RealColumn get volumeKg => real().nullable()();
  BoolColumn get isPr => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
}

/// ════════ 扩展 7 张 ════════

/// 动作库（与 JS 版 MG.EXERCISES 对齐）。
@DataClassName('ExerciseData')
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get muscleGroup => text()();
  TextColumn get subGroup => text().nullable()();
  BoolColumn get isCompound => boolean().withDefault(const Constant(false))();
  TextColumn get requiredEquipmentJson =>
      text().withDefault(const Constant('[]'))(); // List<String>
  TextColumn get scenesJson =>
      text().withDefault(const Constant('[]'))(); // List<String>
  IntColumn get defaultSets => integer().withDefault(const Constant(3))();
  RealColumn get repLow => real().withDefault(const Constant(8))();
  RealColumn get repHigh => real().withDefault(const Constant(12))();
  BoolColumn get isBodyweight => boolean().withDefault(const Constant(false))();
  IntColumn get orderWeight => integer().withDefault(const Constant(99))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 习惯打卡（每日一行）。
@DataClassName('HabitData')
class Habits extends Table {
  TextColumn get date => text().withLength(min: 10, max: 10)();
  IntColumn get waterCups => integer().withDefault(const Constant(0))();
  RealColumn get sleepHours => real().withDefault(const Constant(7.0))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

/// 周复盘（每周一行）。
@DataClassName('WeeklyReviewData')
class WeeklyReviews extends Table {
  TextColumn get weekStart =>
      text().withLength(min: 10, max: 10)(); // 周一 yyyy-MM-dd
  TextColumn get weekEnd => text()();
  RealColumn get weightDeltaKg => real().nullable()();
  TextColumn get trendStatus => text()(); // slow | onTrack | fast | unknown
  RealColumn get trainingCompliance => real().nullable()(); // 0-1
  TextColumn get summary => text()();
  TextColumn get adjustmentsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {weekStart};
}

/// 餐别命名（用户自定义）。
@DataClassName('MealNameData')
class MealNames extends Table {
  TextColumn get id => text()(); // breakfast | lunch | dinner | snack
  TextColumn get label => text()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 应用通用设置（key-value 兜底，所有不直接进表的设置放这里）。
@DataClassName('AppSettingData')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 用户自定义食物（每 100g 的基础营养 + 默认克数）。
@DataClassName('CustomFoodData')
class CustomFoods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  RealColumn get kcalPer100 => real()();
  RealColumn get pPer100 => real()();
  RealColumn get cPer100 => real()();
  RealColumn get fPer100 => real()();
  RealColumn get defaultGrams => real().withDefault(const Constant(100))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI 周报生成元数据。
class AiReviewMeta extends Table {
  TextColumn get weekStart => text().withLength(min: 10, max: 10)();
  TextColumn get model => text()();
  IntColumn get promptTokens => integer()();
  IntColumn get completionTokens => integer()();
  DateTimeColumn get generatedAt => dateTime()();
  TextColumn get rawJson => text()();

  @override
  Set<Column> get primaryKey => {weekStart};
}

/// ════════ 睡眠（v2 新增，来源 Health Connect / vivo 健康）════════

/// 睡眠会话（一晚一行；date = 起床日 yyyy-MM-dd）。
@DataClassName('SleepSessionData')
class SleepSessions extends Table {
  TextColumn get date => text().withLength(min: 10, max: 10)();
  DateTimeColumn get bedtimeStart => dateTime()(); // 入床/入睡开始
  DateTimeColumn get bedtimeEnd => dateTime()(); // 起床
  TextColumn get source =>
      text().withDefault(const Constant('health_connect'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

/// 睡眠阶段段（Health Connect 的 SleepStage 逐段）。
@DataClassName('SleepStageRow')
class SleepStageRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text().withLength(min: 10, max: 10)(); // 起床日
  TextColumn get stage => text()(); // deep | light | rem | awake
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
}

/// 睡眠体征（一晚一行；可空 = 当晚没有该数据源）。
@DataClassName('SleepMetricData')
class SleepMetrics extends Table {
  TextColumn get date => text().withLength(min: 10, max: 10)();
  RealColumn get avgHr => real().nullable()(); // bpm
  RealColumn get minHr => real().nullable()();
  RealColumn get maxHr => real().nullable()();
  RealColumn get respirationRate => real().nullable()(); // 次/分
  RealColumn get spo2Avg => real().nullable()(); // %
  RealColumn get spo2Min => real().nullable()();
  RealColumn get hrvMs => real().nullable()(); // RMSSD ms
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

@DriftDatabase(
  tables: [
    Profiles,
    Goals,
    WeightPoints,
    FoodLogs,
    TrainingSessions,
    WorkoutSets,
    Exercises,
    Habits,
    WeeklyReviews,
    MealNames,
    AppSettings,
    CustomFoods,
    AiReviewMeta,
    SleepSessions,
    SleepStageRows,
    SleepMetrics,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(sleepSessions);
            await m.createTable(sleepStageRows);
            await m.createTable(sleepMetrics);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  // ════════ JSON decode helpers（Keys 给仓储层调用） ════════

  /// 从 SQLite 一行读出 List<String>（安全，失败 → []）。
  static List<String> decodeStrList(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
    } catch (_) {/* swallow */}
    return <String>[];
  }

  /// List<String> → JSON 字符串。
  static String encodeStrList(List<String> values) => jsonEncode(values);
}
