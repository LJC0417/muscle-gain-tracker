import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String sex, // male | female
    required int age,
    required double heightCm,
    required String scene, // home | gym
    @Default([]) List<String> equipment,
    @Default(4) int daysPerWeek,
    @Default(1.55) double activityFactor,
    @Default(false) bool activityFactorLocked,
    @Default(false) bool onboardingDone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
