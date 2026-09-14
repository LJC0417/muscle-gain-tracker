/// 自定义训练日（Bug #7 对齐 prototype workout.js）：
///   - 改名 / 每个动作 ± 组数（1–8）/ 删除动作
///   - 添加动作（按场景+器械过滤内置库 + 自定义动作，支持搜索）
///   - 新建自定义动作（名称/部位/组数/次数范围，存 AppSettings['customExercises']）
///   - 重置为默认 / 保存（写入 plan.userOverrides）
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../../domain/plan/plan.dart';
import '../theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════
// 自定义动作（AppSettings JSON）
// ════════════════════════════════════════════════════════════════════

class CustomExercise {
  final String id;
  final String name;
  final String muscleGroup;
  final int defaultSets;
  final int repLow;
  final int repHigh;
  const CustomExercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.defaultSets,
    required this.repLow,
    required this.repHigh,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'muscleGroup': muscleGroup,
        'defaultSets': defaultSets,
        'repLow': repLow,
        'repHigh': repHigh,
      };

  static CustomExercise fromJson(Map<String, dynamic> m) => CustomExercise(
        id: m['id'] as String,
        name: m['name'] as String,
        muscleGroup: m['muscleGroup'] as String,
        defaultSets: (m['defaultSets'] as num?)?.toInt() ?? 3,
        repLow: (m['repLow'] as num?)?.toInt() ?? 8,
        repHigh: (m['repHigh'] as num?)?.toInt() ?? 12,
      );
}

final customExercisesProvider = FutureProvider<List<CustomExercise>>((ref) async {
  final db = await ref.watch(databaseReadyProvider.future);
  final rows = await (db.select(db.appSettings)
        ..where((t) => t.key.equals('customExercises')))
      .getSingleOrNull();
  final raw = rows?.value;
  if (raw == null || raw.isEmpty) return const <CustomExercise>[];
  try {
    final l = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in l) CustomExercise.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  } catch (_) {
    return const <CustomExercise>[];
  }
});

Future<void> saveCustomExercises(
  WidgetRef ref,
  AppDatabase db,
  List<CustomExercise> list,
) async {
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'customExercises',
          value: jsonEncode([for (final e in list) e.toJson()]),
        ),
      );
  ref.invalidate(customExercisesProvider);
}

// ════════════════════════════════════════════════════════════════════
// 弹层主入口
// ════════════════════════════════════════════════════════════════════

class PlanCustomizeSheet extends ConsumerStatefulWidget {
  final String planCode;
  const PlanCustomizeSheet({super.key, required this.planCode});

  @override
  ConsumerState<PlanCustomizeSheet> createState() => _PlanCustomizeSheetState();
}

class _EditableEntry {
  String exerciseId;
  int targetSets;
  final num repLow;
  final num repHigh;
  _EditableEntry({
    required this.exerciseId,
    required this.targetSets,
    required this.repLow,
    required this.repHigh,
  });
}

