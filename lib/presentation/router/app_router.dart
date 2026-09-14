/// 路由（ARCHITECTURE F03 + F05 补全）
/// go_router + StatefulShellRoute.indexedStack 包 5 个 Tab：
///   /today  /training  /diet  /stats  /me
/// 独立路由：/workout-run/:code（训练执行）、/onboarding。
///
/// 引导门用 **redirect + refreshListenable** 实现，而不是重建 GoRouter：
///   - 全 App 生命周期只存在一个 GoRouter 实例（避免同名 GlobalKey 冲突）
///   - [onboardingDone] 为 null 表示「设置还没读出来」，此时不做任何重定向
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/diet_page.dart';
import '../pages/me_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/sleep_page.dart';
import '../pages/stats_page.dart';
import '../pages/today_page.dart';
import '../pages/training_page.dart';
import '../pages/workout_run_page.dart';
import '../widgets/app_scaffold.dart';

GoRouter buildAppRouter(ValueListenable<bool?> onboardingDone) {
  // 每次创建都用自己的 key，不复用全局单例，避免热重载/重建时重复挂载。
  final rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'mg-root-nav');
  return GoRouter(
    navigatorKey: rootNavKey,
    initialLocation: '/today',
    refreshListenable: onboardingDone,
    redirect: (context, state) {
      final onboarded = onboardingDone.value;
      if (onboarded == null) return null; // 状态未知，先按原样放行
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded) return atOnboarding ? null : '/onboarding';
      return atOnboarding ? '/today' : null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/workout-run/:code',
        parentNavigatorKey: rootNavKey,
        builder: (context, state) {
          final code = Uri.decodeComponent(
            state.pathParameters['code'] ?? '',
          );
          return WorkoutRunPage(planCode: code);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/training',
                builder: (context, state) => const TrainingPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sleep',
                builder: (context, state) => const SleepPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/diet',
                builder: (context, state) => const DietPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
