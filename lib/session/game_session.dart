import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../crypto/mental_poker.dart';
import '../net/transport.dart';
import '../poker/card.dart';

/// 联机对局会话：在 [Transport] 之上运行分布式心智扑克协议。
///
/// 角色模型：**host** 既是参与者也是协议协调者（负责发牌流程编排），
/// 但 host 并不持有他人的私钥，因此无法提前知晓牌面——发牌私密性由心智扑克保证。
///
/// 协议消息（JSON）：
/// - `join`/`joinAck`：客户端加入、host 回发座次与参数
/// - `shuffle`/`shuffleResp`：host 把牌组交给某参与者重新加密+置换
/// - `deckReady`：最终加密牌组广播
/// - `peel`/`peelResp`：请某参与者去掉自己的一层（发底牌/公共牌时逐层剥离）
/// - `reveal`：把只剩目标玩家一层的数据发给该玩家，由其自行揭示
/// - `community`：host 广播公共牌明文
class GameSession {
  final String localId;
  final String localName;
  final bool isHost;
  final MentalPokerParams params;
  final Transport transport;

  late final MentalPokerParticipant me;
  final Map<String, String> peers = {}; // id -> name
  final Map<BigInt, Card> _valueToCard = {};

  List<String> order = []; // 座次（含 host），host 在前
  List<BigInt> _deck = [];
  final List<Card> community = [];
  final Map<String, List<Card>> holeCards = {};

  StreamSubscription<TransportMessage>? _sub;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _rid = 1;

  GameSession({
    required this.localId,
    required this.localName,
    required this.isHost,
    required this.params,
    required this.transport,
  }) {
    // 每个参与者用基于 id 的不同种子生成私钥（保证各方密钥不同 → 私密性）。
    // 真实部署应使用密码学安全随机源。
    me = MentalPokerParticipant.random(localId, params, Random(localId.hashCode));
    _rng = Random(localId.hashCode ^ 0x5EED);
    for (var i = 0; i < 52; i++) {
      _valueToCard[params.g.modPow(BigInt.from(i + 1), params.p)] = Card.all[i];
    }
  }

  late final Random _rng;

  Future<void> start() async {
    await transport.start();
    _sub = transport.messages.listen(_onMessage);
  }

  void _onMessage(TransportMessage msg) {
    final m = jsonDecode(utf8.decode(msg.bytes)) as Map<String, dynamic>;
    final rid = m['rid'] as int?;
    switch (m['t']) {
      case 'join':
        if (isHost) {
          peers[msg.fromId] = m['name'] as String;
          _broadcastJoinAck();
        }
        break;
      case 'joinAck':
        peers
          ..clear()
          ..addEntries((m['peers'] as Map).cast<String, String>().entries);
        order = (m['order'] as List).cast<String>();
        break;
      case 'shuffle':
        final deck = _decodeDeck(m['deck'] as List);
        final reshuffled = me.shuffleAndEncrypt(deck, _rng);
        _reply(msg.fromId, rid!, {'t': 'shuffleResp', 'deck': _encodeDeck(reshuffled)});
        break;
      case 'shuffleResp':
        _resolve(rid!, {'deck': _decodeDeck(m['deck'] as List)});
        break;
      case 'peel':
        final v = BigInt.parse(m['value'] as String);
        _reply(msg.fromId, rid!, {'t': 'peelResp', 'value': me.decryptLayer(v).toString()});
        break;
      case 'peelResp':
        _resolve(rid!, {'value': BigInt.parse(m['value'] as String)});
        break;
      case 'reveal':
        // 只剩自己一层，去掉后揭示为明文牌。
        final v = BigInt.parse(m['value'] as String);
        final card = _valueToCard[me.decryptLayer(v)];
        if (card != null) {
          holeCards.putIfAbsent(localId, () => []).add(card);
        }
        _reply(msg.fromId, rid!, {'t': 'revealResp', 'ok': true});
        break;
      case 'revealResp':
        _resolve(rid!, {'ok': true});
        break;
      case 'deckReady':
        _deck = _decodeDeck(m['deck'] as List);
        break;
      case 'community':
        community.add(Card.all[m['card'] as int]);
        break;
    }
  }

