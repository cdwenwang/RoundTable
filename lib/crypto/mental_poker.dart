import 'dart:math';

import '../poker/card.dart';

/// 心智扑克（Mental Poker）协议：基于模幂交换加密，实现无信任荷官发牌。
///
/// 数学基础：在安全素数 p = 2q + 1 下，取二次剩余子群（阶为素数 q）的生成元 g。
/// 每张牌映射为 g^i（i=1..52），属于该子群。每个玩家持私钥指数 k（与 q 互素），
/// 加密 E_k(v)=v^k mod p，解密 D_k(v)=v^(k^{-1} mod q) mod p。
/// 由于 v = g^m，E_{k1}(E_{k2}(v)) = g^{m·k1·k2} = E_{k2}(E_{k1}(v))，满足交换律。
///
/// 协议流程（见 [MentalPoker]）：
/// 1. 全体依次对牌组「重新加密 + 置换」，得到多方加密且打乱的牌组。
/// 2. 发底牌给 P：取一个加密 token，除 P 外的玩家依次去掉自己的层，
///    最后由 P 去掉自己的层得 g^i（明文牌）——仅 P 可见。
/// 3. 发公共牌：全体依次去掉自己的层，所有人共同得 g^i。
///
/// 注意：[MentalPokerParams.dev] 的小素数仅供开发/测试，不具安全性；
/// 生产环境须使用 2048 位以上安全素数，且 v1 暂未实现零知识洗牌证明。

class MentalPokerParams {
  final BigInt p; // 安全素数
  final BigInt q; // (p-1)/2，二次剩余子群阶
  final BigInt g; // 二次剩余子群生成元

  const MentalPokerParams(this.p, this.q, this.g);

  /// 开发/测试参数：p=167（安全素数，q=83>52），完全不安全，仅用于验证协议正确性。
  static final MentalPokerParams dev = MentalPokerParams(
    BigInt.from(167),
    BigInt.from(83),
    BigInt.from(4), // 4 = 2^2，二次剩余，阶为 83
  );
}

/// 一个心智扑克参与方（一台设备），持私钥指数 k。
///
/// 在分布式（蓝牙）场景中，每台设备运行一个 [MentalPokerParticipant]，
/// 仅暴露 [encrypt]/[decryptLayer]/[shuffleAndEncrypt]，彼此通过传输层交换
/// BigInt 值；任何单方都看不到明文牌。本地测试中由 [MentalPoker] 编排全部参与方。
class MentalPokerParticipant {
  final String id;
  final MentalPokerParams params;
  final BigInt _k;

  MentalPokerParticipant(this.id, this.params, this._k);

  factory MentalPokerParticipant.random(
    String id,
    MentalPokerParams params,
    Random rng,
  ) {
    late BigInt k;
    do {
      k = _randomInRange(BigInt.two, params.q - BigInt.one, rng);
    } while (k.gcd(params.q) != BigInt.one);
    return MentalPokerParticipant(id, params, k);
  }

  BigInt get _kInv => _k.modInverse(params.q);

  /// 加密一层：v -> v^k mod p。
  BigInt encrypt(BigInt v) => v.modPow(_k, params.p);

  /// 去掉自己的一层：v -> v^(k^{-1} mod q) mod p。
  BigInt decryptLayer(BigInt v) => v.modPow(_kInv, params.p);

  /// 重新加密（每张牌升一次自己的幂）并随机置换。
  List<BigInt> shuffleAndEncrypt(List<BigInt> deck, Random rng) {
    final out = deck.map(encrypt).toList()..shuffle(rng);
    return out;
  }
}

/// 心智扑克协议编排器（进程内，持有全部参与方的密钥）。
///
/// 用于单测与桌面 MockTransport 联机模拟：验证协议正确性与私密性。
/// 真实蓝牙联机时，每台设备各自持有一个 [MentalPokerParticipant]，
/// 通过 [Transport]（Step 5）交换 token，复用同一套加密原语。
class MentalPoker {
  final MentalPokerParams params;
  final List<MentalPokerParticipant> participants;
  final Random rng;

  late List<BigInt> _deck;
  final Map<BigInt, Card> _valueToCard = {};
  final Map<Card, BigInt> _cardToValue = {};

  final List<Card> community = [];
  final Map<String, List<Card>> holeCards = {};

  MentalPoker(this.params, this.participants, this.rng) {
    for (var i = 0; i < 52; i++) {
      final value = params.g.modPow(BigInt.from(i + 1), params.p);
      _valueToCard[value] = Card.all[i];
      _cardToValue[Card.all[i]] = value;
    }
    _deck = [for (final c in Card.all) _cardToValue[c]!];
  }

  int get remaining => _deck.length;

  /// 全体依次重新加密 + 置换，完成洗牌。
  void shuffle() {
    for (final p in participants) {
      _deck = p.shuffleAndEncrypt(_deck, rng);
    }
  }

  /// 取一个加密 token，依次让所有参与方去掉自己的层，揭示为明文牌。
  /// `playerId` 指定归属（底牌）；公共牌传 null。
  Card _reveal({String? playerId}) {
    if (_deck.isEmpty) throw StateError('Deck empty');
    final token = _deck.removeLast();
    var v = token;
    // 模拟分布式协议：各方依次施加自己的解密层（顺序无关，因交换律）。
    for (final p in participants) {
      v = p.decryptLayer(v);
    }
    final card = _valueToCard[v];
    if (card == null) {
      throw StateError('Revealed value not a valid card: $v');
    }
    if (playerId != null) {
      holeCards.putIfAbsent(playerId, () => []).add(card);
    } else {
      community.add(card);
    }
    return card;
  }

  Card dealHoleTo(String playerId) => _reveal(playerId: playerId);
  Card revealCommunity() => _reveal();
}

BigInt _randomInRange(BigInt min, BigInt max, Random rng) {
  final range = max - min + BigInt.one;
  final bits = range.bitLength;
  BigInt r;
  do {
    r = _randomBits(bits, rng);
  } while (r >= range);
  return min + r;
}

BigInt _randomBits(int bits, Random rng) {
  final bytes = (bits + 7) ~/ 8;
  final out = <int>[];
  for (var i = 0; i < bytes; i++) {
    out.add(rng.nextInt(256));
  }
  var result = BigInt.zero;
  for (final b in out) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}
