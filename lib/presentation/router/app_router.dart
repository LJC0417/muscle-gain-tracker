/// 路由（ARCHITECTURE F03）
/// go_router + StatefulShellRoute.indexedStack 包 4 个 Tab：
///   /today     /training     /diet     /me
/// /onboarding 不在 Tab 内，由 app.dart 启动时决定跳哪。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/diet_page.dart';
import '../pages/me_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/today_page.dart';
import '../pages/training_page.dart';
import '../widgets/app_scaffold.dart';

GoRouter buildAppRouter({required bool startWithOnboarding}) {
  return GoRouter(
    initialLocation: startWithOnboarding ? '/onboarding' : '/today',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
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
