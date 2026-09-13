/// 引导页（ARCHITECTURE F04）
/// 最小可用版本：性别 / 年龄 / 身高 / 当前体重 / 目标体重 / 场景（居家/健身房）。
/// 完成 → 写 Profiles + Goals + 生成计划 + 写 AppSettings.onboardingDone='1' → 跳 /today。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../../domain/calc/calc.dart';
import '../../domain/plan/plan.dart';
import '../theme/app_theme.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  String sex = 'male';
  int age = 25;
  double heightCm = 175;
  double currentKg = 62.0;
  double targetKg = 67.0;
  String scene = 'home';
  List<String> equipment = const ['dumbbell', 'bench'];
  int daysPerWeek = 4;
  bool _saving = false;

  Future<void> _finish() async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final factor = recommendFactor(daysPerWeek);

    // 写 Profiles
    final profileId = await db.into(db.profiles).insert(
          ProfilesCompanion.insert(
            sex: sex,
            age: age,
            heightCm: heightCm,
            scene: scene,
            equipmentJson: Value(AppDatabase.encodeStrList(equipment)),
            daysPerWeek: Value(daysPerWeek),
            activityFactor: Value(factor),
            activityFactorLocked: const Value(false),
            onboardingDone: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    // 写 Goals
    await db.into(db.goals).insert(
          GoalsCompanion.insert(
            startWeightKg: currentKg,
            currentWeightKg: currentKg,
            targetWeightKg: targetKg,
            kcalMode: const Value('auto'),
            kcalManual: const Value(null),
            kcalAutoOffset: const Value(0),
            proteinMode: const Value('auto'),
            proteinManual: const Value(null),
            carbMode: const Value('auto'),
            carbManual: const Value(null),
            fatMode: const Value('auto'),
            fatManual: const Value(null),
            rateMode: const Value('auto'),
            rateManual: const Value(null),
            surplusKcal: const Value(AppConfig.defaultSurplus),
            lastWeightUsed: Value(currentKg),
            updatedAt: Value(DateTime.now()),
          ),
        );

    // 生成 plan
    final allExercises = await db.select(db.exercises).get();
    final exList = allExercises.map((e) {
      return Exercise(
        id: e.id,
        name: e.name,
        muscleGroup: e.muscleGroup,
        subGroup: e.subGroup,
        isCompound: e.isCompound,
        requiredEquipment: AppDatabase.decodeStrList(e.requiredEquipmentJson),
        scenes: AppDatabase.decodeStrList(e.scenesJson),
        defaultSets: e.defaultSets,
        repLow: e.repLow,
        repHigh: e.repHigh,
        isBodyweight: e.isBodyweight,
        orderWeight: e.orderWeight,
      );
    }).toList();

    final tpl4 = _templates4();
    final week4 = const WeekPattern('A', 'B', '', 'C', '', 'D', '');
    final tpl5 = _templates5();
    final week5 =
        const WeekPattern('A', 'B', '', 'C', 'D', 'E', '');
    final input = GeneratePlanInput(
      scene: scene,
      daysPerWeek: daysPerWeek,
      equipment: equipment,
      allExercises: exList,
      templates: daysPerWeek >= 5 ? tpl5 : tpl4,
      fallbackMap: _fallbackMap(),
      weekPatternDefault: {4: week4, 5: week5},
      templatePoolLe5: const ['A', 'B', 'C', 'D', 'E'],
      templatePoolAll: const ['A', 'B', 'C', 'D', 'E', 'F'],
    );
    final plan = generatePlan(input);

    final planJson = {
      'days': plan.days.map((d) => {
            'code': d.code,
            'name': d.name,
            'estMinutes': d.estMinutes,
            'entries': d.entries
                .map((e) => {
                      'sortOrder': e.sortOrder,
                      'exerciseId': e.exerciseId,
                      'targetSets': e.targetSets,
                      'repLow': e.repLow,
                      'repHigh': e.repHigh,
                    })
                .toList(),
          }).toList(),
      'pattern': {
        for (var i = 1; i <= 7; i++) i: plan.pattern.at(i),
      },
    };

    // 写 AppSettings.onboardingDone + plan
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'onboardingDone',
            value: '1',
          ),
        );
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'plan',
            value: jsonEncode(planJson),
          ),
        );

    if (mounted) {
      // 触发依赖刷新
      ref.invalidate(profileStreamProvider);
      ref.invalidate(goalStreamProvider);
      ref.invalidate(appSettingsProvider);
      ref.invalidate(profileProvider);
      ref.invalidate(goalProvider);
      context.go('/today');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Container(
                height: 80,
                width: 80,
                margin: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF4EC), AppPalette.primaryWeak],
                  ),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  size: 40,
                  color: AppPalette.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '增肌管理',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '记录体重与饮食，按你的身高体重定制增肌方案。\n只要 1 分钟，马上开始。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppPalette.textSub,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),

              // 性别
              const _Label('性别'),
              _SegPair(
                options: const [
                  ('male', '男'),
                  ('female', '女'),
                ],
                value: sex,
                onChanged: (v) => setState(() => sex = v),
              ),
              const SizedBox(height: 16),

              // 年龄
              const _Label('年龄（岁）'),
              _NumberInput(
                value: age.toDouble(),
                suffix: '岁',
                onChanged: (v) => age = v.toInt().clamp(10, 90),
              ),
              const SizedBox(height: 16),

              // 身高
              const _Label('身高（cm）'),
              _NumberInput(
                value: heightCm,
                suffix: 'cm',
                onChanged: (v) => heightCm = v.clamp(120, 230),
              ),
              const SizedBox(height: 16),

              // 当前体重
              const _Label('当前体重（kg）'),
              _NumberInput(
                value: currentKg,
                suffix: 'kg',
                onChanged: (v) => currentKg = v.clamp(30, 200),
              ),
              const SizedBox(height: 16),

              // 目标体重
              const _Label('目标体重（kg）'),
              _NumberInput(
                value: targetKg,
                suffix: 'kg',
                onChanged: (v) => targetKg = v.clamp(30, 200),
              ),
              const SizedBox(height: 16),

              // 场景
              const _Label('训练场景'),
              _SegPair(
                options: const [
                  ('home', '居家哑铃'),
                  ('gym', '健身房'),
                ],
                value: scene,
                onChanged: (v) {
                  setState(() {
                    scene = v;
                    if (v == 'home') {
                      equipment = const ['dumbbell', 'bench'];
                    } else {
                      equipment = const ['barbell', 'rack', 'cable', 'machine'];
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              // 每周训练频率
              const _Label('每周训练频率'),
              Row(
                children: [
                  for (final d in const [3, 4, 5, 6])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: d == 6 ? 0 : 8),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: daysPerWeek == d
                                ? AppPalette.primary
                                : AppPalette.surface,
                            foregroundColor: daysPerWeek == d
                                ? Colors.white
                                : AppPalette.text,
                            side: BorderSide(
                              color: daysPerWeek == d
                                  ? AppPalette.primary
                                  : AppPalette.border,
                            ),
                          ),
                          onPressed: () => setState(
                              () => daysPerWeek = d),
                          child: Text('$d 天'),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),

              FilledButton(
                onPressed: _saving ? null : _finish,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('开始使用'),
              ),
              const SizedBox(height: 12),
              const Text(
                '以上为基础设置，使用过程中可随时在「我的」中微调。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.textWeak,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppPalette.textSub,
        ),
      ),
    );
  }
}

