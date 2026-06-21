import 'package:flutter/material.dart';

import '../../games/registry.dart';
import 'coming_soon_screen.dart';
import 'texas_lobby_screen.dart';

/// App 入口：全屏游戏轮播。左右滑动切换游戏，点击进入对应游戏大厅。
///
/// 每个游戏封面目前用「全屏渐变 + 图标 + 名称」占位，后续可替换为动态图/视频素材
///（仅需把 [GameCover] 的背景换成 Image/Video 组件即可）。
class GameCarouselScreen extends StatefulWidget {
  const GameCarouselScreen({super.key});

  @override
  State<GameCarouselScreen> createState() => _GameCarouselScreenState();
}

class _GameCarouselScreenState extends State<GameCarouselScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            itemCount: games.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => GameCover(
              game: games[i],
              onTap: () => _enter(games[i]),
            ),
          ),
          // 顶部标题
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('选择游戏',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          // 底部页码指示
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < games.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _enter(GameDef game) {
    final screen = switch (game.id) {
      'texas' => const TexasLobbyScreen(),
      _ => ComingSoonScreen(game: game),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

/// 单个游戏的全屏封面。占位用渐变 + 呼吸动画的图标；后续可换动态素材。
class GameCover extends StatefulWidget {
  final GameDef game;
  final VoidCallback onTap;

  const GameCover({super.key, required this.game, required this.onTap});

  @override
  State<GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<GameCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g.gradient,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(
                    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
                  ),
                  child: Icon(g.icon, size: 120, color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Text(g.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(g.subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 16)),
                const SizedBox(height: 40),
                if (!g.available)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Chip(
                      label: Text('敬请期待'),
                      backgroundColor: Colors.black38,
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                Text(
                  g.available ? '点击进入 · 左右滑动切换' : '左右滑动切换',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
