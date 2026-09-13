/// 趋势分析（ARCHITECTURE 2.8 / A8 / A14）
///   gapFill         — 缺失日线性插值/外推（标注 real:false）
///   movingAverage7  — 7 日滑动均线（窗口内真实点 >= MA7_MIN_POINTS 才计算）
///   weekAvg         — 某自然周（含端点）平均体重，记录 < WEEK_AVG_MIN_DAYS 返回 null
///   delta           — 周均值之差
///   trendStatus     — slow / onTrack / fast / unknown
///   streak          — 连续记录天数（含今日尚未记录时从昨日往回数）
import '../../core/constants/app_config.dart';
import 'date_utils.dart';
import 'round.dart';

/// 体重点（含是否真实记录）。
class FilledPoint {
  final String date;
  final num kg;
  final bool real;
  const FilledPoint(this.date, this.kg, this.real);
}

/// 均线点（real=该日真实记录；ma=null=窗口内真实点不足）。
class MaPoint {
  final String date;
  final num? ma;
  final bool real;
  const MaPoint(this.date, this.ma, this.real);
}

/// 原始体重点（轻量版本，只含业务需要的字段）。
class WeightPointLite {
  final String date;
  final num kg;
  const WeightPointLite(this.date, this.kg);
}

/// 缺失日插值（线性内插；端点外用最近已知点）。
/// 入参支持任意 [{date,kg}] 结构（Map 或 WeightPointLite）。
List<FilledPoint> gapFill(
  Iterable<dynamic> weights,
  String from,
  String to,
) {
  final list = _normalize(weights);
  final known = <String, num>{};
  for (final w in list) {
    known[w.date] = w.kg;
  }
  final out = <FilledPoint>[];
  for (final d in D.eachDay(from, to)) {
    if (known.containsKey(d)) {
      out.add(FilledPoint(d, known[d]!, true));
      continue;
    }
    // 找前后最近真实点
    WeightPointLite? prev;
    WeightPointLite? next;
    for (final w in list) {
      final wd = w.date;
      if (wd.compareTo(d) < 0 && (prev == null || wd.compareTo(prev.date) > 0)) {
        prev = w;
      }
      if (wd.compareTo(d) > 0 && (next == null || wd.compareTo(next.date) < 0)) {
        next = w;
      }
    }
    if (prev != null && next != null) {
      final span = D.diffDays(prev.date, next.date);
      final frac = span == 0 ? 0.0 : D.diffDays(prev.date, d) / span;
      out.add(FilledPoint(
        d,
        R.r2(prev.kg + (next.kg - prev.kg) * frac),
        false,
      ));
    } else if (prev != null) {
      out.add(FilledPoint(d, prev.kg, false));
    } else if (next != null) {
      out.add(FilledPoint(d, next.kg, false));
    }
    // 两端都无则跳过
  }
  return out;
}

/// 7 日滑动均线。全序列真实点 >= MA7_MIN_POINTS 才计算（窗口含补值点）。
List<MaPoint> movingAverage7(List<FilledPoint> series) {
  final out = <MaPoint>[];
  final totalReal = series.where((p) => p.real).length;
  for (var i = 0; i < series.length; i++) {
    if (totalReal < AppConfig.ma7MinPoints) {
      out.add(MaPoint(series[i].date, null, series[i].real));
      continue;
    }
    final start = (i - (AppConfig.ma7Window - 1)) < 0 ? 0 : i - (AppConfig.ma7Window - 1);
    final window = series.sublist(start, i + 1);
    final sum = window.fold<num>(0, (a, p) => a + p.kg);
    out.add(MaPoint(series[i].date, R.r2(sum / window.length), series[i].real));
  }
  return out;
}

/// 归一化：Map{date,kg} 或带 date/kg 属性的对象 → WeightPointLite。
List<WeightPointLite> _normalize(Iterable<dynamic> weights) {
  return [
    for (final w in weights)
      if (w is Map)
        WeightPointLite(w['date'] as String, w['kg'] as num)
      else
        WeightPointLite(w.date as String, w.kg as num),
  ];
}

/// 周均体重（mondayDate..mondayDate+6）。记录 < WEEK_AVG_MIN_DAYS 返回 null。
double? weekAvg(Iterable<dynamic> weights, String mondayDate) {
  final pts = _normalize(weights).where((w) {
    final d = w.date;
    return d.compareTo(mondayDate) >= 0 && d.compareTo(D.addDays(mondayDate, 6)) <= 0;
  }).toList();
  if (pts.length < AppConfig.weekAvgMinDays) return null;
  final sum = pts.fold<num>(0, (a, w) => a + w.kg);
  return R.r2(sum / pts.length);
}

/// 周均值差（r2）。任一为 null 返回 null。
double? delta(num? thisWeekAvg, num? prevWeekAvg) {
  if (thisWeekAvg == null || prevWeekAvg == null) return null;
  return R.r2(thisWeekAvg - prevWeekAvg);
}

/// 趋势判定：slow / onTrack / fast / unknown。
String trendStatus(num? deltaVal, num? targetRate,
    {num? tolSlow, num? tolFast}) {
  final ts = tolSlow ?? AppConfig.tolSlow;
  final tf = tolFast ?? AppConfig.tolFast;
  if (deltaVal == null || targetRate == null) return 'unknown';
  if (deltaVal < targetRate - ts) return 'slow';
  if (deltaVal > targetRate + tf) return 'fast';
  return 'onTrack';
}

/// 连续记录天数（含今日尚未记录时从昨日往回数）。
int streak(Iterable<String> weightDates, String today) {
  final set = <String>{};
  for (final d in weightDates) {
    set.add(d);
  }
  var cur = today;
  if (!set.contains(cur)) cur = D.addDays(cur, -1);
  var n = 0;
  while (set.contains(cur)) {
    n++;
    cur = D.addDays(cur, -1);
  }
  return n;
}
