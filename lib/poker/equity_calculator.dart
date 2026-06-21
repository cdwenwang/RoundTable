import 'dart:math';

import 'card.dart';
import 'hand_evaluator.dart';

/// 胜率计算结果。
class EquityResult {
  final double winRate;
  final double tieRate;
  final HandResult bestHand;
  final int outs;
  final List<KeyOut> keyOuts;
  final int unknownCards;

  const EquityResult({
    required this.winRate,
    required this.tieRate,
    required this.bestHand,
    required this.outs,
    required this.keyOuts,
    required this.unknownCards,
  });

  HandCategory get currentCategory => bestHand.category;
  String get currentName => _catName(currentCategory);
  double get drawProb => outs <= 0 || unknownCards <= 0 ? 0 : outs / unknownCards;

  static String _catName(HandCategory c) => switch (c) {
        HandCategory.highCard => '高牌',
        HandCategory.pair => '一对',
        HandCategory.twoPair => '两对',
        HandCategory.threeOfAKind => '三条',
        HandCategory.straight => '顺子',
        HandCategory.flush => '同花',
        HandCategory.fullHouse => '葫芦',
        HandCategory.fourOfAKind => '四条',
        HandCategory.straightFlush => '同花顺',
      };
}

class KeyOut {
  final Card card;
  final String target;
  final double winIncrease;
  const KeyOut({required this.card, required this.target, required this.winIncrease});
}

/// 蒙特卡洛胜率计算器。
class EquityCalculator {
  final List<Card> heroHole;
  final List<Card> community;
  final int opponentCount;
  final Random _rng;

  EquityCalculator({
    required this.heroHole,
    required this.community,
    required this.opponentCount,
    Random? rng,
  }) : _rng = rng ?? Random();

  static const int _sims = 1500;

  EquityResult calculate() {
    final remainingComm = 5 - community.length;
    final known = [...heroHole, ...community];
    final pool = [...Card.all]..removeWhere((c) => known.contains(c));
    final unknownCount = pool.length;
    final best = bestHand([...known]);

    var wins = 0.0, ties = 0.0;
    final cardWins = <Card, double>{};
    final cardCounts = <Card, int>{};

    for (var s = 0; s < _sims; s++) {
      final deck = [...pool]..shuffle(_rng);
      int i = 0;
      Card pop() { final c = deck[i++]; return c; }

      final simComm = [...community];
      final commDrawn = <Card>[];
      for (var j = 0; j < remainingComm; j++) {
        final c = pop(); simComm.add(c); commDrawn.add(c);
      }
      final firstTurn = remainingComm > 0 ? commDrawn.first : null;
      if (firstTurn != null) cardCounts[firstTurn] = (cardCounts[firstTurn] ?? 0) + 1;

      final oppHands = <List<Card>>[];
      for (var o = 0; o < opponentCount; o++) oppHands.add([pop(), pop()]);

      final heroR = bestHand([...heroHole, ...simComm]);
      var heroWin = true, heroTie = false;
      for (final opp in oppHands) {
        final cmp = heroR.compareTo(bestHand([...opp, ...simComm]));
        if (cmp < 0) { heroWin = false; break; }
        if (cmp == 0) heroTie = true;
      }
      if (heroWin) {
        wins += heroTie ? 0.5 : 1.0;
        if (firstTurn != null) cardWins[firstTurn] = (cardWins[firstTurn] ?? 0) + 1.0;
      } else if (heroTie) {
        ties += 0.5;
      }
    }

    final winRate = wins / _sims;
    final tieRate = ties / _sims;

    final keyOuts = <KeyOut>[];
    if (remainingComm > 0) {
      for (final c in cardCounts.keys) {
        final cnt = cardCounts[c]!;
        if (cnt == 0) continue;
        final inc = (cardWins[c] ?? 0) / cnt - winRate;
        if (inc > 0.03) keyOuts.add(KeyOut(card: c, target: _targetOf(heroHole, c, community), winIncrease: inc));
      }
      keyOuts.sort((a, b) => b.winIncrease.compareTo(a.winIncrease));
    }

    final outs = _countOuts(pool, heroHole, community);

    return EquityResult(
      winRate: winRate, tieRate: tieRate, bestHand: best,
      outs: outs, keyOuts: keyOuts.take(6).toList(),
      unknownCards: unknownCount,
    );
  }

  static String _targetOf(List<Card> hole, Card c, List<Card> comm) {
    final r = bestHand([...hole, ...comm, c]).category;
    if (r == HandCategory.straightFlush || r == HandCategory.flush) return '同花';
    if (r == HandCategory.straight) return '顺子';
    if (r == HandCategory.fourOfAKind || r == HandCategory.fullHouse) return '葫芦+';
    if (r == HandCategory.threeOfAKind) return '三条';
    if (r == HandCategory.twoPair) return '两对';
    return '提升';
  }

  static int _countOuts(List<Card> pool, List<Card> hole, List<Card> comm) {
    final cur = bestHand([...hole, ...comm]);
    var o = 0;
    for (final c in pool) { if (bestHand([...hole, ...comm, c]).compareTo(cur) > 0) o++; }
    return o;
  }
}
