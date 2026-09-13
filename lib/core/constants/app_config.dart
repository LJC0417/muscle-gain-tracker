/// 全量业务常量（阶段 A 的 data/constants.js 的 Dart 版）
/// 规则：所有业务数字必须来自此处，禁止在其它文件写死魔法数字。
class AppConfig {
  // 营养
  static const double bmrMaleOffset = 5;
  static const double bmrFemaleOffset = -161;

  static final List<_ActivityLevel> activityLevels = [
    _ActivityLevel('sedentary', '久坐（几乎不运动）', 1.2),
    _ActivityLevel('light', '轻度（每周 1–3 天）', 1.375),
    _ActivityLevel('moderate', '中等（每周 3–5 天）', 1.55),
    _ActivityLevel('high', '高强度（每周 6–7 天）', 1.725),
    _ActivityLevel('athlete', '极高（体力工作/每日训练）', 1.9),
  ];

  static double get defaultActivityFactor => 1.55;
  static const double defaultSurplus = 400;
  static const double surplusMin = 0;
  static const double surplusMax = 1000;
  static const double proteinPerKg = 1.8;
  static const double proteinKgMin = 1.6;
  static const double proteinKgMax = 2.2;
  static const double fatPerKg = 0.9;
  static const double fatPctMin = 0.20;
  static const double macroTolerance = 20;
  static const double minCarbG = 20;
  static const double ratePctPerWeek = 0.004;
  static const double rateMin = 0.1;
  static const double rateMax = 0.8;
  static const double weightLinkThreshold = 0.2;

  // 趋势与微调
  static const int ma7Window = 7;
  static const int ma7MinPoints = 3;
  static const int weekAvgMinDays = 3;
  static const double tolSlow = 0.05;
  static const double tolFast = 0.15;
  static const double adjustStepKcal = 100;
  static const double maxAdjustKcal = 200;
  static const double slowSeverityUnit = 0.10;
  static const double fastSeverityUnit = 0.15;
  static const int minWeeksBeforeAdjust = 2;
  static const double kcalFloorBmrMult = 1.2;
  static const double kcalCeilBmrMult = 2.2;

  // 达标率
  static const double kcalTolLower = 0.10;
  static const double kcalTolUpper = 0.10;
  static const double proteinTol = 0.95;

  // 训练
  static const int restDefaultSec = 90;
  static const double timePerRepSec = 4;
  static const double transitionPerSetSec = 40;
  static const double setupPerExerciseSec = 120;
  static const int warmupSec = 600;
  static const double defaultWeightKg = 20;
  static const int defaultReps = 10;
  static const bool countBodyweightVolume = true;
  static const int e1rmDivisor = 30;

  // 习惯
  static const int waterGoalCups = 8;
  static const int waterCupMl = 250;
  static const double sleepDefaultH = 7.0;
  static const double sleepStepH = 0.5;

  // 提醒默认
  static const String notifyWeightTime = '08:00';
  static const String notifyWorkoutTime = '19:00';
  static const int notifyWaterIntervalH = 2;
  static const String notifyWaterWindow = '10:00-21:00';
  static const int notifyReviewDow = 7;
  static const String notifyReviewTime = '20:00';

  // 展示
  static const String weightUnit = 'kg';
  static const bool ringOverShownAsAcceptable = true;
  static const int weekStartsOn = 1; // 周一

  // 存储
  static const String storageKey = 'mg:v1:state';
  static const int stateVersion = 1;

  // 枚举
  static const List<String> sex = ['male', 'female'];
  static const List<String> scene = ['home', 'gym'];
  static const List<String> mealSlot = ['breakfast', 'lunch', 'dinner', 'snack'];
  static const List<String> trendStatus = ['slow', 'onTrack', 'fast', 'unknown'];
  static const List<String> adjustType = ['increase', 'decrease', 'maintain'];
  static const List<String> goalFieldMode = ['auto', 'manual'];
  static const List<String> foodCategory = [
    'staple', 'meat', 'takeout', 'supplement', 'veg', 'fruit', 'drink', 'snack'
  ];
  static const List<String> foodSource = ['builtin', 'custom', 'override'];
  static const List<String> muscleGroup = [
    'chest', 'back', 'legs', 'shoulders', 'arms', 'core'
  ];
  static const List<String> equipmentId = [
    'dumbbell', 'bench', 'band', 'pullup_bar', 'kettlebell',
    'barbell', 'rack', 'cable', 'machine', 'mat', 'none'
  ];
  static const List<String> chartRange = ['week', 'month', 'quarter', 'all'];
  static const List<String> sessionStatus = ['ongoing', 'completed', 'abandoned'];
  static const List<String> weightUnit = ['kg', 'jin'];

  // 中文文案映射
  static const Map<String, String> labels = {
    'male': '男',
    'female': '女',
    'home': '居家哑铃',
    'gym': '健身房',
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
    'slow': '偏慢',
    'onTrack': '达标',
    'fast': '偏快',
    'unknown': '数据不足',
    'increase': '增加',
    'decrease': '减少',
    'maintain': '维持',
    'auto': '自动',
    'manual': '手动',
    'staple': '主食',
    'meat': '肉蛋',
    'takeout': '外卖常见',
    'supplement': '补剂',
    'veg': '蔬菜',
    'fruit': '水果',
    'drink': '饮料',
    'dumbbell': '可调节哑铃',
    'bench': '卧推凳',
    'band': '弹力带',
    'pullup_bar': '引体向上杆',
    'kettlebell': '壶铃',
    'barbell': '杠铃',
    'rack': '深蹲架',
    'cable': '龙门架',
    'machine': '器械',
    'mat': '瑜伽垫',
    'none': '自重',
    'week': '周',
    'month': '月',
    'quarter': '季',
    'all': '全部',
    'ongoing': '进行中',
    'completed': '已完成',
    'abandoned': '已放弃',
    'kg': 'kg',
    'jin': '斤',
  };
}

class _ActivityLevel {
  final String key;
  final String label;
  final double factor;

  const _ActivityLevel(this.key, this.label, this.factor);
}
