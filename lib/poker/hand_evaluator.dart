import 'card.dart';

/// 5 张牌的牌型类别，从弱到强。`index` 即可用于比较大小。
enum HandCategory {
  highCard,
  pair,
  twoPair,
  threeOfAKind,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
}

/// 一手 5 张牌的评估结果。
///
/// `kickers` 为从高到低的比较因子（已编码类别内部细节，如两对的两个对子+ kicker、
/// 顺子的高牌等）。两个 [HandResult] 仅按 `category.index` 与 `kickers` 逐位比较。
class HandResult implements Comparable<HandResult> {
  final HandCategory category;
  final List<int> kickers;

  const HandResult(this.category, this.kickers);

  @override
  int compareTo(HandResult other) {
    final c = category.index.compareTo(other.category.index);
    if (c != 0) return c;
    for (var i = 0; i < kickers.length && i < other.kickers.length; i++) {
      final d = kickers[i].compareTo(other.kickers[i]);
      if (d != 0) return d;
    }
    return 0;
  }

  bool get isStraightFlush => category == HandCategory.straightFlush;

  @override
  String toString() => '${category.name}$kickers';
}

/// 评估恰好 5 张牌。
HandResult evaluate5(List<Card> cards) {
  if (cards.length != 5) {
    throw ArgumentError('evaluate5 requires exactly 5 cards, got ${cards.length}');
  }

  final values = cards.map((c) => c.value).toList()..sort((a, b) => b.compareTo(a));
  final isFlush = cards.map((c) => c.suit).toSet().length == 1;
  final straightHigh = _straightHigh(values);

  // 按点数统计：count 降序，点数降序。
  final counts = <int, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final groups = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : b.key.compareTo(a.key);
    });

  if (straightHigh != null && isFlush) {
    return HandResult(HandCategory.straightFlush, [straightHigh]);
  }
  if (groups.first.value == 4) {
    return HandResult(HandCategory.fourOfAKind, [groups[0].key, groups[1].key]);
  }
  if (groups.first.value == 3 && groups[1].value >= 2) {
    return HandResult(HandCategory.fullHouse, [groups[0].key, groups[1].key]);
  }
  if (isFlush) {
    return HandResult(HandCategory.flush, values);
  }
  if (straightHigh != null) {
    return HandResult(HandCategory.straight, [straightHigh]);
  }
  if (groups.first.value == 3) {
    return HandResult(
      HandCategory.threeOfAKind,
      [groups[0].key, groups[1].key, groups[2].key],
    );
  }
  if (groups.first.value == 2 && groups[1].value == 2) {
    return HandResult(
      HandCategory.twoPair,
      [groups[0].key, groups[1].key, groups[2].key],
    );
  }
  if (groups.first.value == 2) {
    return HandResult(
      HandCategory.pair,
      [groups[0].key, groups[1].key, groups[2].key, groups[3].key],
    );
  }
  return HandResult(HandCategory.highCard, values);
}

/// 从 5~7 张牌中选最佳 5 张组合。
HandResult bestHand(List<Card> cards) {
  return bestHandWithCards(cards).result;
}

/// 返回最佳组合的评估结果和对应 5 张牌。
({HandResult result, List<Card> cards}) bestHandWithCards(List<Card> cards) {
  if (cards.length < 5) {
    throw ArgumentError('bestHand requires at least 5 cards, got ${cards.length}');
  }
  if (cards.length == 5) {
    return (result: evaluate5(cards), cards: List.of(cards));
  }

  ({HandResult result, List<Card> cards})? best;
  for (final combo in _combinations(cards, 5)) {
    final r = evaluate5(combo);
    if (best == null || r.compareTo(best.result) > 0) {
      best = (result: r, cards: combo);
    }
  }
  return best!;
}

/// 返回顺子的最高牌点数；非顺子返回 null。
/// `values` 须已降序排列。处理 wheel（A-2-3-4-5，高牌为 5）。
int? _straightHigh(List<int> values) {
  final distinct = <int>[...{...values}]..sort((a, b) => b.compareTo(a));
  if (distinct.length < 5) return null;

  for (var i = 0; i <= distinct.length - 5; i++) {
    final window = distinct.sublist(i, i + 5);
    if (_isConsecutive(window)) return window.first;
  }
  // wheel: A(14)-5-4-3-2
  if (distinct.contains(14) &&
      distinct.contains(5) &&
      distinct.contains(4) &&
      distinct.contains(3) &&
      distinct.contains(2)) {
    return 5;
  }
  return null;
}

bool _isConsecutive(List<int> desc) {
  for (var i = 1; i < desc.length; i++) {
    if (desc[i - 1] - desc[i] != 1) return false;
  }
  return true;
}

/// 从 [items] 中取 [k] 个的所有组合（保持原相对顺序）。
Iterable<List<T>> _combinations<T>(List<T> items, int k) sync* {
  if (k == 0) {
    yield [];
    return;
  }
  if (k > items.length) return;
  for (var i = 0; i <= items.length - k; i++) {
    final head = items[i];
    for (final tail in _combinations(items.sublist(i + 1), k - 1)) {
      yield [head, ...tail];
    }
  }
}
