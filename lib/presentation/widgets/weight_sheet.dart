/// 体重记录弹层（P-11 对齐 prototype app.js openWeight）
///   - 大输入框 + ±0.1/±0.5 步进
///   - 今天 / 补录昨天 切换
///   - 保存：写 WeightPoints + onWeightLogged 联动 goal（阈值 0.2kg）
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/history_providers.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../data/database.dart';
import '../../domain/calc/calc.dart';
import '../theme/app_theme.dart';

Future<void> showWeightSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _WeightSheet(),
  );
}

class _WeightSheet extends ConsumerStatefulWidget {
  const _WeightSheet();

  @override
  ConsumerState<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<_WeightSheet> {
  late String _targetDate; // yyyy-MM-dd
  late TextEditingController _ctrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _targetDate = 'today';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final db = ref.read(databaseReadyProvider).requireValue;
    final today = ref.read(todayStringProvider);
    final row = await (db.select(db.weightPoints)
          ..where((t) => t.date.equals(today)))
        .getSingleOrNull();
    final goal = await ref.read(goalStreamProvider.future);
    final cur = row?.kg ?? goal?.currentWeightKg ?? 62.0;
    if (!mounted) return;
    setState(() {
      _targetDate = today;
      _ctrl = TextEditingController(text: cur.toStringAsFixed(1));
      _loaded = true;
    });
  }

  @override
  void dispose() {
    if (_loaded) _ctrl.dispose();
    super.dispose();
  }

  Future<void> _switchDate() async {
    final today = ref.read(todayStringProvider);
    final db = ref.read(databaseReadyProvider).requireValue;
    final next =
        _targetDate == today ? D.addDays(today, -1) : today;
    final row = await (db.select(db.weightPoints)
          ..where((t) => t.date.equals(next)))
        .getSingleOrNull();
    final goal = await ref.read(goalStreamProvider.future);
    final cur = row?.kg ?? goal?.currentWeightKg ?? 62.0;
    if (!mounted) return;
    setState(() {
      _targetDate = next;
      _ctrl.text = cur.toStringAsFixed(1);
    });
  }

  void _step(double delta) {
    final n = double.tryParse(_ctrl.text) ?? 0;
    _ctrl.text = R.r1(n + delta).toStringAsFixed(1);
    setState(() {});
  }

  Future<void> _save() async {
    final n = double.tryParse(_ctrl.text);
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效体重')),
      );
      return;
    }
    final db = ref.read(databaseReadyProvider).requireValue;
    final today = ref.read(todayStringProvider);
    final isToday = _targetDate == today;

    // 1) 写体重点（同日覆盖）
    await db.into(db.weightPoints).insertOnConflictUpdate(
          WeightPointsCompanion.insert(date: _targetDate, kg: n),
        );

    // 2) 只有当天记录才联动 goal（补录不联动，与原型一致）
    String extra = '';
    if (isToday) {
      final profile = await ref.read(profileStreamProvider.future);
      final goal = await ref.read(goalStreamProvider.future);
      if (profile != null && goal != null) {
        final profileMap = <String, dynamic>{
          'sex': profile.sex,
          'age': profile.age,
          'heightCm': profile.heightCm,
          'scene': profile.scene,
          'equipment': AppDatabase.decodeStrList(profile.equipmentJson),
          'daysPerWeek': profile.daysPerWeek,
          'activityFactor': profile.activityFactor,
          'activityFactorLocked': profile.activityFactorLocked,
          'onboardingDone': profile.onboardingDone,
        };
        final goalMap = <String, dynamic>{
          'kcalMode': goal.kcalMode,
          'kcalManual': goal.kcalManual,
          'kcalAutoOffset': goal.kcalAutoOffset,
          'proteinMode': goal.proteinMode,
          'proteinManual': goal.proteinManual,
          'carbMode': goal.carbMode,
          'carbManual': goal.carbManual,
          'fatMode': goal.fatMode,
          'fatManual': goal.fatManual,
          'rateMode': goal.rateMode,
          'rateManual': goal.rateManual,
          'surplusKcal': goal.surplusKcal,
          'lastWeightUsed': goal.lastWeightUsed,
          'lastAdjustWeek': goal.lastAdjustWeek,
        };
        final r = onWeightLogged(n, profileMap, goalMap);
        await (db.update(db.goals)..where((t) => t.id.equals(goal.id))).write(
          GoalsCompanion(
            currentWeightKg: Value(n),
            lastWeightUsed: Value(n),
            kcalAutoOffset: Value(
                (r.nextGoal['kcalAutoOffset'] as num?)?.toDouble() ??
                    goal.kcalAutoOffset),
            kcalMode: Value(r.nextGoal['kcalMode'] as String? ?? goal.kcalMode),
            kcalManual: Value((r.nextGoal['kcalManual'] as num?)?.toDouble()),
            lastAdjustWeek:
                Value(r.nextGoal['lastAdjustWeek'] as String? ?? goal.lastAdjustWeek),
            lastAdjustedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
        if (r.changed) extra = ' · ${r.message}';
      }
    }

    ref.invalidate(weightPointsStreamProvider);
    ref.invalidate(goalStreamProvider);
    ref.invalidate(resolvedGoalProvider);
    ref.invalidate(todayWeightProvider);
    ref.invalidate(weightDeltaProvider);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记录 ${n.toStringAsFixed(1)} kg$extra')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayStringProvider);
    final isToday = _targetDate == today;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            isToday ? '记录今日体重' : '补录昨日体重',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _loaded ? _ctrl : null,
            enabled: _loaded,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 40, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '0.0',
            ),
          ),
          const Center(
            child: Text('单位 kg · 可直接输入，或用下方微调',
                style: TextStyle(fontSize: 12, color: AppPalette.textSub)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepBtn('-0.5', () => _step(-0.5)),
              const SizedBox(width: 8),
              _stepBtn('-0.1', () => _step(-0.1)),
              const SizedBox(width: 8),
              _stepBtn('+0.1', () => _step(0.1)),
              const SizedBox(width: 8),
              _stepBtn('+0.5', () => _step(0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _switchDate,
              child: Text(isToday ? '改为补录昨天' : '改回今天'),
            ),
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _loaded ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 40),
        padding: EdgeInsets.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
