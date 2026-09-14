/// 睡眠页 P-06
///
/// 布局：
///   ① 日期切换行：‹ 前一晚 … 最多回看 3 天（今天不可右翻）
///   ② 睡眠总时长卡：总时长 + 就寝/起床时间段 + 睡眠效率，
///      内含四阶段占比条与明细（清醒 / 快速眼动 / 浅睡 / 深睡）
///   ③ 睡眠阶段时间轴卡：整晚逐段分布
///   ④ 睡眠指标卡：睡眠心率 / 呼吸率 / 血氧 / 心率变异性 2×2
///   ⑤ 睡眠建议卡：按当晚数据规则式生成（改进项 + 注意事项）
///
/// 数据：Health Connect 同步（SleepSyncService）→ SleepSessions/StageRows/Metrics；
///       无数据时给「连接手表数据」引导。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../application/sleep_models.dart';
import '../../application/sleep_providers.dart';
import '../../application/sleep_sync_service.dart';
import '../theme/app_theme.dart';

/// 阶段配色（对齐主流睡眠 App 用色习惯）。
const _stageColors = {
  SleepStage.awake: Color(0xFFCED4DA),
  SleepStage.rem: Color(0xFF9775FA),
  SleepStage.light: Color(0xFF74C0FC),
  SleepStage.deep: Color(0xFF4C6EF5),
};

class SleepPage extends ConsumerStatefulWidget {
  const SleepPage({super.key});

