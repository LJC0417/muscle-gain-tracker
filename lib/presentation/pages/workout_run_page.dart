/// 训练执行页（P-05 记录每组重量×次数 + P-06 渐进超负荷预填 / PR 判定）
/// 对齐 prototype pages/workoutRun.js：
///   - 每个动作一行：重量 + 次数 + 「完成」按钮（完成时 N 组按同一重量×次数记录）
///   - 预填上次成绩（prefillSet）；badge 显示对比（↑/↓/持平/首次）
///   - 「结束训练并保存」：展开为 N 组 WorkoutSets，PR 判定（maxWeight/maxVolume/est1RM）
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/history_providers.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../../domain/plan/plan.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

class WorkoutRunPage extends ConsumerStatefulWidget {
  final String planCode;
  const WorkoutRunPage({super.key, required this.planCode});

  @override
  ConsumerState<WorkoutRunPage> createState() => _WorkoutRunPageState();
}

class _RunItem {
  final PlanEntry entry;
  final ExerciseData? ex;
  final WorkoutSet? ref; // 上次第一组
  final TextEditingController weightCtrl;
  final TextEditingController repsCtrl;
  bool done = false;
  String badge = '--';
  Color badgeColor = AppPalette.textWeak;
  _RunItem({
    required this.entry,
    required this.ex,
    required this.ref,
  })  : weightCtrl = TextEditingController(
          text: ref == null
              ? AppConfig.defaultWeightKg.toInt().toString()
              : _fmtNum(ref.weightKg),
        ),
        repsCtrl = TextEditingController(
          text: ref == null
              ? AppConfig.defaultReps.toString()
              : ref.reps.toInt().toString(),
        ),
        badge = ref == null ? '首次' : '--',
        badgeColor = AppPalette.textWeak;

  static String _fmtNum(num v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

class _WorkoutRunPageState extends ConsumerState<WorkoutRunPage> {
  List<_RunItem> _items = [];
  bool _saved = false;
  bool _saving = false;
  bool _inited = false;

  PlanDay? _day;
  StoredPlan? _plan;

  @override
  void initState() {
    super.initState();
    // initState 里不能 ref.read（依赖未就绪），放 post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final plan = ref.read(planProvider);
    final sessionsAsync = ref.read(allSessionsProvider);
    final exercisesAsync = await ref.read(exercisesProvider.future);
    final day = plan.effectiveDay(widget.planCode);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _day = day;
      _inited = true;
    });
    if (day == null) return;
    final sessions = sessionsAsync.valueOrNull ?? const <TrainingSession>[];
    final map = {for (final e in exercisesAsync) e.id: e};
    setState(() {
      _items = [
        for (final en in day.entries)
          _RunItem(
            entry: en,
            ex: map[en.exerciseId],
            ref: _firstSetOf(sessions, en.exerciseId),
          ),
      ];
    });
  }

