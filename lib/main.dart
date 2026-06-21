import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app.dart';

void main() {
  // 将所有 Flutter 渲染错误打印到 logcat，关键字 [RT_ERR] 方便过滤
  FlutterError.onError = (details) {
    debugPrint('[RT_ERR] ${details.exception}');
    final lines = details.stack?.toString().split('\n') ?? [];
    for (final line in lines.take(20)) {
      debugPrint('[RT_ERR]   $line');
    }
    FlutterError.presentError(details);
  };
  runApp(const ProviderScope(child: RoundTableApp()));
}
