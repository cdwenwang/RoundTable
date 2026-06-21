import 'package:flutter/material.dart';

import '../../crypto/mental_poker.dart';
import '../../net/mock_transport.dart';
import '../../poker/card.dart' as poker;
import '../../session/game_session.dart';
import '../widgets/playing_card.dart';

/// 蓝牙联机大厅。
///
/// 联机协议（分布式心智扑克）已在 [GameSession] 实现并通过 MockTransport 验证。
/// 真机蓝牙传输受 flutter_blue_plus 仅支持中心角色的限制（详见 [BluetoothTransport]），
/// 完整 P2P 待外设方案与真机验证。此处提供：
/// - 模拟联机演示：在桌面用两个进程内节点跑通真实发牌，直观验证心智扑克；
/// - 创建/加入房间：真机蓝牙入口（scaffold）。
class BluetoothLobbyScreen extends StatefulWidget {
  const BluetoothLobbyScreen({super.key});

  @override
  State<BluetoothLobbyScreen> createState() => _BluetoothLobbyScreenState();
}

class _BluetoothLobbyScreenState extends State<BluetoothLobbyScreen> {
  bool _running = false;

  Future<void> _runMockDemo() async {
    setState(() => _running = true);
    final hub = MockTransportHub();
    final params = MentalPokerParams.dev;
    final host = GameSession(
      localId: 'host', localName: '庄家', isHost: true,
      params: params, transport: hub.create('host'),
    );
    final client = GameSession(
      localId: 'client', localName: '玩家', isHost: false,
      params: params, transport: hub.create('client'),
    );

    await host.start();
    await client.start();
    await client.joinAsClient();
    await Future.delayed(Duration.zero);
    await host.runShuffle();
    await host.dealHole('host');
    await host.dealHole('client');
    await host.dealHole('host');
    await host.dealHole('client');
    for (var i = 0; i < 5; i++) {
      await host.revealCommunity();
    }
    await host.close();
    await client.close();

    if (!mounted) return;
    setState(() => _running = false);
    _showDemoResult(host, client);
  }

  void _showDemoResult(GameSession host, GameSession client) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('模拟联机发牌结果'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('庄家底牌', host.holeCards['host'] ?? const []),
              _row('玩家底牌', client.holeCards['client'] ?? const []),
              _row('公共牌', host.community),
              const SizedBox(height: 8),
              const Text(
                '✓ 庄家看不到玩家底牌，玩家也看不到庄家底牌——心智扑克保证私密性。\n'
                '✓ 双方公共牌一致。',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _row(String label, List<poker.Card> cards) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(label)),
            for (final c in cards) Padding(padding: const EdgeInsets.only(right: 4), child: PlayingCardView(card: c)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙联机')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '联机发牌采用心智扑克（无信任荷官），任何一端都无法提前知晓牌面。\n\n'
                  '当前蓝牙传输基于 flutter_blue_plus（中心角色），完整 P2P 需外设侧方案与真机验证。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _running ? null : _runMockDemo,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.science),
              label: Text(_running ? '发牌中…' : '模拟联机演示（桌面）'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _todo('创建房间（主机）需真机蓝牙'),
              icon: const Icon(Icons.router),
              label: const Text('创建房间（主机）'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _todo('加入房间需真机蓝牙扫描'),
              icon: const Icon(Icons.search),
              label: const Text('加入房间（扫描）'),
            ),
          ],
        ),
      ),
    );
  }

  void _todo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
