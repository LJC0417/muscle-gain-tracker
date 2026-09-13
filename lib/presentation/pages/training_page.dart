/// 训练页 P-04（ARCHITECTURE F04）
///   - 顶部周排期（周一~周日 7 个圆点，今日高亮，点选切换）
///   - 训练日详情卡：前 3 个动作 + 总数 + 预计分钟数 + 三态按钮
///   - 「自定义内容」disable + toast
///   - 本周训练进度条
///
/// 本期不实现：实际训练执行、自定义训练日 picker、自定义动作。
/// 所有对应按钮统一 SnackBar「本迭代未包含训练执行」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../data/database.dart';
import '../../domain/plan/plan.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

class TrainingPage extends ConsumerStatefulWidget {
  const TrainingPage({super.key});

  @override
  ConsumerState<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends ConsumerState<TrainingPage> {
  String? _selCodeOverride;

  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider);
    final profileAsync = ref.watch(profileStreamProvider);
    final today = ref.watch(todayStringProvider);
    final exercisesAsync = ref.watch(exercisesProvider);
    final sessionAsync = ref.watch(todayTrainingSessionStreamProvider);

    if (profileAsync.value == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppPalette.primary),
        ),
      );
    }

    final todayWd = _weekday1to7(today);
    final todayCode = plan.pattern[todayWd] ?? '';

    // 默认选中 = 今天 code；今天若空则取计划第一个 code
    final fallbackCode = plan.days.isNotEmpty ? plan.days.first.code : '';
    final validCodes = plan.days.map((d) => d.code).toSet();
    final selCode = (_selCodeOverride != null &&
            validCodes.contains(_selCodeOverride))
        ? _selCodeOverride!
        : (todayCode.isNotEmpty ? todayCode : fallbackCode);

    return Scaffold(
      appBar: AppBar(title: const Text('训练')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(exercisesProvider);
          ref.invalidate(todayTrainingSessionStreamProvider);
          ref.invalidate(_weekSessionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _WeekStripCard(
              plan: plan,
              todayWd: todayWd,
              selCode: selCode,
              onSelect: (code) {
                setState(() => _selCodeOverride = code);
              },
            ),
            const SizedBox(height: 12),
            _DayDetailCard(
              plan: plan,
              selCode: selCode,
              todayCode: todayCode,
              exercisesAsync: exercisesAsync,
              sessionAsync: sessionAsync,
              onAction: _blockedSnack,
              onCustomize: _blockedSnack,
            ),
            const SizedBox(height: 12),
            const _WeeklyProgressCard(),
          ],
        ),
      ),
    );
  }

  void _blockedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本迭代未包含训练执行')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 周排期卡
// ════════════════════════════════════════════════════════════════════

class _WeekStripCard extends StatelessWidget {
  final StoredPlan plan;
  final int todayWd;
  final String selCode;
  final ValueChanged<String> onSelect;

