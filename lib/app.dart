/// 应用外壳（ARCHITECTURE F03）
/// MaterialApp.router + go_router + onboarding gate + 主题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'application/notification_service.dart';
import 'application/plan_regen.dart';
import 'application/providers/app_providers.dart';
import 'application/providers/database_provider.dart';
import 'presentation/router/app_router.dart';
import 'presentation/theme/app_theme.dart';

class MuscleGainApp extends ConsumerWidget {
  const MuscleGainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readyAsync = ref.watch(databaseReadyProvider);
    return MaterialApp(
      title: '增肌管理',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _Bootstrap(readyAsync: readyAsync),
    );
  }
}

/// 启动闸门：等数据库 ready → 检查 onboard 状态 → 跳路由。
class _Bootstrap extends ConsumerWidget {
  final AsyncValue<dynamic> readyAsync;
  const _Bootstrap({required this.readyAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return readyAsync.when(
      data: (_) => const _Gate(),
      loading: () => const _SplashScaffold(),
      error: (e, st) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                Text('数据库初始化失败：$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(databaseReadyProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Gate extends ConsumerStatefulWidget {
  const _Gate();

  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> {
  /// 引导状态：null = 尚未读到设置，true/false = 已完成/未完成引导。
  /// 作为 GoRouter 的 refreshListenable 驱动 redirect。
  final ValueNotifier<bool?> _onboarded = ValueNotifier<bool?>(null);
  late final GoRouter _router = buildAppRouter(_onboarded);

  bool _rescheduled = false;
  bool _planChecked = false;
  bool _appShown = false;

  @override
  void dispose() {
    _router.dispose();
    _onboarded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final s = settings.valueOrNull;

    if (s != null) {
      _appShown = true;
      final onboarded = s['onboardingDone'] == '1';

      if (_onboarded.value == null) {
        // 首帧：此时 _router 还没被创建，没有任何监听者，直接赋值是安全的
        _onboarded.value = onboarded;
      } else if (_onboarded.value != onboarded) {
        // 后续变化一律放到帧后，避免在 build 期间触发 refreshListenable
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onboarded.value = onboarded;
        });
      }

      if (!_rescheduled) {
        _rescheduled = true;
        // 首次拿到设置后，按开关重排 4 类提醒（fire-and-forget）
        Future<void>(() => NotificationService.instance.reschedule(s));
      }

      // 自愈：老版本因为序列化 bug 没能把训练计划写进库里，
      // 这里发现「已完成引导但没有计划」就自动补一份。
      if (onboarded && !_planChecked) {
        _planChecked = true;
        Future<void>(() async {
          try {
            final db = await ref.read(databaseReadyProvider.future);
            final fixed = await ensureTrainingPlan(db);
            if (fixed && mounted) {
              ref.invalidate(planProvider);
              ref.invalidate(appSettingsProvider);
            }
          } catch (_) {/* 自愈失败不打扰用户 */}
        });
      }
    }

    // 已经展示过主界面后，即使设置短暂回到 loading 也继续展示，
    // 否则会把用户踢回启动页（这正是「填完信息卡在加载」的另一半原因）。
    if (!_appShown) return const _SplashScaffold();

    return MaterialApp.router(
      title: '增肌管理',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}

class _SplashScaffold extends StatelessWidget {
  const _SplashScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFF7A30)),
            SizedBox(height: 16),
            Text('加载中…', style: TextStyle(color: Color(0xFF8A8A8E))),
          ],
        ),
      ),
    );
  }
}
