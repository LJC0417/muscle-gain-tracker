/// 路由（ARCHITECTURE F03 + F05 补全）
/// go_router + StatefulShellRoute.indexedStack 包 5 个 Tab：
///   /today  /training  /diet  /stats  /me
/// 独立路由：/workout-run/:code（训练执行）、/onboarding。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/diet_page.dart';
import '../pages/me_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/stats_page.dart';
import '../pages/today_page.dart';
import '../pages/training_page.dart';
import '../pages/workout_run_page.dart';
import '../widgets/app_scaffold.dart';

GoRouter buildAppRouter({required bool startWithOnboarding}) {
  return GoRouter(
    initialLocation: startWithOnboarding ? '/onboarding' : '/today',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/workout-run/:code',
        parentNavigatorKey: rootNavigatorKey,
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
