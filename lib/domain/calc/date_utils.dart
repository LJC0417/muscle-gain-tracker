/// 本地时区日期工具（ARCHITECTURE 7.4）。
/// 业务规则：
///   - 日期字符串统一为 yyyy-MM-dd（绝不直接用 ISO 8601 / toUtc）
///   - 周一为一周之始（weekday 1 = 周一，7 = 周日）
///   - 跨日/跨年所有计算走本地 DateTime，禁用 DateTime.toUtc()
class D {
  D._();

  static String pad(int n) => n < 10 ? '0$n' : '$n';

  /// 把 'yyyy-MM-dd' 解析为本地 DateTime（00:00:00）。
  static DateTime parseDate(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// 把本地 DateTime 格式化 'yyyy-MM-dd'。
  static String fmtDate(DateTime d) =>
      '${d.year}-${pad(d.month)}-${pad(d.day)}';

  /// 锚定的"今天"——单元测试与演示模式使用真实日期；生产由调用方覆盖。
  /// 在 Flutter UI 层会替换为 `MG.today() = CONFIG.DEMO_TODAY`，这里取系统当前。
  static String todayStr() => fmtDate(DateTime.now());

  /// 'yyyy-MM-dd' + n 天（n 可负）。
  static String addDays(String dateStr, int n) {
    final d = parseDate(dateStr);
    return fmtDate(d.add(Duration(days: n)));
  }

  /// 整日差：b - a（按本地时区 00:00 相减）。
  static int diffDays(String a, String b) {
    final pa = parseDate(a);
    final pb = parseDate(b);
    return (pb.difference(pa).inHours / 24).round();
  }

  /// 该日期所在自然周的周一（'yyyy-MM-dd'）。
  static String mondayOf(String dateStr) {
    final d = parseDate(dateStr);
    final day = (d.weekday + 6) % 7; // 1=周一 → 0；7=周日 → 6
    return fmtDate(d.subtract(Duration(days: day)));
  }

  /// weekday 1=周一, 7=周日（与 JS 版一致）。
  static int weekday1to7(String dateStr) =>
      (parseDate(dateStr).weekday + 6) % 7 + 1;

  /// ISO 周编号（{year, week}）。周四所在年即为该周所属年。
  static ({int year, int week}) isoWeekNumber(String dateStr) {
    final d = parseDate(mondayOf(dateStr)).add(const Duration(days: 3));
    final firstThu = DateTime(d.year, 1, 4);
    final fday = (firstThu.weekday + 6) % 7;
    final mondayOfFirstWeek =
        firstThu.subtract(Duration(days: fday));
    final week = 1 +
        ((d.difference(mondayOfFirstWeek).inHours / 24) / 7).round();
    return (year: d.year, week: week);
  }

  /// 'YYYY-Www'（例 '2025-W11'）。
  static String isoWeekKey(String dateStr) {
    final n = isoWeekNumber(dateStr);
    return '${n.year}-W${n.week < 10 ? '0${n.week}' : n.week}';
  }

  /// [from]..[to] 闭区间每一天（含两端），含保护 10000 天。
  static List<String> eachDay(String from, String to) {
    final out = <String>[];
    var cur = from;
    var guard = 0;
    while (diffDays(cur, to) >= 0 && guard < 10000) {
      out.add(cur);
      cur = addDays(cur, 1);
      guard++;
    }
    return out;
  }
}
