/// 应用外壳（ARCHITECTURE F03）
/// MaterialApp.router + go_router + onboarding gate + 主题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return settings.when(
      data: (s) {
        final onboarded = s['onboardingDone'] == '1';
        final router = buildAppRouter(startWithOnboarding: !onboarded);
        return MaterialApp.router(
          title: '增肌管理',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          routerConfig: router,
        );
      },
      loading: () => const _SplashScaffold(),
      error: (e, _) => const _SplashScaffold(),
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
