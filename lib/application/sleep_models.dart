/// 睡眠数据模型 + 建议算法（纯 Dart，零 Flutter 依赖，可单测/裸跑）
library;

/// 睡眠阶段。
enum SleepStage { awake, rem, light, deep }

/// 一个睡眠阶段段（分钟数相对「入床日 0 点」的绝对钟点，23:00 = 1380）。
class SleepSegment {
  final SleepStage stage;
  final int startMin;
  final int endMin;
  const SleepSegment(this.stage, this.startMin, this.endMin);

  int get durationMin => endMin - startMin;
}

/// 一晚睡眠（UI 与数据层共用；字段可空 = 数据源没有该项）。
class SleepDay {
  final String date; // 起床日 yyyy-MM-dd
  final int windowStartMin; // 时间轴窗口起点
  final int windowEndMin; // 时间轴窗口终点
  final int bedtimeMin; // 入床
  final int wakeMin; // 起床
  final List<SleepSegment> segments;
  final double? avgHr;
  final double? minHr;
  final double? maxHr;
  final double? respirationRate;
  final double? spo2Avg;
  final double? spo2Min;
  final double? hrvMs;

  const SleepDay({
    required this.date,
    required this.windowStartMin,
    required this.windowEndMin,
    required this.bedtimeMin,
    required this.wakeMin,
    required this.segments,
    this.avgHr,
    this.minHr,
    this.maxHr,
    this.respirationRate,
    this.spo2Avg,
    this.spo2Min,
    this.hrvMs,
  });

  int durationOf(SleepStage s) => segments
      .where((g) => g.stage == s)
      .fold(0, (a, g) => a + g.durationMin);

  int get inBedMin => wakeMin - bedtimeMin;

  /// 睡着总分钟（非清醒即睡着）。
  int get asleepMin => inBedMin - durationOf(SleepStage.awake);

  double get efficiency => inBedMin == 0 ? 0 : asleepMin / inBedMin * 100;

  /// 各阶段占卧床时间的百分比。
  int pctOf(SleepStage s) =>
      inBedMin == 0 ? 0 : (durationOf(s) / inBedMin * 100).round();
}

const stageLabels = {
  SleepStage.awake: '清醒',
  SleepStage.rem: '快速眼动',
  SleepStage.light: '浅睡',
  SleepStage.deep: '深睡',
};

/// 分钟数（相对入床日 0 点）→ HH:mm。
String hm(int min) {
  final m = ((min % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 分钟数 → 「x小时xx分 / x 分钟」。
String dur(int min) {
  if (min < 60) return '$min 分钟';
  return '${min ~/ 60}小时${(min % 60).toString().padLeft(2, '0')}分';
}

/// 一条睡眠建议。
class SleepAdvice {
  final String title;
  final String detail;

  /// true = 正向反馈（做得好）。
  final bool positive;
  const SleepAdvice(this.title, this.detail, {this.positive = false});
}

/// 规则式建议（本地生成，不依赖网络/模型；按重要性最多 4 条）。
List<SleepAdvice> buildSleepAdvice(SleepDay day) {
  final out = <SleepAdvice>[];
  final asleepH = day.asleepMin / 60;

  // 1) 总时长（最重要）
  if (asleepH < 6.5) {
    out.add(SleepAdvice('总睡眠不足 6.5 小时',
        '实际 ${dur(day.asleepMin)}，增肌恢复至少要 7 小时。今晚提前 30–60 分钟上床，比多练一组更有用。'));
  } else if (asleepH < 7) {
    out.add(SleepAdvice('睡眠略低于 7 小时建议线',
        '现在 ${dur(day.asleepMin)}。把就寝再提前 20–30 分钟就能补上缺口。'));
  } else if (asleepH >= 9.5) {
    out.add(SleepAdvice('睡眠时间偏长',
        '睡了 ${dur(day.asleepMin)}。过长的卧床若伴随多段清醒，说明睡眠质量不高，试着固定起床时间。'));
  }

  // 2) 就寝时间
  if (day.bedtimeMin >= 24 * 60 + 30) {
    out.add(SleepAdvice('就寝太晚（${hm(day.bedtimeMin)}）',
        '0 点半后才睡会压缩深睡比例。生长激素主要在前半夜深睡期分泌，尽量在 23:00–24:00 之间入睡。'));
  }

  // 3) 深睡占比
  final deepPct = day.pctOf(SleepStage.deep);
  if (deepPct < 15 && day.durationOf(SleepStage.deep) > 0) {
    out.add(SleepAdvice('深睡占比 $deepPct%，偏低',
        '深睡是身体修复的主力。睡前 1 小时远离手机、卧室保持黑暗凉爽、当晚避免剧烈运动和饮酒。'));
  } else if (deepPct >= 20) {
    out.add(SleepAdvice('深睡占比 $deepPct%，很好', '身体修复窗口充足，白天训练的强度可以放心保持。',
        positive: true));
  }

  // 4) REM
  final remPct = day.pctOf(SleepStage.rem);
  if (remPct < 18 && day.durationOf(SleepStage.rem) > 0) {
    out.add(SleepAdvice('快速眼动占比 $remPct%，偏低',
        'REM 不足会影响神经恢复与动作记忆。后半夜 REM 最集中——别太早起床打断它。'));
  }

  // 5) 夜间清醒
  final awakeMin = day.durationOf(SleepStage.awake);
  if (awakeMin > 30) {
    out.add(SleepAdvice('夜间清醒共 ${dur(awakeMin)}',
        '片段化睡眠会拉低修复效率。睡前少喝水、减少光线和噪音；醒超过 20 分钟可起身看纸质书再回床。'));
  }

  // 6) 效率
  if (day.efficiency < 85) {
    out.add(SleepAdvice('睡眠效率 ${day.efficiency.toStringAsFixed(0)}%',
        '卧床时间里睡着的占比偏低。与其早早上床干躺，不如困了再上床、固定时间起床。'));
  }

  // 7) 体征
  final hr = day.avgHr;
  if (hr != null && hr > 65) {
    out.add(SleepAdvice('睡眠平均心率 ${hr.toStringAsFixed(0)} bpm，偏高',
        '可能和当日训练强度大、咖啡因或压力有关。观察 2–3 天，持续偏高就降一降训练量。'));
  }
  final hrv = day.hrvMs;
  if (hrv != null && hrv < 30) {
    out.add(SleepAdvice('心率变异性 ${hrv.toStringAsFixed(0)} ms，偏低',
        'HRV 低常提示身体恢复压力大。今晚可以提前睡、降低训练强度，给身体留出恢复余量。'));
  }
  final spo2 = day.spo2Min;
  if (spo2 != null && spo2 < 93) {
    out.add(SleepAdvice('最低血氧 $spo2%，偏低',
        '偶尔一晚可能与鼻塞、睡姿有关；若连续多晚偏低或白天嗜睡，建议关注呼吸健康。'));
  }

  if (out.isEmpty) {
    out.add(SleepAdvice('这一晚睡得不错',
        '时长、结构和体征都在合理区间——好状态是练出来也是睡出来的，保持住。',
        positive: true));
  }
  return out.take(4).toList();
}
