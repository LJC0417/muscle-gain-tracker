// 趋势分析单元测试（ARCHITECTURE F02 验收）
// 覆盖：gapFill / movingAverage7 / weekAvg / delta / trendStatus / streak
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/calc/calc.dart';

void main() {
  group('D 日期工具', () {
    test('parseDate / fmtDate 互逆', () {
      final d = D.parseDate('2025-03-10');
      expect(D.fmtDate(d), '2025-03-10');
    });

    test('addDays 跨月', () {
      expect(D.addDays('2025-03-31', 1), '2025-04-01');
      expect(D.addDays('2025-03-01', -1), '2025-02-28');
    });

    test('diffDays', () {
      expect(D.diffDays('2025-03-10', '2025-03-17'), 7);
    });

    test('mondayOf — 周一返回自身', () {
      // 2025-03-10 是周一
      expect(D.mondayOf('2025-03-10'), '2025-03-10');
    });

    test('mondayOf — 周日返回上周一', () {
      // 2025-03-16 是周日 → 上周一 2025-03-10
      expect(D.mondayOf('2025-03-16'), '2025-03-10');
    });

    test('weekday1to7 — 周一=1，周日=7', () {
      expect(D.weekday1to7('2025-03-10'), 1);
      expect(D.weekday1to7('2025-03-16'), 7);
    });

    test('isoWeekKey', () {
      // 2025-03-10 (周一) 所在 ISO 周：当年第 11 周
      expect(D.isoWeekKey('2025-03-10'), '2025-W11');
    });

    test('eachDay 闭区间', () {
      final days = D.eachDay('2025-03-10', '2025-03-12');
      expect(days, ['2025-03-10', '2025-03-11', '2025-03-12']);
    });
  });

  group('gapFill 缺失日插值', () {
    test('全部缺失端点', () {
      final out = gapFill(<Map<String, Object>>[], '2025-03-10', '2025-03-12');
      expect(out, isEmpty);
    });

    test('只有首日 → 后续天复制首日值', () {
      final src = [
        {'date': '2025-03-10', 'kg': 62.0},
      ];
      final out = gapFill(src, '2025-03-10', '2025-03-12');
      expect(out.length, 3);
      expect(out[0].real, true);
      expect(out[0].kg, 62.0);
      expect(out[1].real, false);
      expect(out[1].kg, 62.0);
      expect(out[2].real, false);
      expect(out[2].kg, 62.0);
    });

    test('两端有 → 中间线性插值', () {
      final src = [
        {'date': '2025-03-10', 'kg': 62.0},
        {'date': '2025-03-14', 'kg': 62.4},
      ];
      final out = gapFill(src, '2025-03-10', '2025-03-14');
      expect(out.length, 5);
      expect(out[0].real, true);
      expect(out[4].real, true);
      // 03-12 是中点：(62.0 + 62.4) / 2 = 62.2
      expect(out[2].kg, 62.2);
      expect(out[2].real, false);
    });
  });

  group('movingAverage7', () {
    test('窗口内真实点 < 3 → ma=null', () {
      final series = [
        const FilledPoint('2025-03-10', 62.0, true),
        const FilledPoint('2025-03-11', 62.0, false),
        const FilledPoint('2025-03-12', 62.0, false),
        const FilledPoint('2025-03-13', 62.0, false),
        const FilledPoint('2025-03-14', 62.0, false),
      ];
      final ma = movingAverage7(series);
      // 只有 1 个真实点，全部 ma=null
      expect(ma.every((p) => p.ma == null), true);
    });

    test('窗口内真实点 >= 3 → 计算均值', () {
      final series = [
        const FilledPoint('2025-03-10', 62.0, true),
        const FilledPoint('2025-03-11', 62.1, true),
        const FilledPoint('2025-03-12', 62.2, true),
        const FilledPoint('2025-03-13', 62.3, false),
      ];
      final ma = movingAverage7(series);
      expect(ma[0].ma, 62.0); // 1 个点 = 62.0
      expect(ma[1].ma, 62.05); // (62.0+62.1)/2 = 62.05 → r2
      expect(ma[2].ma, 62.1); // (62.0+62.1+62.2)/3 = 62.1 → r2
      expect(ma[3].ma, 62.15); // (62.0+62.1+62.2+62.3)/4 = 62.15
    });
  });

  group('weekAvg', () {
    test('记录 < 3 天返回 null', () {
      final src = [
        {'date': '2025-03-10', 'kg': 62.0},
      ];
      expect(weekAvg(src, '2025-03-10'), isNull);
    });

    test('记录 >= 3 天返回均值（r2）', () {
      final src = [
        {'date': '2025-03-10', 'kg': 62.0},
        {'date': '2025-03-11', 'kg': 62.1},
        {'date': '2025-03-12', 'kg': 62.2},
      ];
      expect(weekAvg(src, '2025-03-10'), 62.1);
    });

    test('跨周不计入', () {
      final src = [
        {'date': '2025-03-09', 'kg': 99.0}, // 上周日
        {'date': '2025-03-10', 'kg': 62.0},
        {'date': '2025-03-11', 'kg': 62.1},
        {'date': '2025-03-12', 'kg': 62.2},
      ];
      expect(weekAvg(src, '2025-03-10'), 62.1);
    });
  });

  group('delta', () {
    test('任一为 null 返回 null', () {
      expect(delta(null, 62.0), isNull);
      expect(delta(62.0, null), isNull);
    });

    test('正常差值 r2', () {
      expect(delta(62.2, 62.0), 0.2);
    });
  });

  group('trendStatus', () {
    test('unknown — 参数缺失', () {
      expect(trendStatus(null, 0.25), 'unknown');
      expect(trendStatus(0.1, null), 'unknown');
    });

    test('slow — delta 远小于目标', () {
      // 0.10 < 0.25 - 0.05 = 0.20 → slow
      expect(trendStatus(0.10, 0.25), 'slow');
    });

    test('onTrack — 区间内', () {
      // 0.25 在 [0.20, 0.40] 内
      expect(trendStatus(0.25, 0.25), 'onTrack');
      expect(trendStatus(0.30, 0.25), 'onTrack');
    });

    test('fast — delta 远大于目标', () {
      // 0.50 > 0.25 + 0.15 = 0.40 → fast
      expect(trendStatus(0.50, 0.25), 'fast');
    });
  });

  group('streak 连续记录天数', () {
    test('今日已记录', () {
      final dates = ['2025-03-08', '2025-03-09', '2025-03-10'];
      expect(streak(dates, '2025-03-10'), 3);
    });

    test('今日未记录 → 从昨日往回数', () {
      final dates = ['2025-03-08', '2025-03-09'];
      expect(streak(dates, '2025-03-10'), 2);
    });

    test('中断返回 0', () {
      final dates = ['2025-03-07', '2025-03-08'];
      expect(streak(dates, '2025-03-10'), 0);
    });
  });

  group('rangeOf / unitConvert', () {
    test('rangeOf 各档', () {
      final week = rangeOf('week', '2025-03-15', null);
      expect(week.from, '2025-03-09'); // 含端点 7 天
      expect(week.to, '2025-03-15');

      final month = rangeOf('month', '2025-03-15', null);
      expect(month.from, '2025-02-15'); // 30 天
      expect(month.to, '2025-03-15');

      final quarter = rangeOf('quarter', '2025-03-15', null);
      expect(quarter.from, '2024-12-16'); // 90 天
      expect(quarter.to, '2025-03-15');

      final all = rangeOf('all', '2025-03-15', '2024-12-01');
      expect(all.from, '2024-12-01');
      expect(all.to, '2025-03-15');
    });

    test('unitConvert kg / 斤', () {
      expect(unitConvert(62.0, 'kg'), 62.0);
      expect(unitConvert(62.0, 'jin'), 124.0); // 62*2 = 124
    });

    test('unitConvert null', () {
      expect(unitConvert(null, 'kg'), isNull);
    });
  });
}
