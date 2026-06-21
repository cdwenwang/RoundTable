import 'package:flutter/material.dart';

import '../../games/registry.dart';

/// 未上线游戏的占位页。
class ComingSoonScreen extends StatelessWidget {
  final GameDef game;
  const ComingSoonScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(game.name)),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: game.gradient,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(game.icon, size: 96, color: Colors.white70),
              const SizedBox(height: 24),
              Text(game.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('敬请期待', style: TextStyle(color: Colors.white70, fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }
}
