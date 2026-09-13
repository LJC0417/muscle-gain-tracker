/// 训练计划（阶段 A 的 core/plan.js 的 Dart 版）。
/// 全部纯函数：不碰 DOM、不读写 store（所需数据一律由调用方以参数传入）。
///
/// 入口分模块导出（与 JS 版 MG.plan 字段一一对应）：
///   [availableExercises] / [generatePlan] / [estimateMinutes] /
///   [defaultWeekPattern] / [templatePoolOf] / [getTodayPlan]
///   [setVolume] / [e1RM] / [sessionVolume] / [checkPR]
///   [lastPerformance] / [prefillSet] / [compareBadge] / [rolling7TrainingStats]
library;

export 'plan_generation.dart'
    show
        PlanDay,
        PlanEntry,
        Exercise,
        DayTemplate,
        DaySlot,
        WeekPattern,
        PlanOutput,
        GeneratePlanInput,
        availableExercises,
        estimateMinutes,
        defaultWeekPattern,
        templatePoolOf,
        generatePlan,
        getTodayPlan;
export 'plan_metrics.dart'
    show WorkoutSet, PrHistory, PrHit, setVolume, e1RM, sessionVolume, checkPR;
export 'plan_history.dart'
    show
        TrainingSession,
        PrefillSetResult,
        Rolling7Stats,
        lastPerformance,
        prefillSet,
        compareBadge,
        rolling7TrainingStats;
