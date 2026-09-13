import 'package:freezed_annotation/freezed_annotation.dart';

part 'weight_point.freezed.dart';
part 'weight_point.g.dart';

@freezed
class WeightPoint with _$WeightPoint {
  const factory WeightPoint({
    required String date, // yyyy-MM-dd
    required double kg,
    String? note,
  }) = _WeightPoint;

  factory WeightPoint.fromJson(Map<String, Object?> json) =>
      _$WeightPointFromJson(json);
}
