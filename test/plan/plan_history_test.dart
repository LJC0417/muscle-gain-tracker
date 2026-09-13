// 训练历史查询单元测试
// 覆盖：
//   - setVolume（含自重选项）
//   - e1RM（Epley 公式）
//   - sessionVolume（求和）
//   - checkPR（三类 PR 命中）
//   - lastPerformance（按 date+startedAt 降序，beforeSessionId 排除）
//   - prefillSet（首组用上次，第 N 组用上一组）
//   - compareBadge（↑/↓/持平/首次）
//   - rolling7TrainingStats（count/total/avgDuration）
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_gain_tracker/domain/calc/calc.dart';
import 'package:muscle_gain_tracker/domain/plan/plan.dart';

WorkoutSet _set(num w, num r, {bool bw = false, String exId = 'ex_x'}) =>
    WorkoutSet(exerciseId: exId, weightKg: w, reps: r, isBodyweight: bw);

TrainingSession _session(
  String id,
  String date,
  List<WorkoutSet> sets, {
  String status = 'completed',
  num? totalVolumeKg,
  num? durationSec,
  String? startedAt,
}) {
  return TrainingSession(
    id: id,
    date: date,
    startedAt: startedAt,
    status: status,
    totalVolumeKg: totalVolumeKg,
    durationSec: durationSec,
    sets: sets,
  );
}