  const _WeekStripCard({
    required this.plan,
    required this.todayWd,
    required this.selCode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return MgCard(
      title: '本周排期',
      sub: '点选某天查看动作',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var wd = 1; wd <= 7; wd++) _buildDot(wd),
        ],
      ),
    );
  }

  Widget _buildDot(int wd) {
    final code = plan.pattern[wd] ?? '';
    final has = code.isNotEmpty;
    final isToday = wd == todayWd;
    final isSel = !isToday && has && code == selCode;
    final label = _TrainingPageState._weekLabels[wd - 1];

    Color bg;
    Color fg;
    if (isToday) {
      bg = AppPalette.primary;
      fg = Colors.white;
    } else if (isSel) {
      bg = AppPalette.primaryWeak;
      fg = AppPalette.primaryDark;
    } else if (has) {
      bg = AppPalette.surfaceMuted;
      fg = AppPalette.text;
    } else {
      bg = AppPalette.background;
      fg = AppPalette.textWeak;
    }

    return Expanded(
      child: GestureDetector(
        onTap: has ? () => onSelect(code) : null,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(99),
                border: isToday
                    ? Border.all(color: AppPalette.primaryDark, width: 1.5)
                    : null,
              ),
              child: Text(
                has ? code : '休',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppPalette.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 训练日详情卡
// ════════════════════════════════════════════════════════════════════

class _DayDetailCard extends StatelessWidget {
  final StoredPlan plan;
  final String selCode;
  final String todayCode;
  final AsyncValue<List<ExerciseData>> exercisesAsync;
  final AsyncValue<TrainingSessionData?> sessionAsync;
  final VoidCallback onAction;
  final VoidCallback onCustomize;

  const _DayDetailCard({
    required this.plan,
    required this.selCode,
    required this.todayCode,
    required this.exercisesAsync,
    required this.sessionAsync,
    required this.onAction,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final day = plan.days.where((d) => d.code == selCode).firstOrNull;

    if (day == null) {
      return const MgCard(
        title: '训练日详情',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '暂未生成训练计划，请先在「我的」中重新生成',
              style: TextStyle(fontSize: 13, color: AppPalette.textSub),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final isTodayDone =
        selCode == todayCode && sessionAsync.value?.status == 'completed';
    final String btnLabel;
    final bool btnDisabled;
    if (isTodayDone) {
      btnLabel = '今日训练已完成';
      btnDisabled = true;
    } else if (selCode == todayCode) {
      btnLabel = '开始今日训练';
      btnDisabled = false;
    } else {
      btnLabel = '开始训练';
      btnDisabled = false;
    }

    return MgCard(
      title: '训练日详情',
      sub: day.code,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${day.code} · ${day.name}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isTodayDone)
                          const MgBadge(
                            text: '已完成',
                            bg: Color(0xFFE7F8EE),
                            fg: Color(0xFF177F45),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.entries.length} 个动作 · 约 ${day.estMinutes} 分钟',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppPalette.textSub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: btnDisabled ? null : onAction,
                child: Text(btnLabel),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _exerciseList(day, exercisesAsync),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onCustomize,
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('自定义内容'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exerciseList(PlanDay day, AsyncValue<List<ExerciseData>> async) {
    return async.when(
      data: (all) {
        final map = {for (final e in all) e.id: e};
        final show = day.entries.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final en in show)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 16,
                      color: AppPalette.textSub,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        map[en.exerciseId]?.name ?? en.exerciseId,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${en.targetSets} 组',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textSub,
                      ),
                    ),
                  ],
                ),
              ),
            if (day.entries.length > 3)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '…等更多动作',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.textWeak,
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(
          minHeight: 4,
          color: AppPalette.primary,
          backgroundColor: AppPalette.surfaceMuted,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 本周训练进度
// ════════════════════════════════════════════════════════════════════

/// 本周已完成训练次数（TrainingSessions.status='completed'）。
final _weekSessionsProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseReadyProvider).requireValue;
  final monday = ref.watch(mondayOfTodayProvider);
  final today = ref.watch(todayStringProvider);
  final rows = await (db.select(db.trainingSessions)
        ..where((t) => t.date.isBetweenValues(monday, today))
        ..where((t) => t.status.equals('completed')))
      .get();
  return rows.length;
});

class _WeeklyProgressCard extends ConsumerWidget {
  const _WeeklyProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    final doneAsync = ref.watch(_weekSessionsProvider);
    final planned = plan.pattern.values.where((c) => c.isNotEmpty).length;
    final done = doneAsync.value ?? 0;
    final ratio = planned > 0 ? (done / planned).clamp(0.0, 1.0) : 0.0;

    return MgCard(
      title: '本周训练进度',
      sub: planned == 0 ? '请先生成训练计划' : '已完成 $done / $planned 天',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: AppPalette.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppPalette.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _progressHint(ratio, planned, plan),
            style: const TextStyle(
              fontSize: 12,
              color: AppPalette.textSub,
            ),
          ),
        ],
      ),
    );
  }

  String _progressHint(double ratio, int planned, StoredPlan plan) {
    if (planned == 0) return '在「我的」里点「重新生成训练计划」即可。';
    if (ratio >= 1.0) return '本周期已完成，继续保持！';
    if (ratio >= 0.5) return '进行中，下一训练日：${_nextPlannedLabel(plan)}';
    return '刚开始，建议本周累计完成 $planned 次训练';
  }

  String _nextPlannedLabel(StoredPlan plan) {
    for (var i = 1; i <= 7; i++) {
      final c = plan.pattern[i];
      if (c != null && c.isNotEmpty) return c;
    }
    return '—';
  }
}

// ════════════════════════════════════════════════════════════════════
// 工具
// ════════════════════════════════════════════════════════════════════

/// ISO yyyy-MM-dd → weekday 1..7（1=周一）。
int _weekday1to7(String iso) {
  final d = DateTime.parse(iso);
  return ((d.weekday + 6) % 7) + 1;
}
