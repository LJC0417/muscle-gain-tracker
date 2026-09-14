/// 睡眠 provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/database_provider.dart';
import 'sleep_models.dart';
import 'sleep_repository.dart';

/// 某晚睡眠（date = 起床日 yyyy-MM-dd；null = 当晚无数据）。
final sleepNightProvider = FutureProvider.family<SleepDay?, String>(
  (ref, date) async {
    final db = await ref.read(databaseReadyProvider.future);
    return loadSleepDay(db, date);
  },
);