  void _broadcastJoinAck() {
    peers[localId] = localName;
    order = [localId, ...peers.keys.where((k) => k != localId)];
    broadcast({
      't': 'joinAck',
      'peers': peers,
      'order': order,
    });
  }

  // --- host: 发牌流程 ---

  /// 客户端加入后由 host 调用：完成洗牌（全体依次重新加密+置换）。
  Future<void> runShuffle() async {
    assert(isHost);
    _deck = [for (var i = 0; i < 52; i++) params.g.modPow(BigInt.from(i + 1), params.p)];
    // host 自己先洗。
    _deck = me.shuffleAndEncrypt(_deck, _rng);
    // 其余参与者依次洗。
    for (final id in order) {
      if (id == localId) continue;
      final resp = await _request(id, {'t': 'shuffle', 'deck': _encodeDeck(_deck)});
      _deck = resp['deck'] as List<BigInt>;
    }
    broadcast({'t': 'deckReady', 'deck': _encodeDeck(_deck)});
  }

  /// 给 [playerId] 发一张底牌（仅该玩家可见）。
  Future<Card> dealHole(String playerId) async {
    assert(isHost);
    final token = _deck.removeLast();
    var v = token;
    // 剥离除目标玩家以外所有参与者的层。
    for (final id in order) {
      if (id == playerId) continue;
      if (id == localId) {
        v = me.decryptLayer(v);
      } else {
        final resp = await _request(id, {'t': 'peel', 'value': v.toString()});
        v = resp['value'] as BigInt;
      }
    }
    // 只剩目标玩家一层：交给其自行揭示。
    if (playerId == localId) {
      final card = _valueToCard[me.decryptLayer(v)]!;
      holeCards.putIfAbsent(localId, () => []).add(card);
      return card;
    } else {
      await _request(playerId, {'t': 'reveal', 'value': v.toString()});
      // host 不知道明文，返回占位；明文仅在该玩家本机记录。
      return Card.all.first;
    }
  }

  /// 揭示一张公共牌（全体剥离全部层，公开明文）。
  Future<Card> revealCommunity() async {
    assert(isHost);
    final token = _deck.removeLast();
    var v = token;
    for (final id in order) {
      if (id == localId) {
        v = me.decryptLayer(v);
      } else {
        final resp = await _request(id, {'t': 'peel', 'value': v.toString()});
        v = resp['value'] as BigInt;
      }
    }
    final card = _valueToCard[v]!;
    community.add(card);
    broadcast({'t': 'community', 'card': Card.all.indexOf(card)});
    return card;
  }

  // --- 消息收发辅助 ---

  Future<Map<String, dynamic>> _request(String to, Map<String, dynamic> msg) async {
    final rid = _rid++;
    msg['rid'] = rid;
    final c = Completer<Map<String, dynamic>>();
    _pending[rid] = c;
    await transport.sendTo(to, utf8.encode(jsonEncode(msg)));
    return c.future;
  }

  void _reply(String to, int rid, Map<String, dynamic> body) {
    body['rid'] = rid;
    transport.sendTo(to, utf8.encode(jsonEncode(body)));
  }

  /// 客户端发起加入（广播，host 收到后回发座次）。
  Future<void> joinAsClient() async {
    await broadcast({'t': 'join', 'name': localName});
  }

  void _resolve(int rid, Map<String, dynamic> result) {
    final c = _pending.remove(rid);
    c?.complete(result);
  }

  Future<void> broadcast(Map<String, dynamic> msg) {
    return transport.broadcast(utf8.encode(jsonEncode(msg)));
  }

  List<String> _encodeDeck(List<BigInt> deck) =>
      [for (final v in deck) v.toString()];
  List<BigInt> _decodeDeck(List<dynamic> list) =>
      [for (final s in list) BigInt.parse(s as String)];

  Future<void> close() async {
    await _sub?.cancel();
    await transport.close();
  }
}
