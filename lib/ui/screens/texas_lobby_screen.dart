import 'package:flutter/material.dart';

import 'bluetooth_lobby_screen.dart';
import 'table_screen.dart';

/// 德州扑克场景定义。
class TexasScene {
  final String id;
  final String label;
  final int seats;
  const TexasScene({required this.id, required this.label, required this.seats});
}

const List<TexasScene> texasScenes = [
  TexasScene(id: '5', label: '5 人桌', seats: 5),
  TexasScene(id: '8', label: '8 人桌', seats: 8),
];

/// 德州扑克大厅：选场景 → 创建/加入桌子。
class TexasLobbyScreen extends StatefulWidget {
  const TexasLobbyScreen({super.key});

  @override
  State<TexasLobbyScreen> createState() => _TexasLobbyScreenState();
}

class _TexasLobbyScreenState extends State<TexasLobbyScreen> {
  int _sceneIndex = 0;
  int _buyIn = 1000;
  int _smallBlind = 10;
  int get _bigBlind => _smallBlind * 2;

  TexasScene get _scene => texasScenes[_sceneIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('德州扑克 · 大厅')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('选择场景', style: TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (var i = 0; i < texasScenes.length; i++)
                ChoiceChip(
                  label: Text(texasScenes[i].label),
                  selected: i == _sceneIndex,
                  onSelected: (_) => setState(() => _sceneIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('初始买入', style: TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (final b in const [500, 1000, 2000, 5000])
                ChoiceChip(
                  label: Text('$b'),
                  selected: _buyIn == b,
                  onSelected: (_) => setState(() => _buyIn = b),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('小盲注 / 大盲注', style: TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (final s in const [5, 10, 20, 50])
                ChoiceChip(
                  label: Text('$s / ${s * 2}'),
                  selected: _smallBlind == s,
                  onSelected: (_) => setState(() => _smallBlind = s),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TableScreen(
                seats: _scene.seats,
                sceneLabel: _scene.label,
                buyIn: _buyIn,
                smallBlind: _smallBlind,
                bigBlind: _bigBlind,
              ),
            )),
            icon: const Icon(Icons.add_circle_outline),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('创建新桌子', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _toast('自动加入：附近暂无桌子'),
            icon: const Icon(Icons.login),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('自动加入附近桌子'),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              const Expanded(
                child: Divider(color: Colors.white24),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('附近桌子', style: TextStyle(color: Colors.white54)),
              ),
              const Expanded(
                child: Divider(color: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NearbyTablesStub(),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const BluetoothLobbyScreen(),
            )),
            icon: const Icon(Icons.science, size: 18),
            label: const Text('模拟联机演示（心智扑克）'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 「附近桌子」占位：蓝牙联机尚未打通，先显示扫描态。
class _NearbyTablesStub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.bluetooth_searching, color: Colors.white54, size: 36),
          SizedBox(height: 8),
          Text('蓝牙扫描中…', style: TextStyle(color: Colors.white70)),
          SizedBox(height: 4),
          Text('附近暂无已创建的桌子', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