  WorkoutSet? _firstSetOf(List<TrainingSession> sessions, String exId) {
    final last = lastPerformance(sessions, exId);
    return last.isEmpty ? null : last.first;
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.weightCtrl.dispose();
      it.repsCtrl.dispose();
    }
    super.dispose();
  }

  int get _completedCount => _items.where((x) => x.done).length;
  double get _volume {
    var v = 0.0;
    for (final it in _items) {
      final w = double.tryParse(it.weightCtrl.text) ?? 0;
      final r = int.tryParse(it.repsCtrl.text) ?? 0;
      if (it.done && w > 0 && r > 0) {
        v += setVolume(w, r, false).toDouble() * it.entry.targetSets;
      }
    }
    return (v * 10).roundToDouble() / 10;
  }

  void _complete(_RunItem it) {
    final w = double.tryParse(it.weightCtrl.text);
    final r = int.tryParse(it.repsCtrl.text);
    if (w == null || r == null || w <= 0 || r <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填好重量和次数')),
      );
      return;
    }
    final cur = WorkoutSet(
      exerciseId: it.entry.exerciseId,
      weightKg: w,
      reps: r,
      isBodyweight: false,
    );
    final b = compareBadge(cur, it.ref);
    setState(() {
      it.done = true;
      it.badge = b.text;
      it.badgeColor =
          b.tone == 'good' ? const Color(0xFF177F45) : AppPalette.textSub;
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseReadyProvider).requireValue;
      final day = _day;
      if (day == null) return;
      final sid = 'ws_${DateTime.now().millisecondsSinceEpoch}';
      final rows = <WorkoutSetsCompanion>[];
      for (final it in _items) {
        final w = double.tryParse(it.weightCtrl.text) ?? 0;
        final r = int.tryParse(it.repsCtrl.text) ?? 0;
        if (w <= 0 || r <= 0) continue; // 跳过未填的动作
        for (var s = 1; s <= it.entry.targetSets; s++) {
          rows.add(WorkoutSetsCompanion.insert(
            sessionId: sid,
            exerciseId: it.entry.exerciseId,
            setIndex: s,
            weightKg: w,
            reps: r,
            volumeKg: Value(setVolume(w, r, false).toDouble()),
            createdAt: Value(DateTime.now()),
          ));
        }
      }
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有可保存的训练数据')),
        );
        setState(() => _saving = false);
        return;
      }

      final totalVol =
          rows.fold<double>(0, (a, x) => a + (x.volumeKg.value ?? 0));
      final now = DateTime.now();
      await db.into(db.trainingSessions).insert(TrainingSessionsCompanion.insert(
            id: sid,
            date: ref.read(todayStringProvider),
            templateCode: Value(day.code),
            status: 'completed',
            totalVolumeKg: Value((totalVol * 10).roundToDouble() / 10),
            durationSec: Value(day.estMinutes > 0 ? day.estMinutes * 60 : null),
            startedAt: Value(now),
            finishedAt: Value(now),
          ));
      await db.batch((b) {
        for (final r in rows) {
          b.insert(db.workoutSets, r);
        }
      });

      // PR 判定：对每个已完成动作，与历史基线（不含本场）对比
      final domainSessions = _toDomainSessions(
        db,
        await (db.select(db.trainingSessions)
              ..where((t) => t.status.equals('completed')))
            .get(),
      );
      var prHit = false;
      for (final it in _items.where((x) => x.done)) {
        final w = double.tryParse(it.weightCtrl.text) ?? 0;
        final r = int.tryParse(it.repsCtrl.text) ?? 0;
        if (w <= 0 || r <= 0) continue;
        final hist = prHistoryFor(
          domainSessions,
          it.entry.exerciseId,
          excludeSessionId: sid,
        );
        final hits = checkPR(
          WorkoutSet(
              exerciseId: it.entry.exerciseId, weightKg: w, reps: r, isBodyweight: false),
          hist,
        );
        if (hits.isNotEmpty) prHit = true;
      }

      _saved = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '训练已保存 · 容量 ${totalVol.toStringAsFixed(1)} kg · '
            '${prHit ? '破纪录 · ' : ''}已完成 $_completedCount/${_items.length} 个动作',
          ),
        ),
      );
      ref.invalidate(allSessionsProvider);
      ref.invalidate(todayTrainingSessionStreamProvider);
      context.go('/training');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<TrainingSession> _toDomainSessions(
    AppDatabase db,
    List<TrainingSessionData> rows,
  ) {
    // 这里只需要 date/id 供 prHistoryFor 聚合，sets 现查
    return <TrainingSession>[
      for (final s in rows)
        TrainingSession(
          id: s.id,
          date: s.date,
          startedAt: s.startedAt?.toIso8601String(),
          status: s.status,
          totalVolumeKg: s.totalVolumeKg,
          durationSec: s.durationSec,
          sets: const <WorkoutSet>[],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return WillPopScope(
      onWillPop: () async {
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go('/training')),
          title: Text(
            '已完成 $_completedCount/${_items.length} 个动作 · '
            '${_volume.toStringAsFixed(1)} kg',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        body: !_inited
            ? const Center(
                child: CircularProgressIndicator(color: AppPalette.primary))
            : day == null
                ? const Center(child: Text('找不到该训练日，请先生成计划'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      MgCard(
                        title: '${day.code} · ${day.name}',
                        sub: day.estMinutes > 0
                            ? '约 ${day.estMinutes} 分钟 · 每个动作一组重量+次数即可'
                            : '每个动作一组重量+次数即可',
                        child: Column(
                          children: [
                            for (final it in _items)
                              _exerciseRow(context, it),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : _finish,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(_saving ? '保存中…' : '结束训练并保存'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
      ),
    );
  }

  Widget _exerciseRow(BuildContext context, _RunItem it) {
    final en = it.entry;
    final lastHint = it.ref != null
        ? '上次：${_fmt(it.ref!.weightKg)} kg × ${it.ref!.reps.toInt()} 次'
        : '首次训练';
    final done = it.done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${it.ex?.name ?? en.exerciseId}'
                  '${it.ex?.isCompound == true ? ' · 复合' : ''}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                it.badge,
                style: TextStyle(fontSize: 12, color: it.badgeColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${en.targetSets} 组 · 目标 ${en.repLow}–${en.repHigh} 次 · $lastHint',
            style: const TextStyle(fontSize: 12, color: AppPalette.textSub),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _numField(
                controller: it.weightCtrl,
                enabled: !done,
                suffix: 'kg',
                decimal: true,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('×', style: TextStyle(color: AppPalette.textSub)),
              ),
              _numField(
                controller: it.repsCtrl,
                enabled: !done,
                suffix: '次',
                decimal: false,
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: done ? null : () => _complete(it),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  backgroundColor:
                      done ? AppPalette.surfaceMuted : AppPalette.primary,
                ),
                child: Text(done ? '✓ 已完成' : '完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField({
    required TextEditingController controller,
    required bool enabled,
    required String suffix,
    required bool decimal,
  }) {
    return SizedBox(
      width: 96,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType:
            TextInputType.numberWithOptions(decimal: decimal, signed: false),
        inputFormatters: [
          if (decimal)
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}'))
          else
            FilteringTextInputFormatter.digitsOnly,
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          suffixText: suffix,
          suffixStyle: const TextStyle(fontSize: 11, color: AppPalette.textSub),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

String _fmt(num v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
