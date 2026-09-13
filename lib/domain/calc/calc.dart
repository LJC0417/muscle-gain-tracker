/// 营养与趋势算法（阶段 A 的 core/calc.js 的 Dart 版）。
/// 全部纯函数：不读全局可变状态、不做 IO、不依赖 Flutter。
///
/// 入口分模块导出（与 JS 版 MG.calc 字段一一对应）：
///   [round]    — R 工具 + clamp
///   [date]     — D 工具（本地时区日期）
///   [bmr] / [recommendFactor] / [tdee] / [targetKcal] / [macros] / [defaultRate] / [weeksToGoal]
///   [computeAutoGoal] / [isManualField] / [resolveGoal] / [onWeightLogged]
///   [gapFill] / [movingAverage7] / [weekAvg] / [delta] / [trendStatus] / [streak]
///   [suggestCalorieAdjust] / [applyAdjustment]
///   [kcalHit] / [proteinHit]
///   [rangeOf] / [unitConvert]
library;

export 'round.dart' show R, clamp;
export 'date_utils.dart' show D;
export 'nutrition_calculator.dart'
    show Macros, bmr, recommendFactor, tdee, targetKcal, macros, defaultRate, weeksToGoal;
export 'goal_resolver.dart'
    show AutoGoal, ResolvedGoal, WeightLinkResult, computeAutoGoal, isManualField, resolveGoal, onWeightLogged;
export 'trend_analyzer.dart'
    show FilledPoint, MaPoint, WeightPointLite, gapFill, movingAverage7, weekAvg, delta, trendStatus, streak;
export 'calorie_adjuster.dart'
    show CalorieAdjust, AdjustCtx, suggestCalorieAdjust, applyAdjustment;
export 'hit.dart' show kcalHit, proteinHit;
export 'range.dart' show rangeOf, unitConvert;