void main() {
  group('setVolume', () {
    test('普通 20kg × 10 = 200', () {
      expect(setVolume(20, 10, false), 200);
    });

    test('自重 60kg × 12 = 720', () {
      expect(setVolume(60, 12, true), 720);
    });
  });

  group('e1RM', () {
    test('20kg × 10 → 20 * (1 + 10/30) = 26.67 → 26.7', () {
      expect(e1RM(20, 10), 26.7);
    });

    test('w=0 → 0', () {
      expect(e1RM(0, 10), 0);
    });
  });

  group('sessionVolume', () {
    test('3 组求和', () {
      final v = sessionVolume([
        _set(20, 10, exId: 'a'),
        _set(25, 8, exId: 'b'),
        _set(30, 6, exId: 'c'),
      ]);
      // 200 + 200 + 180 = 580
      expect(v, 580);
    });

    test('空集 → 0', () {
      expect(sessionVolume(const []), 0);
    });
  });

  group('checkPR', () {
    test('三项全突破', () {
      final h = const PrHistory(bestWeightKg: 0, bestSingleVolume: 0, bestEst1Rm: 0);
      final prs = checkPR(_set(20, 10), h);
      expect(prs.length, 3);
      expect(prs.map((p) => p.kind).toSet(), {'maxWeight', 'maxVolume', 'est1RM'});
    });

    test('历史已有 → 仅突破项', () {
      final h = const PrHistory(bestWeightKg: 25, bestSingleVolume: 300, bestEst1Rm: 27);
      // 20kg × 10: vol=200 < 300; est=26.7 < 27; w=20 < 25
      final prs = checkPR(_set(20, 10), h);
      expect(prs, isEmpty);
    });

    test('仅 maxWeight 突破', () {
      final h = const PrHistory(bestWeightKg: 25, bestSingleVolume: 1000, bestEst1Rm: 100);
      // 30kg × 8: vol=240 < 1000; est=30*(1+8/30)=38 < 100; w=30 > 25
      final prs = checkPR(_set(30, 8), h);
      expect(prs.length, 1);
      expect(prs.first.kind, 'maxWeight');
      expect(prs.first.value, 30);
      expect(prs.first.old, 25);
    });
  });

  group('lastPerformance', () {
    test('取最近一场中该动作的所有组', () {
      final sessions = [
        _session('s1', '2025-03-01', [_set(20, 10, exId: 'a'), _set(20, 8, exId: 'a')]),
        _session('s2', '2025-03-08', [_set(22, 10, exId: 'a')]),
      ];
      final last = lastPerformance(sessions, 'a');
      expect(last.length, 1);
      expect(last.first.weightKg, 22);
    });

    test('beforeSessionId 排除自身', () {
      final sessions = [
        _session('s1', '2025-03-01', [_set(20, 10, exId: 'a')]),
        _session('s2', '2025-03-08', [_set(22, 10, exId: 'a')]),
      ];
      // 从 s2 的视角回看，应拿到 s1
      final last = lastPerformance(sessions, 'a', beforeSessionId: 's2');
      expect(last.first.weightKg, 20);
    });

    test('无数据 → 空', () {
      expect(lastPerformance(const [], 'a'), isEmpty);
    });

    test('同日期按 startedAt 降序', () {
      final sessions = [
        _session('s1', '2025-03-08', [_set(20, 10, exId: 'a')], startedAt: '2025-03-08T09:00'),
        _session('s2', '2025-03-08', [_set(25, 10, exId: 'a')], startedAt: '2025-03-08T18:00'),
      ];
      final last = lastPerformance(sessions, 'a');
      expect(last.first.weightKg, 25);
    });
  });

  group('prefillSet', () {
    test('首组（setIndex=1）用上次第一组', () {
      final sessions = [
        _session('s1', '2025-03-01', [_set(25, 8, exId: 'a'), _set(25, 6, exId: 'a')]),
      ];
      final p = prefillSet(sessions, 'a', 1, const [], currentSessionId: 's2');
      expect(p.weight, 25);
      expect(p.reps, 8);
    });

    test('首组无历史 → 默认值', () {
      final p = prefillSet(const [], 'a', 1, const []);
      expect(p.weight, 20); // defaultWeightKg
      expect(p.reps, 10); // defaultReps
    });

    test('第 2 组（setIndex=2）用 currentSets[0]', () {
      final p = prefillSet(const [], 'a', 2, [_set(20, 10, exId: 'a')]);
      expect(p.weight, 20);
      expect(p.reps, 10);
    });

    test('currentSets 为空 + 非首组 → fallback', () {
      final p = prefillSet(const [], 'a', 5, const []);
      expect(p.weight, 20);
    });
  });

  group('compareBadge', () {
    test('ref=null → 首次', () {
      final r = compareBadge(_set(20, 10), null);
      expect(r.text, '首次');
      expect(r.tone, 'neutral');
    });

    test('重量 ↑', () {
      final r = compareBadge(_set(22.5, 10), _set(20, 10));
      expect(r.text, contains('↑ +2.5 kg'));
      expect(r.tone, 'good');
    });

    test('同重量但次数 ↑', () {
      final r = compareBadge(_set(20, 12), _set(20, 10));
      expect(r.text, contains('↑ +2 次'));
      expect(r.tone, 'good');
    });

    test('重量 ↓', () {
      final r = compareBadge(_set(18, 10), _set(20, 10));
      expect(r.text, '↓');
      expect(r.tone, 'muted');
    });

    test('持平', () {
      final r = compareBadge(_set(20, 10), _set(20, 10));
      expect(r.text, '持平');
      expect(r.tone, 'neutral');
    });
  });

  group('rolling7TrainingStats', () {
    test('范围过滤 + 计数 + 总容量', () {
      final sessions = [
        _session('s1', '2025-03-09', const [], totalVolumeKg: 3000, durationSec: 3600),
        _session('s2', '2025-03-12', const [], totalVolumeKg: 4000, durationSec: 4200),
        _session('s3', '2025-03-15', const [], totalVolumeKg: 5000, durationSec: 4800),
        _session('s4', '2025-03-20', const [], totalVolumeKg: 9999, durationSec: 9999), // 范围外
        _session('s5', '2025-03-15', const [], totalVolumeKg: 0, durationSec: 0, status: 'ongoing'), // 未完成
      ];
      final range = rangeOf('week', '2025-03-15', null); // 03-09..03-15（含端点）
      final stats = rolling7TrainingStats(range, sessions);
      expect(stats.count, 3);
      expect(stats.totalVolumeKg, 12000); // 3000+4000+5000
      expect(stats.avgDurationSec, (3600 + 4200 + 4800) / 3); // 4200
    });

    test('无完成 → count=0', () {
      final range = rangeOf('week', '2025-03-15', null);
      final stats = rolling7TrainingStats(range, const []);
      expect(stats.count, 0);
      expect(stats.totalVolumeKg, 0);
      expect(stats.avgDurationSec, 0);
    });
  });
}
