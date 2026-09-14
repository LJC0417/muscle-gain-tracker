import 'package:flutter_test/flutter_test.dart';

import 'package:muscle_gain_tracker/application/sleep_models.dart';

SleepDay _day({
  required int asleepMin,
  int deepMin = 100,
  int remMin = 90,
  int awakeMin = 15,
  String date = '2026-09-14',
  double? avgHr = 55,
  double? hrvMs = 45,
  double? spo2Min = 96,
}) {
  final lightMin = asleepMin - deepMin - remMin;
  final segments = <SleepSegment>[
    SleepSegment(SleepStage.awake, 23 * 60, 23 * 60 + awakeMin),
    SleepSegment(SleepStage.deep, 23 * 60 + awakeMin, 23 * 60 + awakeMin + deepMin),
    SleepSegment(
        SleepStage.light, 23 * 60 + awakeMin + deepMin, 23 * 60 + awakeMin + deepMin + lightMin),
    SleepSegment(
        SleepStage.rem, 23 * 60 + awakeMin + deepMin + lightMin, 23 * 60 + awakeMin + deepMin + lightMin + remMin),
  ];
  return SleepDay(
    date: date,
    windowStartMin: 23 * 60,
    windowEndMin: 7 * 60 + 1440,
    bedtimeMin: 23 * 60,
    wakeMin: 7 * 60 + 1440,
    segments: segments,
    avgHr: avgHr,
    hrvMs: hrvMs,
    spo2Min: spo2Min,
  );
}

void main() {
  test('睡得好的夜晚只给正向反馈', () {
    // 睡 7.5h，清醒 15 分钟，深睡/REM 正常，体征正常
    final day = _day(asleepMin: 7 * 60 + 30);
    final advice = buildSleepAdvice(day);
    expect(advice.length, 1);
    expect(advice.first.positive, isTrue);
  });

  test('总时长不足时给出补觉建议', () {
    final day = _day(asleepMin: 6 * 60, deepMin: 60, remMin: 60);
    final advice = buildSleepAdvice(day);
    expect(advice.any((a) => a.title.contains('总睡眠') || a.title.contains('睡眠')), isTrue);
    expect(advice.first.positive, isFalse);
  });

  test('体征异常触发对应建议', () {
    final day = _day(asleepMin: 7 * 60 + 40, avgHr: 72, hrvMs: 22, spo2Min: 91);
    final advice = buildSleepAdvice(day);
    expect(advice.any((a) => a.title.contains('心率')), isTrue);
    expect(advice.any((a) => a.title.contains('血氧')), isTrue);
  });

  test('入睡过晚触发就寝建议', () {
    final base = _day(asleepMin: 7 * 60 + 40);
    // 手动构造 00:45 才入睡的一晚
    final day = SleepDay(
      date: base.date,
      windowStartMin: 24 * 60 + 45,
      windowEndMin: 8 * 60 + 1440,
      bedtimeMin: 24 * 60 + 45,
      wakeMin: 8 * 60 + 1440,
      segments: [
        SleepSegment(SleepStage.deep, 24 * 60 + 45, 25 * 60 + 105),
        SleepSegment(SleepStage.light, 25 * 60 + 105, 30 * 60 + 105),
        SleepSegment(SleepStage.rem, 30 * 60 + 105, 31 * 60 + 15),
      ],
      avgHr: 55,
      hrvMs: 45,
      spo2Min: 96,
    );
    final advice = buildSleepAdvice(day);
    expect(advice.any((a) => a.title.contains('就寝太晚')), isTrue);
  });

  test('模型口径自洽：非清醒即睡着', () {
    final day = _day(asleepMin: 7 * 60);
    expect(day.asleepMin, day.inBedMin - day.durationOf(SleepStage.awake));
    expect(day.efficiency, greaterThan(0));
    expect(day.efficiency, lessThanOrEqualTo(100));
  });
}
