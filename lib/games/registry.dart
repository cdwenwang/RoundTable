import 'package:flutter/material.dart';

/// 一个游戏的定义（轮播封面用）。后续新增游戏只需在此列表追加一项。
class GameDef {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool available; // false = 仅入口占位，进入后显示「敬请期待」

  const GameDef({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.available = true,
  });
}

/// 当前支持的游戏列表。轮播、大厅路由都据此生成。
const List<GameDef> games = [
  GameDef(
    id: 'texas',
    name: '德州扑克',
    subtitle: 'Texas Hold\'em',
    icon: Icons.casino,
    gradient: [Color(0xFF0B6E4F), Color(0xFF063528)],
  ),
  GameDef(
    id: 'werewolf',
    name: '狼人杀',
    subtitle: 'Werewolf',
    icon: Icons.nights_stay,
    gradient: [Color(0xFF4A148C), Color(0xFF1A0930)],
    available: false,
  ),
];