class _SegPair extends StatelessWidget {
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;
  const _SegPair({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (k, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(k),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: value == k ? AppPalette.surface : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: value == k
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          value == k ? FontWeight.w600 : FontWeight.w500,
                      color: value == k
                          ? AppPalette.text
                          : AppPalette.textSub,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberInput extends StatefulWidget {
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;
  const _NumberInput({
    required this.value,
    required this.suffix,
    required this.onChanged,
  });
  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当外部 value 与本地 _ctrl 文本不一致时才更新（避免光标跳）
    final want = _format(widget.value);
    if (_ctrl.text != want && !_ctrl.text.startsWith(_shortFormat(widget.value))) {
      _ctrl.text = want;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _format(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String _shortFormat(double v) => v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppPalette.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: '0',
              suffixText: widget.suffix,
            ),
            onChanged: (s) {
              final v = double.tryParse(s);
              if (v != null) widget.onChanged(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => widget.onChanged(widget.value - 1),
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          onPressed: () => widget.onChanged(widget.value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

// ════════ 模板 / 排期（与 prototype 一致，此处仅 4/5 天两个） ════════

List<DayTemplate> _templates4() => [
      DayTemplate(code: 'A', name: '胸 + 三头', slots: [
        DaySlot(mg: 'chest', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: 'triceps', n: 2),
      ]),
      DayTemplate(code: 'B', name: '背 + 二头', slots: [
        DaySlot(mg: 'back', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: 'biceps', n: 2),
      ]),
      DayTemplate(code: 'C', name: '腿 + 核心', slots: [
        DaySlot(mg: 'legs', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 2),
      ]),
      DayTemplate(code: 'D', name: '肩 + 手臂', slots: [
        DaySlot(mg: 'shoulders', sub: null, n: 3),
        DaySlot(mg: 'arms', sub: null, n: 2),
      ]),
    ];

List<DayTemplate> _templates5() => [
      DayTemplate(code: 'A', name: '胸', slots: [
        DaySlot(mg: 'chest', sub: null, n: 5),
      ]),
      DayTemplate(code: 'B', name: '背', slots: [
        DaySlot(mg: 'back', sub: null, n: 5),
      ]),
      DayTemplate(code: 'C', name: '腿', slots: [
        DaySlot(mg: 'legs', sub: null, n: 5),
      ]),
      DayTemplate(code: 'D', name: '肩 + 核心', slots: [
        DaySlot(mg: 'shoulders', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 1),
      ]),
      DayTemplate(code: 'E', name: '手臂 + 核心', slots: [
        DaySlot(mg: 'arms', sub: null, n: 4),
        DaySlot(mg: 'core', sub: null, n: 2),
      ]),
    ];

Map<String, List<String>> _fallbackMap() => {
      'chest': ['shoulders'],
      'back': ['arms'],
      'legs': ['core'],
      'shoulders': ['arms'],
      'arms': ['back'],
      'core': ['legs'],
    };