class _PlanCustomizeSheetState extends ConsumerState<PlanCustomizeSheet> {
  final _nameCtrl = TextEditingController();
  final _entries = <_EditableEntry>[];
  bool _loaded = false;
  bool _hadOverride = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final plan = ref.read(planProvider);
    final def = plan.defaultDay(widget.planCode);
    final ov = plan.overrides[widget.planCode];
    _hadOverride = ov != null;
    _nameCtrl.text = ov?.name ?? def?.name ?? widget.planCode;
    final src = ov?.entries ?? def?.entries ?? const [];
    _entries
      ..clear()
      ..addAll([
        for (final e in src)
          _EditableEntry(
            exerciseId: e.exerciseId,
            targetSets: e.targetSets,
            repLow: e.repLow,
            repHigh: e.repHigh,
          ),
      ]);
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_entries.isEmpty) {
      _toast('至少保留一个动作');
      return;
    }
    final db = ref.read(databaseReadyProvider).requireValue;
    final plan = ref.read(planProvider);
    var order = 0;
    final ov = PlanOverride(
      name: _nameCtrl.text.trim().isEmpty
          ? widget.planCode
          : _nameCtrl.text.trim(),
      entries: [
        for (final e in _entries)
          PlanEntry(
            sortOrder: order++,
            exerciseId: e.exerciseId,
            targetSets: e.targetSets,
            repLow: e.repLow,
            repHigh: e.repHigh,
          ),
      ],
    );
    final newOverrides = Map<String, PlanOverride>.from(plan.overrides);
    newOverrides[widget.planCode] = ov;
    final updated = StoredPlan(
      days: plan.days,
      pattern: plan.pattern,
      overrides: newOverrides,
    );
    await saveStoredPlan(db, updated);
    ref.invalidate(planProvider);
    ref.invalidate(appSettingsProvider);
    if (!mounted) return;
    Navigator.pop(context);
    _toast('已保存自定义训练日');
  }

  Future<void> _reset() async {
    if (!_hadOverride) {
      _toast('当前已是默认内容');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置为默认内容？'),
        content: const Text('自定义内容会丢失。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重置')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseReadyProvider).requireValue;
    final plan = ref.read(planProvider);
    final newOverrides = Map<String, PlanOverride>.from(plan.overrides)
      ..remove(widget.planCode);
    await saveStoredPlan(
      db,
      StoredPlan(days: plan.days, pattern: plan.pattern, overrides: newOverrides),
    );
    ref.invalidate(planProvider);
    ref.invalidate(appSettingsProvider);
    if (!mounted) return;
    Navigator.pop(context);
    _toast('已重置为默认');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(exercisesProvider);
    final customsAsync = ref.watch(customExercisesProvider);
    final nameOf = <String, String>{
      for (final e in (exercisesAsync.value ?? const <ExerciseData>[]))
        e.id: e.name,
      for (final c in (customsAsync.value ?? const <CustomExercise>[]))
        c.id: c.name,
    };
    final compoundOf = <String, bool>{
      for (final e in (exercisesAsync.value ?? const <ExerciseData>[]))
        e.id: e.isCompound,
    };

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text(
                    '自定义 ${widget.planCode} 训练日',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppPalette.primary))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: '训练日名称',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_entries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                '空计划，从下方「添加动作」开始',
                                style: TextStyle(
                                    fontSize: 13, color: AppPalette.textSub),
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < _entries.length; i++)
                            _entryRow(i, nameOf, compoundOf),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _openPicker,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加动作'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _reset,
                                child: const Text('重置为默认'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _save,
                                child: const Text('保存'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryRow(
    int idx,
    Map<String, String> nameOf,
    Map<String, bool> compoundOf,
  ) {
    final e = _entries[idx];
    final label = (nameOf[e.exerciseId] ?? e.exerciseId) +
        (compoundOf[e.exerciseId] == true ? ' · 复合' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('${e.targetSets} 组 × ${e.repLow}–${e.repHigh} 次',
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSub)),
              ],
            ),
          ),
          _roundBtn(Icons.remove, () {
            if (e.targetSets > 1) setState(() => e.targetSets--);
          }),
          _roundBtn(Icons.add, () {
            if (e.targetSets < 8) setState(() => e.targetSets++);
          }),
          _roundBtn(Icons.close, () {
            setState(() => _entries.removeAt(idx));
          }, danger: true),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton.outlined(
          padding: EdgeInsets.zero,
          iconSize: 16,
          onPressed: onTap,
          icon: Icon(icon,
              color: danger ? AppPalette.danger : AppPalette.textSub),
        ),
      ),
    );
  }

  // ── 动作选择器（二级弹层） ──
  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ExercisePickerSheet(profileScene: _sceneOf()),
    );
    if (picked == null) return;
    setState(() {
      _entries.add(_EditableEntry(
        exerciseId: picked['id'] as String,
        targetSets: (picked['sets'] as num).toInt(),
        repLow: picked['repLow'] as num,
        repHigh: picked['repHigh'] as num,
      ));
    });
  }

  String _sceneOf() {
    final p = ref.read(profileStreamProvider).valueOrNull;
    return p?.scene ?? 'home';
  }
}

// ════════════════════════════════════════════════════════════════════
// 动作选择器
// ════════════════════════════════════════════════════════════════════

class _PickerChoice {
  final String id;
  final String name;
  final int sets;
  final int repLow;
  final int repHigh;
  const _PickerChoice(this.id, this.name, this.sets, this.repLow, this.repHigh);
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  final String profileScene;
  const _ExercisePickerSheet({required this.profileScene});

  @override
  ConsumerState<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  String _cat = 'all';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final exAsync = ref.watch(exercisesProvider);
    final customsAsync = ref.watch(customExercisesProvider);
    final profileAsync = ref.watch(profileStreamProvider);
    final equipment = AppDatabase.decodeStrList(
        profileAsync.valueOrNull?.equipmentJson ?? '[]');
    final lenient = equipment.isEmpty ||
        (equipment.length == 1 && equipment.first == 'none');

    final customs = customsAsync.value ?? const <CustomExercise>[];
    final all = <_PickerChoice>[
      // 内置：按场景 + 器械过滤（与 prototype openPickExercise 一致）
      for (final e in (exAsync.value ?? const <ExerciseData>[]))
        if (_sceneOk(e) && _equipOk(e, equipment, lenient))
          _PickerChoice(e.id, e.name, e.defaultSets,
              e.repLow.toInt(), e.repHigh.toInt()),
      for (final c in customs)
        _PickerChoice(c.id, c.name, c.defaultSets, c.repLow, c.repHigh),
    ];