  @override
  ConsumerState<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends ConsumerState<SleepPage> {
  /// 回看偏移：0=今晚（起床日=今天），1..3 = 前几晚。
  int _offset = 0;
  bool _syncing = false;

  static const _maxOffset = 3;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayStringProvider);
    final date = _dateOf(today, _offset);
    final dayAsync = ref.watch(sleepNightProvider(date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('睡眠'),
        actions: [
          IconButton(
            tooltip: '同步手表数据',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 22),
          ),
        ],
      ),
      body: dayAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => _emptyState('加载失败：$e'),
        data: (day) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _dateSwitcher(today),
            const SizedBox(height: 12),
            if (day == null)
              _emptyState(_offset == 0
                  ? '今晚还没有睡眠数据\n点右上角同步，或等明早手表数据同步后自动出现'
                  : '这一晚没有睡眠数据')
            else ...[
              _totalCard(day),
              const SizedBox(height: 12),
              _timelineCard(day),
              const SizedBox(height: 12),
              _metricsCard(day),
              const SizedBox(height: 12),
              _adviceCard(day),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: AppPalette.textWeak),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '数据来源：Health Connect（vivo 健康）；如无数据，请在 vivo 健康的设置里开启「数据共享」',
                      style:
                          TextStyle(fontSize: 12, color: AppPalette.textSub),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _dateOf(String today, int offset) {
    final d = DateTime.parse(today).subtract(Duration(days: offset));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ── 同步 ──

  Future<void> _sync() async {
    setState(() => _syncing = true);
    SleepSyncReport report;
    try {
      final ok = await SleepSyncService.instance.hasPermissions() ||
          await SleepSyncService.instance.requestPermissions();
      if (!ok) {
        _toast('未获得 Health Connect 权限，同步中止');
        return;
      }
      final db = await ref.read(databaseReadyProvider.future);
      report = await SleepSyncService.instance.sync(db, days: 4);
      ref.invalidate(sleepNightProvider);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (!mounted) return;
    _toast(report.error != null
        ? '同步失败，请确认 vivo 健康已开启数据共享'
        : report.nights == 0
            ? 'Health Connect 里还没有睡眠数据；确认 vivo 健康已开启数据共享后明早再试'
            : '已同步 ${report.nights} 晚睡眠数据');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ════════════════════════════════════════════════════════════════
  // ① 日期切换
  // ════════════════════════════════════════════════════════════════

  Widget _dateSwitcher(String today) {
    final label = _offset == 0
        ? '今晚'
        : _offset == 1
            ? '昨晚'
            : '$_offset 天前';
    final date = _dateOf(today, _offset);
    final md = date.substring(5).replaceFirst('-', '/');
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _offset >= _maxOffset
              ? null
              : () => setState(() => _offset++),
          icon: const Icon(Icons.chevron_left, size: 26),
        ),
        Expanded(
          child: Column(
            children: [
              Text('$label（$md）',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.text)),
              if (_offset > 0)
                GestureDetector(
                  onTap: () => setState(() => _offset = 0),
                  child: const Text('回到今晚',
                      style: TextStyle(fontSize: 12, color: AppPalette.primary)),
                ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _offset <= 0 ? null : () => setState(() => _offset--),
          icon: const Icon(Icons.chevron_right, size: 26),
        ),
      ],
    );
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.bedtime_outlined,
              size: 44, color: AppPalette.textWeak),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: AppPalette.textSub)),
          const SizedBox(height: 16),
          if (_offset == 0)
            FilledButton(
              onPressed: _syncing ? null : _sync,
              child: const Text('连接手表数据'),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ② 总时长
  // ════════════════════════════════════════════════════════════════

  Widget _totalCard(SleepDay day) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dur(day.asleepMin),
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.text,
                    height: 1.1),
              ),
              const Spacer(),
              _effBadge(day.efficiency),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '睡眠总时长（卧床 ${hm(day.bedtimeMin)} – ${hm(day.wakeMin)}）',
            style: const TextStyle(fontSize: 13, color: AppPalette.textSub),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final s in SleepStage.values)
                    if (day.durationOf(s) > 0)
                      Expanded(
                        flex: day.durationOf(s),
                        child: ColoredBox(
                            color: _stageColors[s]!,
                            child: const SizedBox.expand()),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...SleepStage.values.reversed.map((s) {
            final m = day.durationOf(s);
            if (m == 0) return const SizedBox.shrink();
            final pct = day.pctOf(s);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _stageColors[s]!,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(stageLabels[s]!,
                      style: const TextStyle(
                          fontSize: 14, color: AppPalette.text)),
                  const Spacer(),
                  Text('${dur(m)} · $pct%',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppPalette.textSub,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _effBadge(double eff) {
    final good = eff >= 85;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFE6F7EF) : AppPalette.primaryWeak,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '睡眠效率 ${eff.toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: good ? const Color(0xFF0F9960) : AppPalette.primaryDark,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ③ 时间轴
  // ════════════════════════════════════════════════════════════════

  Widget _timelineCard(SleepDay day) {
    final span = day.windowEndMin - day.windowStartMin;
    final ticks = <String>[];
    for (var t = day.windowStartMin; t <= day.windowEndMin; t += 120) {
      ticks.add(hm(t));
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('睡眠阶段分布',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.text)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 26,
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                double frac(int min) =>
                    ((min - day.windowStartMin).clamp(0, span)) / span;
                return Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFFF2F2F2)),
                    ),
                    for (final g in day.segments)
                      Positioned(
                        left: frac(g.startMin) * w,
                        width: (frac(g.endMin) - frac(g.startMin)) * w,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(color: _stageColors[g.stage]!),
                      ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in ticks)
                Text(t,
                    style: const TextStyle(
                        fontSize: 11, color: AppPalette.textWeak)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in SleepStage.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _stageColors[s]!,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(stageLabels[s]!,
                        style: const TextStyle(
                            fontSize: 12, color: AppPalette.textSub)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ④ 体征
  // ════════════════════════════════════════════════════════════════

  Widget _metricsCard(SleepDay day) {
    String? v(double? x, {int digits = 0}) =>
        x == null ? null : x.toStringAsFixed(digits);
    final items = [
      (
        '睡眠心率',
        v(day.avgHr) ?? '—',
        day.avgHr == null ? '' : 'bpm',
        day.avgHr == null
            ? '手表未记录'
            : '最低 ${v(day.minHr)} · 最高 ${v(day.maxHr)}'
      ),
      (
        '呼吸率',
        v(day.respirationRate, digits: 1) ?? '—',
        day.respirationRate == null ? '' : '次/分',
        day.respirationRate == null ? '手表未记录' : '整晚平均'
      ),
      (
        '血氧',
        v(day.spo2Avg) ?? '—',
        day.spo2Avg == null ? '' : '%',
        day.spo2Min == null ? '手表未记录' : '最低 ${v(day.spo2Min)}%'
      ),
      (
        '心率变异性',
        v(day.hrvMs) ?? '—',
        day.hrvMs == null ? '' : 'ms',
        day.hrvMs == null ? '手表未记录' : 'RMSSD'
      ),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('睡眠体征',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.text)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              for (final (label, value, unit, sub) in items)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: AppPalette.textSub)),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(value,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.text)),
                          if (unit.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Text(unit,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.textSub)),
                          ],
                        ],
                      ),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 11, color: AppPalette.textWeak)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ⑤ 建议
  // ════════════════════════════════════════════════════════════════

  Widget _adviceCard(SleepDay day) {
    final advice = buildSleepAdvice(day);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('睡眠建议',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.text)),
          const SizedBox(height: 12),
          ...advice.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: a.positive
                            ? const Color(0xFF22C55E)
                            : AppPalette.warn,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.text)),
                          const SizedBox(height: 2),
                          Text(a.detail,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.55,
                                  color: AppPalette.textSub)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
      ),
      child: child,
    );
  }
}
