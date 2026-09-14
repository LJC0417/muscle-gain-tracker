/// 数据看板（P-08 体重趋势 + 热量微调 + P-09 AI 周报）
/// 对齐 prototype pages/stats.js：
///   - 体重趋势图（真实点 + 7 日均线），周/月/季/全部 切换
///   - 本周概览 KPI（体重/周均变化/节奏/连续记录/训练/容量）
///   - 热量微调建议（3 闸门 + 软边界，应用写 kcalAutoOffset，每周 1 次）
///   - AI 周报：云端大模型生成（走云服务免密钥通道），24h 缓存 + 失败降级本地模板
library;

import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai/weekly_review_ai.dart';
import '../../application/history_providers.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../../domain/calc/calc.dart';
import '../../domain/plan/plan.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  String _range = 'month';
  AiReviewOutcome? _ai;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    // 打开页面即自动生成（命中 24h 缓存则直接读缓存，不重复调用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runReview(force: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final weightsAsync = ref.watch(weightPointsStreamProvider);
    final goal = ref.watch(resolvedGoalProvider);
    final goalRow = ref.watch(goalStreamProvider).valueOrNull;
    final today = ref.watch(todayStringProvider);
    final sessionsAsync = ref.watch(allSessionsProvider);

    final weights = weightsAsync.value ?? const <WeightPointData>[];
    final sorted = [...weights]..sort((a, b) => a.date.compareTo(b.date));
    final earliest = sorted.isNotEmpty
        ? sorted.first.date
        : D.addDays(today, -29);
    final range = rangeOf(_range, today, earliest);
    final series = gapFill(weights, range.from, range.to);
    final ma = movingAverage7(series);

    // —— 本周 KPI ——
    final monday = D.mondayOf(today);
    final lite = [
      for (final w in weights) WeightPointLite(w.date, w.kg),
    ];
    final thisWeek = weekAvg(lite, monday);
    final prevWeek = weekAvg(lite, D.addDays(monday, -7));
    final d = delta(thisWeek, prevWeek);
    final trend = trendStatus(d, goal.rate);
    final trendLabel = AppConfig.labels[trend] ?? '数据不足';
    final streakN =
        streak(weights.map((w) => w.date), today);
    final tStats = rolling7TrainingStats(rangeOf('week', today, null),
        sessionsAsync.valueOrNull ?? const []);

    // —— 热量微调建议 ——
    final spanDays = D.diffDays(earliest, today);
    final weeksOfData = spanDays < 0 ? 1 : (spanDays ~/ 7) + 1;
    final suggest = suggestCalorieAdjust(AdjustCtx(
      weekAvg: thisWeek,
      prevWeekAvg: prevWeek,
      delta: d,
      targetRate: goal.rate,
      targetKcal: goal.kcal,
      bmr: goalRow != null ? _bmrOf(ref, goalRow) : null,
      weeksOfData: weeksOfData,
      lastAdjustWeek: goalRow?.lastAdjustWeek,
      thisWeekKey: D.isoWeekKey(today),
    ));

    return Scaffold(
      appBar: AppBar(title: const Text('数据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MgCard(
            title: '体重趋势',
            right: _rangeControl(),
            child: series.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: Text('还没有体重数据，先去「今日」记录一次吧',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppPalette.textSub))))
                : _chart(series, ma),
          ),
          const SizedBox(height: 12),
          MgCard(
            title: '本周概览',
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                      child: _kpi(goalRow?.currentWeightKg.toStringAsFixed(1) ??
                          '—', '当前体重')),
                  Expanded(
                      child: _kpi(d == null
                          ? '—'
                          : '${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)} kg',
                      '周均变化')),
                  Expanded(child: _kpi(trendLabel, '增重节奏')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _kpi('$streakN 天', '连续记录')),
                  Expanded(child: _kpi('${tStats.count} 次', '本周训练')),
                  Expanded(
                      child: _kpi(
                          '${tStats.totalVolumeKg.toStringAsFixed(1)} kg',
                          '本周容量')),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          MgCard(
            title: '热量微调建议（每周自动评估）',
            child: Row(
              children: [
                Text(
                  suggest.type == 'increase'
                      ? '▲'
                      : (suggest.type == 'decrease' ? '▼' : '✓'),
                  style: TextStyle(
                    fontSize: 18,
                    color: suggest.type == 'maintain'
                        ? const Color(0xFF177F45)
                        : AppPalette.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggest.type == 'maintain'
                            ? '维持当前热量'
                            : (suggest.amount > 0
                                ? '建议上调热量'
                                : '建议下调热量'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(suggest.reason,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppPalette.textSub)),
                    ],
                  ),
                ),
                if (suggest.type != 'maintain')
                  FilledButton(
                    onPressed: () => _applyAdjust(suggest, today),
                    child: const Text('应用'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          MgCard(
            title: '每周总结',
            sub: 'AI 教练结合你这周的实际数据写，不是模板套话',
            right: TextButton(
              onPressed: _aiLoading
                  ? null
                  : () => _runReview(force: true),
              child: Text(_aiLoading ? '生成中…' : '重新生成'),
            ),
            child: _reviewBody(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 周期切换 ──
  Widget _rangeControl() {
    const options = ['week', 'month', 'quarter', 'all'];
    const labels = ['周', '月', '季', '全部'];
    return SegmentedButton<String>(
      segments: [
        for (var i = 0; i < options.length; i++)
          ButtonSegment(value: options[i], label: Text(labels[i])),
      ],
      selected: {_range},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _range = s.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ── 折线图 ──
  Widget _chart(List<FilledPoint> series, List<MaPoint> ma) {
    final spots = <FlSpot>[
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].kg.toDouble()),
    ];
    final maSpots = <FlSpot>[
      for (var i = 0; i < ma.length; i++)
        if (ma[i].ma != null) FlSpot(i.toDouble(), ma[i].ma!.toDouble()),
    ];

    // y 轴范围：min-1 ~ max+1，至少 3 kg 跨度
    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    minY = (minY - 1).floorToDouble();
    maxY = (maxY + 1).ceilToDouble();
    if (maxY - minY < 3) maxY = minY + 3;

    final labelIdx = <int>{};
    final step = (series.length / 5).ceil();
    for (var i = 0; i < series.length; i += step) {
      labelIdx.add(i);
    }
    String shortDate(String iso) {
      final p = iso.split('-');
      return '${int.parse(p[1])}/${int.parse(p[2])}';
    }

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 10, color: AppPalette.textSub)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (!labelIdx.contains(i) || i >= series.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(shortDate(series[i].date),
                      style: const TextStyle(
                          fontSize: 10, color: AppPalette.textSub));
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: true),
          betweenBarsData: const [],
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 1.2,
              color: AppPalette.primary,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) =>
                    FlDotCirclePainter(radius: 2, color: AppPalette.primary),
              ),
            ),
            if (maSpots.length >= AppConfig.ma7MinPoints)
              LineChartBarData(
                spots: maSpots,
                isCurved: true,
                barWidth: 2,
                color: AppPalette.primaryDark,
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }

  double? _bmrOf(WidgetRef ref, GoalData g) {
    final p = ref.read(profileStreamProvider).valueOrNull;
    if (p == null) return null;
    try {
      return bmr(p.sex, g.currentWeightKg, p.heightCm, p.age).toDouble();
    } catch (_) {
      return null;
    }
  }

  // ── 应用微调 ──
  Future<void> _applyAdjust(CalorieAdjust suggest, String today) async {
    final db = ref.read(databaseReadyProvider).requireValue;
    final goalRow = ref.read(goalStreamProvider).valueOrNull;
    if (goalRow == null) return;
    final goalMap = <String, dynamic>{
      'kcalMode': goalRow.kcalMode,
      'kcalManual': goalRow.kcalManual,
      'kcalAutoOffset': goalRow.kcalAutoOffset,
      'proteinMode': goalRow.proteinMode,
      'proteinManual': goalRow.proteinManual,
      'carbMode': goalRow.carbMode,
      'carbManual': goalRow.carbManual,
      'fatMode': goalRow.fatMode,
      'fatManual': goalRow.fatManual,
      'rateMode': goalRow.rateMode,
      'rateManual': goalRow.rateManual,
      'surplusKcal': goalRow.surplusKcal,
      'lastWeightUsed': goalRow.lastWeightUsed,
      'lastAdjustWeek': goalRow.lastAdjustWeek,
    };
    final next = applyAdjustment(suggest, goalMap, D.isoWeekKey(today));
    await (db.update(db.goals)..where((t) => t.id.equals(goalRow.id))).write(
      GoalsCompanion(
        kcalMode: Value(next['kcalMode'] as String? ?? goalRow.kcalMode),
        kcalManual: Value((next['kcalManual'] as num?)?.toDouble()),
        kcalAutoOffset: Value(
            (next['kcalAutoOffset'] as num?)?.toDouble() ??
                goalRow.kcalAutoOffset),
        lastAdjustWeek:
            Value(next['lastAdjustWeek'] as String? ?? goalRow.lastAdjustWeek),
        lastAdjustedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.invalidate(goalStreamProvider);
    ref.invalidate(resolvedGoalProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(suggest.type == 'maintain'
            ? '已记录本周评估'
            : '已${suggest.amount > 0 ? '上调' : '下调'} ${suggest.amount.abs()} kcal'),
      ),
    );
  }

  // ── AI 周报 ──
  /// 生成/读取周报。force=true 为「重新生成」（跳过缓存，仍受当日额度限制）。
  Future<void> _runReview({required bool force}) async {
    if (_aiLoading) return;
    final weights =
        ref.read(weightPointsStreamProvider).value ?? const <WeightPointData>[];
    final sessions =
        ref.read(allSessionsProvider).valueOrNull ?? const <TrainingSession>[];
    final exercises =
        ref.read(exercisesProvider).valueOrNull ?? const <ExerciseData>[];
    final foodLogs =
        ref.read(todayFoodLogsProvider).valueOrNull ?? const <FoodLogData>[];
    final goalRow = ref.read(goalStreamProvider).valueOrNull;
    final profile = ref.read(profileStreamProvider).valueOrNull;
    final today = ref.read(todayStringProvider);
    final db = ref.read(databaseReadyProvider).requireValue;

    setState(() {
      _aiLoading = true;
    });
    try {
      final outcome = await generateAiWeeklyReview(
        db: db,
        today: today,
        goal: ref.read(resolvedGoalProvider),
        weights: weights,
        foodLogs: foodLogs,
        sessions: sessions,
        exercises: exercises,
        profile: profile,
        goalRow: goalRow,
        currentWeightKg: goalRow?.currentWeightKg,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _ai = outcome;
        _aiLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
    }
  }

  Widget _reviewBody() {
    if (_aiLoading && _ai == null) return _aiSkeleton();
    final ai = _ai;
    if (ai == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('正等你写点数据进来，有记录后我会按周给你复盘。',
              style: TextStyle(fontSize: 13, color: AppPalette.textSub)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _runReview(force: false),
            child: const Text('生成本周总结'),
          ),
        ],
      );
    }
    // 数据侧 KPI（无论 AI 还是降级都用本地算法口径）
    final kpi = ai.local;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_aiLoading) ...[
          // 重新生成中：旧内容保留，顶部给加载提示
          Row(
            children: const [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppPalette.primary),
              ),
              SizedBox(width: 8),
              Text('AI 教练正在重写…',
                  style: TextStyle(fontSize: 12, color: AppPalette.textSub)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.primaryWeak,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ai.text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: AppPalette.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (ai.fromAi)
              const MgBadge(
                text: 'AI 教练',
                bg: AppPalette.surfaceMuted,
                fg: AppPalette.textSub,
              )
            else
              Expanded(
                child: Text(
                  '⚠ ${ai.note ?? '网络不可用，显示本地建议'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppPalette.textWeak),
                ),
              ),
            if (ai.fromAi && ai.cached)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('· 今日已生成，24 小时内不重复请求',
                    style:
                        TextStyle(fontSize: 11, color: AppPalette.textWeak)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _kvMini('本周体重均', kpi.thisWeekAvg == null
                ? '—'
                : '${kpi.thisWeekAvg!.toStringAsFixed(2)} kg'),
            _kvMini('周均变化', kpi.delta == null
                ? '—'
                : '${kpi.delta! >= 0 ? '+' : ''}${kpi.delta!.toStringAsFixed(2)} kg'),
            _kvMini('日均热量', '${kpi.avgKcal} kcal'),
            _kvMini('日均蛋白', '${kpi.avgP} g'),
            _kvMini('完成训练', '${kpi.trainCount} 次'),
            _kvMini('训练容量', '${kpi.volume.toStringAsFixed(0)} kg'),
          ],
        ),
      ],
    );
  }

  Widget _aiSkeleton() {
    Widget bar(double w) => Container(
          width: w,
          height: 12,
          decoration: BoxDecoration(
            color: AppPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppPalette.primary),
            ),
            SizedBox(width: 8),
            Text('AI 教练正在写你的周评…',
                style: TextStyle(fontSize: 12, color: AppPalette.textSub)),
          ],
        ),
        const SizedBox(height: 14),
        bar(double.infinity),
        const SizedBox(height: 8),
        bar(240),
        const SizedBox(height: 8),
        bar(180),
      ],
    );
  }
}

Widget _kvMini(String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(fontSize: 11, color: AppPalette.textWeak)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          )),
    ],
  );
}

Widget _kpi(String v, String l) {
  return Column(
    children: [
      Text(
        v,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        l,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          color: AppPalette.textSub,
        ),
      ),
    ],
  );
}
