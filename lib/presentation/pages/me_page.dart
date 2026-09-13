/// 我的页 P-10（ARCHITECTURE F04）
///   - 资料卡：性别 / 年龄 / 身高 / 当前→目标体重 / 场景 / 训练频率
///   - 目标卡：每日热量 + P/C/F
///   - 「重新生成训练计划」按钮：调 regenerateTrainingPlan
///   - 「清空所有数据」按钮：wipeAllUserData + 跳 /onboarding
///   - 底部版本号 + 技术说明
///
/// 本期不实现：体重历史 / 营养微调 / 设置开关 / JSON 备份 / 通知开关。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/plan_regen.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../data/database.dart';
import '../../data/seed_loader.dart';
import '../../domain/calc/calc.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';

class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  bool _regenerating = false;
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileStreamProvider);
    final goalAsync = ref.watch(goalStreamProvider);
    final goal = ref.watch(resolvedGoalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppPalette.primary),
        ),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '暂无资料，请完成引导',
                  style: TextStyle(color: AppPalette.textSub),
                ),
              ),
            );
          }
          final g = goalAsync.value;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _profileCard(profile, g),
              const SizedBox(height: 12),
              _goalCard(goal, g),
              const SizedBox(height: 12),
              _actionsCard(context),
              const SizedBox(height: 12),
              const _aboutCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _profileCard(ProfileData p, GoalData? g) {
    final equipLabels = AppDatabase.decodeStrList(p.equipmentJson)
        .map((e) => AppConfig.labels[e] ?? e)
        .join('、');
    return MgCard(
      title: '我的资料',
      child: Column(
        children: [
          _kv('性别 / 年龄',
              '${AppConfig.labels[p.sex] ?? p.sex} · ${p.age} 岁'),
          _kv('身高', '${p.heightCm.toStringAsFixed(0)} cm'),
          _kv(
            '当前 → 目标体重',
            '${(g?.currentWeightKg ?? 0).toStringAsFixed(1)} → '
            '${(g?.targetWeightKg ?? 0).toStringAsFixed(1)} kg',
          ),
          _kv('训练场景', AppConfig.labels[p.scene] ?? p.scene),
          _kv('器械', equipLabels.isEmpty ? '无' : equipLabels),
          _kv('训练频率', '${p.daysPerWeek} 天 / 周'),
          _kv('活动系数', p.activityFactor.toStringAsFixed(2)),
        ],
      ),
    );
  }

  Widget _goalCard(ResolvedGoalView goal, GoalData? g) {
    final weeks = (g == null)
        ? 0
        : weeksToGoal(
            g.currentWeightKg,
            g.targetWeightKg,
            goal.rate,
          );
    return MgCard(
      title: '增肌目标',
      child: Column(
        children: [
          _kv(
            '当前 → 目标',
            '${(g?.currentWeightKg ?? 0).toStringAsFixed(1)} → '
            '${(g?.targetWeightKg ?? 0).toStringAsFixed(1)} kg',
          ),
          _kv('预计达成', weeks == 0 ? '—' : '$weeks 周'),
          _kv('每日热量', '${goal.kcal.toInt()} kcal'),
          _kv(
            '蛋白 / 碳水 / 脂肪',
            '${goal.protein.toInt()} / ${goal.carb.toInt()} / '
            '${goal.fat.toInt()} g',
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    return MgCard(
      title: '操作',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _regenerating ? null : _regenerate,
              icon: _regenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_regenerating ? '正在生成…' : '重新生成训练计划'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearing ? null : _clearAll,
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text('清空所有数据'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppPalette.danger,
                side: const BorderSide(color: Color(0xFFFEE2E2)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final db = ref.read(databaseReadyProvider).requireValue;
      await regenerateTrainingPlan(db);
      // 触发 plan/appSettings/goal 刷新
      ref.invalidate(planProvider);
      ref.invalidate(appSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('训练计划已重新生成')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await _confirm(
      context,
      title: '清空所有数据？',
      message: '将删除体重、饮食、训练、习惯、计划等所有数据，'
          '并回到首次引导。',
      confirmText: '清空',
    );
    if (!ok) return;
    setState(() => _clearing = true);
    try {
      final db = ref.read(databaseReadyProvider).requireValue;
      await wipeAllUserData(db);
      // 触发依赖刷新
      ref.invalidate(profileStreamProvider);
      ref.invalidate(profileProvider);
      ref.invalidate(goalStreamProvider);
      ref.invalidate(goalProvider);
      ref.invalidate(planProvider);
      ref.invalidate(appSettingsProvider);
      ref.invalidate(todayFoodLogsProvider);
      ref.invalidate(todayHabitsProvider);
      ref.invalidate(todayIntakeProvider);
      ref.invalidate(todayTrainingSessionStreamProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空，即将进入引导')),
      );
      context.go('/onboarding');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
}

// ════════════════════════════════════════════════════════════════════
// 关于卡
// ════════════════════════════════════════════════════════════════════

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '增肌管理 v0.1.0',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppPalette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '基于 Flutter 3.22 + Material 3',
            style: const TextStyle(
              fontSize: 12,
              color: AppPalette.textSub,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 工具
// ════════════════════════════════════════════════════════════════════

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 13,
              color: AppPalette.textSub,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return res ?? false;
}
