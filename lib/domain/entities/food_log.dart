import 'package:freezed_annotation/freezed_annotation.dart';

part 'food_log.freezed.dart';
part 'food_log.g.dart';

@freezed
class FoodLog with _$FoodLog {
  const factory FoodLog({
    required String id,
    required String date,
    required String meal, // breakfast | lunch | dinner | snack
    required String foodId,
    required String foodName,
    @Default(1) double servings,
    required double grams,
    required double kcal,
    required double p,
    required double c,
    required double f,
    @Default(false) bool isEstimate,
    @Default(false) bool isUserModified,
    DateTime? createdAt,
  }) = _FoodLog;

  factory FoodLog.fromJson(Map<String, Object?> json) =>
      _$FoodLogFromJson(json);
}
