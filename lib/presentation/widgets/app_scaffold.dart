/// 应用底部 Tab 容器（ARCHITECTURE F03）
/// 6 个 tab：今日 / 训练 / 睡眠 / 饮食 / 数据 / 我的
/// 选中时高亮（primary 橙）；未选中灰色。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({required this.navigationShell, super.key});

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        backgroundColor: Theme.of(context).colorScheme.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today, color: Color(0xFFFF7A30)),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center, color: Color(0xFFFF7A30)),
            label: '训练',
          ),
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime, color: Color(0xFF4C6EF5)),
            label: '睡眠',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant, color: Color(0xFFFF7A30)),
            label: '饮食',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: Color(0xFFFF7A30)),
            label: '数据',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFFFF7A30)),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
