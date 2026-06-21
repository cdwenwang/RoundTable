import 'package:flutter/material.dart';

import 'screens/game_carousel_screen.dart';

class RoundTableApp extends StatelessWidget {
  const RoundTableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoundTable · 游戏大厅',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GameCarouselScreen(),
    );
  }
}
