/// 德州扑克牌的领域模型。纯 Dart，无 Flutter 依赖，可单测。
library;

enum Suit { clubs, diamonds, hearts, spades }

enum Rank {
  two(2, '2'),
  three(3, '3'),
  four(4, '4'),
  five(5, '5'),
  six(6, '6'),
  seven(7, '7'),
  eight(8, '8'),
  nine(9, '9'),
  ten(10, 'T'),
  jack(11, 'J'),
  queen(12, 'Q'),
  king(13, 'K'),
  ace(14, 'A');

  const Rank(this.value, this.label);
  final int value;
  final String label;
}

/// 一张牌。`value` 为 2..14，A 最大（顺子中可作 1 构成 A-2-3-4-5）。
class Card {
  final Rank rank;
  final Suit suit;

  const Card(this.rank, this.suit);

  int get value => rank.value;

  static final List<Card> all = [
    for (final r in Rank.values) for (final s in Suit.values) Card(r, s),
  ];

  @override
  bool operator ==(Object other) =>
      other is Card && rank == other.rank && suit == other.suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  @override
  String toString() => '${rank.label}${_suitChar(suit)}';

  static String _suitChar(Suit s) => switch (s) {
        Suit.clubs => '♣',
        Suit.diamonds => '♦',
        Suit.hearts => '♥',
        Suit.spades => '♠',
      };
}
