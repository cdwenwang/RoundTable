import 'dart:math';

import 'card.dart';

/// 牌组。`draw()` 从顶部抽一张；`shuffle()` 洗牌。
///
/// 单机模式直接用明文 Deck 发牌；联机模式中心智扑克协议在加密层
/// 处理发牌，但牌的明文映射仍复用 [Card.all] 的顺序。
class Deck {
  final List<Card> _cards;

  Deck._(this._cards);

  factory Deck.fresh() => Deck._(List.of(Card.all));

  /// 用给定牌序构造（测试用，或从加密协议解出的顺序恢复）。
  factory Deck.from(Iterable<Card> cards) => Deck._(List.of(cards));

  int get length => _cards.length;
  bool get isEmpty => _cards.isEmpty;
  bool get isNotEmpty => _cards.isNotEmpty;

  List<Card> get remaining => List.unmodifiable(_cards);

  Card draw() {
    if (_cards.isEmpty) throw StateError('Deck is empty');
    return _cards.removeLast();
  }

  List<Card> drawMany(int n) {
    if (n > _cards.length) throw StateError('Not enough cards: need $n, have ${_cards.length}');
    return [for (var i = 0; i < n; i++) _cards.removeLast()];
  }

  void shuffle([Random? rng]) => _cards.shuffle(rng ?? Random());
}
