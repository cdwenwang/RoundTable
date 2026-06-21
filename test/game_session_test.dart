import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/crypto/mental_poker.dart';
import 'package:round_table/net/mock_transport.dart';
import 'package:round_table/session/game_session.dart';

void main() {
  test('2-node mental poker over MockTransport: shuffle + deal + community', () async {
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

    expect(host.order, containsAll(['host', 'client']));
    expect(client.order, containsAll(['host', 'client']));

    await host.runShuffle();
    await host.dealHole('host');
    await host.dealHole('client');
    await host.dealHole('host');
    await host.dealHole('client');
    for (var i = 0; i < 5; i++) {
      await host.revealCommunity();
    }

    expect(host.holeCards['host']!.length, 2);
    expect(client.holeCards['client']!.length, 2);
    expect(host.community.length, 5);
    expect(client.community.length, 5);
    expect(host.community, equals(client.community));

    final all = [
      ...host.holeCards['host']!,
      ...client.holeCards['client']!,
      ...host.community,
    ];
    expect(all.toSet().length, 9);

    // 私密性：host 不知道 client 的底牌，反之亦然。
    expect(host.holeCards.containsKey('client'), isFalse);
    expect(client.holeCards.containsKey('host'), isFalse);

    await host.close();
    await client.close();
  });
}
