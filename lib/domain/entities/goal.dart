import 'package:freezed_annotation/freezed_annotation.dart';

part 'goal.freezed.dart';
part 'goal.g.dart';

@freezed
class Goal with _$Goal {
  const factory Goal({
    required double startWeightKg,
    required double currentWeightKg,
    required double targetWeightKg,
    @Default('auto') String kcalMode,
    double? kcalManual,
    @Default(0) double kcalAutoOffset,
    @Default('auto') String proteinMode,
    double? proteinManual,
    @Default('auto') String carbMode,
    double? carbManual,
    @Default('auto') String fatMode,
    double? fatManual,
    @Default('auto') String rateMode,
    double? rateManual,
    @Default(400) double surplusKcal,
    @Default(1.8) double proteinPerKg,
    @Default(0.9) double fatPerKg,
    @Default(0.20) double fatPctMin,
    double? lastWeightUsed,
    String? lastAdjustWeek,
    DateTime? lastAdjustedAt,
    DateTime? updatedAt,
  }) = _Goal;

  factory Goal.fromJson(Map<String, Object?> json) => _$GoalFromJson(json);
}

@freezed
class ResolvedGoal with _$ResolvedGoal {
  const factory ResolvedGoal({
    required double bmr,
    required double tdee,
    required double kcal,
    required double protein,
    required double carb,
    required double fat,
    required double rate,
  }) = _ResolvedGoal;
}
