/// 时间范围 / 单位换算（ARCHITECTURE 2.14–2.15）
import 'date_utils.dart';
import 'round.dart';

/// 滚动窗口（不是自然周）：
///   week    — 近 7 天（含今日）
///   month   — 近 30 天
///   quarter — 近 90 天
///   all     — 至今；若 earliestDate 提供则从最早那天起
({String from, String to}) rangeOf(String rangeKey, String today, String? earliestDate) {
  final to = today;
  String from;
  switch (rangeKey) {
    case 'week':
      from = D.addDays(to, -6);
      break;
    case 'month':
      from = D.addDays(to, -29);
      break;
    case 'quarter':
      from = D.addDays(to, -89);
      break;
    case 'all':
      from = earliestDate ?? D.addDays(to, -29);
      break;
    default:
      from = D.addDays(to, -29);
  }
  return (from: from, to: to);
}

/// 单位换算（内部一律 kg，展示层才转斤）。
num? unitConvert(num? kgValue, String unit) {
  if (kgValue == null) return kgValue;
  if (unit == 'jin') return R.r1(kgValue * 2);
  return R.r1(kgValue);
}
