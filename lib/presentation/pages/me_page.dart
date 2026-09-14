/// 我的页 P-10（ARCHITECTURE F04 + F05 补全）
///   - 资料卡 / 目标卡
///   - 操作卡：重新生成训练计划 / 清空所有数据
///   - 设置卡：体重单位（kg/斤）、4 类通知开关与时间
///   - 数据管理卡：JSON 备份导出 / 导入 / 重新引导 / 清空
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup_service.dart';
import '../../application/foods_provider.dart';
import '../../application/history_providers.dart';
import '../../application/notification_service.dart';
import '../../application/plan_regen.dart';
import '../../application/providers/app_providers.dart';
import '../../application/providers/database_provider.dart';
import '../../core/constants/app_config.dart';
import '../../data/database.dart';
import '../../data/seed_loader.dart';
import '../../domain/calc/calc.dart';
import '../theme/app_theme.dart';
import '../widgets/mg_widgets.dart';
import '../widgets/plan_customize_sheet.dart' show customExercisesProvider;

class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  bool _regenerating = false;
  bool _clearing = false;
  bool _sendingTest = false;

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
              _settingsCard(context),
              const SizedBox(height: 12),
              _dataCard(context),
              const SizedBox(height: 12),
              const _AboutCard(),
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
      await NotificationService.instance.cancelAll();
      _invalidateAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空，即将进入引导')),
      );
      // 不在这里 context.go('/onboarding')：写入 onboardingDone=0 后
      // 启动闸门会重定向过去，手动跳转会被尚未来得及更新的闸门弹回首页。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _invalidateAll() {
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
    ref.invalidate(weightPointsStreamProvider);
    ref.invalidate(allSessionsProvider);
    ref.invalidate(todayWeightProvider);
    ref.invalidate(weightDeltaProvider);
    ref.invalidate(foodsProvider);
    ref.invalidate(customExercisesProvider);
  }

  // ════════ 设置卡 ════════

  Future<void> _setSetting(String key, String value) async {
    final db = ref.read(databaseReadyProvider).requireValue;
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
    ref.invalidate(appSettingsProvider);
    // 通知相关设置变化 → 重排提醒
    if (key.startsWith('notify')) {
      final settings = await ref.read(appSettingsProvider.future);
      await NotificationService.instance.reschedule(settings);
    }
  }

  Widget _settingsCard(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ??
        const <String, String>{};
    final unit = settings['weightUnit'] ?? AppConfig.weightUnit;
    return MgCard(
      title: '设置',
      child: Column(
        children: [
          _switchRow('体重单位（kg / 斤）', unit == 'jin', (on) async {
            await _setSetting('weightUnit', on ? 'jin' : 'kg');
          }),
          _switchRow('体重提醒', settings['notifyWeightEnabled'] == '1',
              (on) async {
            await _setSetting('notifyWeightEnabled', on ? '1' : '0');
          }),
          _timeRow('体重提醒时间', settings['notifyWeightTime'],
              (t) => _setSetting('notifyWeightTime', t)),
          _switchRow('训练提醒', settings['notifyWorkoutEnabled'] == '1',
              (on) async {
            await _setSetting('notifyWorkoutEnabled', on ? '1' : '0');
          }),
          _timeRow('训练提醒时间', settings['notifyWorkoutTime'],
              (t) => _setSetting('notifyWorkoutTime', t)),
          _switchRow(
              '喝水提醒（10:00–21:00 每 2 小时）',
              settings['notifyWaterEnabled'] == '1', (on) async {
            await _setSetting('notifyWaterEnabled', on ? '1' : '0');
          }),
          _switchRow('每周复盘提醒（周日 20:00）',
              settings['notifyReviewEnabled'] == '1', (on) async {
            await _setSetting('notifyReviewEnabled', on ? '1' : '0');
          }),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _sendingTest
                ? null
                : () async {
                    setState(() => _sendingTest = true);
                    try {
                      final msg =
                          await NotificationService.instance.sendTestNotification();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
                      );
                    } finally {
                      if (mounted) setState(() => _sendingTest = false);
                    }
                  },
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('发送测试通知（验证提醒链路 / 手表同步）'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _timeRow(
      String label, String? current, ValueChanged<String> onPick) {
    final display = (current == null || current.isEmpty)
        ? AppConfig.notifyWeightTime
        : current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text('$label（$display）',
                style: const TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () async {
              final parts = display.split(':');
              final initial = TimeOfDay(
                hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8,
                minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
              );
              final t = await showTimePicker(
                context: context,
                initialTime: initial,
              );
              if (t != null) {
                onPick('${t.hour.toString().padLeft(2, '0')}:'
                    '${t.minute.toString().padLeft(2, '0')}');
              }
            },
            child: const Text('修改'),
          ),
        ],
      ),
    );
  }

  // ════════ 数据管理卡 ════════

  Widget _dataCard(BuildContext context) {
    return MgCard(
      title: '数据管理',
      child: Column(
        children: [
          _dataRow(
            '导出备份',
            '生成 JSON 并分享到微信/网盘等',
            '导出',
            _export,
          ),
          _dataRow(
            '导入备份',
            '从本地 JSON 文件恢复',
            '导入',
            _import,
          ),
          _dataRow(
            '重新引导',
            '重走一遍设置流程并覆盖当前资料',
            '重新',
            _reOnboard,
          ),
        ],
      ),
    );
  }

  Widget _dataRow(
      String label, String sub, String btnText, VoidCallback onTap) {
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
                Text(sub,
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSub)),
              ],
            ),
          ),
          OutlinedButton(onPressed: onTap, child: Text(btnText)),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final db = ref.read(databaseReadyProvider).requireValue;
    final ok = await exportBackup(db);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已生成备份，请选择分享方式' : '导出失败')),
    );
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = res?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final db = ref.read(databaseReadyProvider).requireValue;
      final msg = await importBackup(db, content);
      _invalidateAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入备份 · $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _reOnboard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新引导？'),
        content: const Text('将重走设置流程并覆盖当前资料。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseReadyProvider).requireValue;
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: 'onboardingDone', value: '0'),
        );
    ref.invalidate(appSettingsProvider);
    // 由启动闸门重定向到 /onboarding
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
