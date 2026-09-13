/// 应用入口（ARCHITECTURE F01 + F03）
/// 启动流程：
///   1) WidgetsFlutterBinding.ensureInitialized
///   2) runApp(ProviderScope(child: MuscleGainApp()))
///   3) MuscleGainApp 内部触发 databaseReadyProvider → seed_loader 自动跑一次。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: MuscleGainApp(),
    ),
  );
}
