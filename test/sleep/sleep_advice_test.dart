import 'package:flutter_test/flutter_test.dart';

import 'package:muscle_gain_tracker/application/sleep_models.dart';

/// 构造自洽的一晚：分段总长 = awakeMin + asleepMin，wake = bedtime + 总长。
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
  final span = awakeMin + asleepMin;
  final t0 = 23 * 60;
  final t1 = t0 + awakeMin;
  final t2 = t1 + deepMin;
  final t3 = t2 + lightMin;
  final segments = <SleepSegment>[
    SleepSegment(SleepStage.awake, t0, t1),
    SleepSegment(SleepStage.deep, t1, t2),
    SleepSegment(SleepStage.light, t2, t3),
    SleepSegment(SleepStage.rem, t3, t3 + remMin),
  ];
  return SleepDay(
    date: date,
    windowStartMin: t0,
    windowEndMin: t0 + span,
    bedtimeMin: t0,
    wakeMin: t0 + span,
    segments: segments,
    avgHr: avgHr,
    hrvMs: hrvMs,
    spo2Min: spo2Min,
  );
}

void main() {
  test('睡得好的夜晚只给正向反馈', () {
    // 睡 7.5h，清醒 15 分钟；深睡 80/465≈17%（不触发好坏阈值）；体征正常
    final day = _day(asleepMin: 7 * 60 + 30, deepMin: 80);
    final advice = buildSleepAdvice(day);
    expect(advice.length, 1);
    expect(advice.first.positive, isTrue);
  });

  test('总时长不足时给出补觉建议', () {
    final day = _day(asleepMin: 6 * 60, deepMin: 60, remMin: 60);
    final advice = buildSleepAdvice(day);
    expect(advice.first.positive, isFalse);
    expect(advice.any((a) => a.title.contains('总睡眠')), isTrue);
  });

  test('体征异常触发对应建议', () {
    final day = _day(asleepMin: 7 * 60 + 40, avgHr: 72, hrvMs: 22, spo2Min: 91);
    final advice = buildSleepAdvice(day);
    expect(advice.any((a) => a.title.contains('心率')), isTrue);
    expect(advice.any((a) => a.title.contains('血氧')), isTrue);
  });

  test('入睡过晚触发就寝建议', () {
    // 00:45 入睡，睡 7h15m（deep 100 / light 245 / rem 90）
    final t0 = 24 * 60 + 45;
    final segments = <SleepSegment>[
      SleepSegment(SleepStage.deep, t0, t0 + 100),
      SleepSegment(SleepStage.light, t0 + 100, t0 + 345),
      SleepSegment(SleepStage.rem, t0 + 345, t0 + 435),
    ];
    final day = SleepDay(
      date: '2026-09-14',
      windowStartMin: t0,
      windowEndMin: t0 + 435,
      bedtimeMin: t0,
      wakeMin: t0 + 435,
      segments: segments,
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