    Iterable<_PickerChoice> pool = all;
    if (_cat == 'custom') {
      pool = pool.where((c) => customs.any((x) => x.id == c.id));
    } else if (_cat != 'all') {
      final idOfMuscle = <String>{};
      for (final e in (exAsync.value ?? const <ExerciseData>[])) {
        if (e.muscleGroup == _cat) idOfMuscle.add(e.id);
      }
      final custMuscle = <String>{
        for (final c in customs)
          if (c.muscleGroup == _cat) c.id,
      };
      pool = pool.where((c) =>
          idOfMuscle.contains(c.id) || custMuscle.contains(c.id));
    }
    if (_q.trim().isNotEmpty) {
      final query = _q.trim();
      pool = pool.where((c) => c.name.contains(query));
    }
    final list = pool.toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Text('选择动作',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: '搜索动作',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              children: [
                _chip('all', '全部'),
                _chip('custom', '自定义'),
                for (final g in AppConfig.muscleGroup) _chip(g, AppConfig.labels[g] ?? g),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('没有动作，换个关键词或分类',
                        style:
                            TextStyle(fontSize: 13, color: AppPalette.textSub)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      for (final c in list.take(80))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(c.name,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${c.sets} 组 × ${c.repLow}–${c.repHigh} 次',
                            style: const TextStyle(
                                fontSize: 12, color: AppPalette.textSub),
                          ),
                          trailing: const Icon(Icons.add,
                              color: AppPalette.primary),
                          onTap: () => Navigator.pop(context, {
                            'id': c.id,
                            'sets': c.sets,
                            'repLow': c.repLow,
                            'repHigh': c.repHigh,
                          }),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _createCustom,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建自定义动作'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  bool _sceneOk(ExerciseData e) {
    final scenes = AppDatabase.decodeStrList(e.scenesJson);
    return scenes.contains(widget.profileScene);
  }

  bool _equipOk(ExerciseData e, List<String> equipment, bool lenient) {
    if (lenient) return true;
    final req = AppDatabase.decodeStrList(e.requiredEquipmentJson);
    return req.every((eq) => eq == 'none' || equipment.contains(eq));
  }

  Widget _chip(String key, String label) {
    final sel = _cat == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        selectedColor: AppPalette.primaryWeak,
        labelStyle: TextStyle(
            color: sel ? AppPalette.primaryDark : AppPalette.textSub,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
        side: BorderSide(color: sel ? AppPalette.primary : AppPalette.border),
        showCheckmark: false,
        onSelected: (_) => setState(() => _cat = key),
      ),
    );
  }

  // ── 新建自定义动作（三级弹层） ──
  Future<void> _createCustom() async {
    final created = await showModalBottomSheet<CustomExercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _CreateCustomExerciseSheet(),
    );
    if (created == null) return;
    final db = ref.read(databaseReadyProvider).requireValue;
    final list = [
      ...(ref.read(customExercisesProvider).valueOrNull ?? const <CustomExercise>[]),
      created,
    ];
    await saveCustomExercises(ref, db, list);
    if (mounted) setState(() {});
  }
}

class _CreateCustomExerciseSheet extends StatefulWidget {
  const _CreateCustomExerciseSheet();

  @override
  State<_CreateCustomExerciseSheet> createState() =>
      _CreateCustomExerciseSheetState();
}

class _CreateCustomExerciseSheetState
    extends State<_CreateCustomExerciseSheet> {
  final _nameCtrl = TextEditingController();
  String _group = 'chest';
  int _sets = 3;
  int _repLow = 8;
  int _repHigh = 12;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const Text('新建自定义动作',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '动作名称',
              hintText: '例：弹力带夹胸',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          const Text('目标肌肉群',
              style: TextStyle(fontSize: 13, color: AppPalette.textSub)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final g in AppConfig.muscleGroup)
                ChoiceChip(
                  label: Text(AppConfig.labels[g] ?? g,
                      style: const TextStyle(fontSize: 12)),
                  selected: _group == g,
                  selectedColor: AppPalette.primaryWeak,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _group = g),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _numField('组数', _sets, (v) => setState(() => _sets = v))),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      _numField('次数·低', _repLow, (v) => setState(() => _repLow = v))),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      _numField('次数·高', _repHigh, (v) => setState(() => _repHigh = v))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入动作名称')));
                      return;
                    }
                    if (_repHigh < _repLow) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('次数·高不能小于次数·低')));
                      return;
                    }
                    Navigator.pop(
                      context,
                      CustomExercise(
                        id:
                            'custom_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        muscleGroup: _group,
                        defaultSets: _sets.clamp(1, 10),
                        repLow: _repLow.clamp(1, 30),
                        repHigh: _repHigh.clamp(1, 30),
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(String label, int value, ValueChanged<int> onChanged) {
    return TextField(
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      controller: TextEditingController(text: '$value'),
      onChanged: (v) => onChanged(int.tryParse(v) ?? value),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}
