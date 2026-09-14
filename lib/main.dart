/// 应用入口（ARCHITECTURE F01 + F03 + F05）
/// 启动流程：
///   1) WidgetsFlutterBinding.ensureInitialized
///   2) 初始化本地通知服务
///   3) runApp(ProviderScope(child: MuscleGainApp()))
///   4) MuscleGainApp 内部触发 databaseReadyProvider → seed → 按设置重排提醒。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'application/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(
    const ProviderScope(
      child: MuscleGainApp(),
    ),
  );
}
