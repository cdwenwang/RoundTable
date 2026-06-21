import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/poker/card.dart';
import 'package:round_table/poker/hand_evaluator.dart';

Card c(Rank r, Suit s) => Card(r, s);

void main() {
  group('evaluate5 categories', () {
    test('royal flush', () {
      final r = evaluate5([
        c(Rank.ace, Suit.spades), c(Rank.king, Suit.spades), c(Rank.queen, Suit.spades),
        c(Rank.jack, Suit.spades), c(Rank.ten, Suit.spades),
      ]);
      expect(r.category, HandCategory.straightFlush);
      expect(r.kickers.first, 14);
    });

    test('straight flush (non-royal)', () {
      final r = evaluate5([
        c(Rank.nine, Suit.hearts), c(Rank.eight, Suit.hearts), c(Rank.seven, Suit.hearts),
        c(Rank.six, Suit.hearts), c(Rank.five, Suit.hearts),
      ]);
      expect(r.category, HandCategory.straightFlush);
      expect(r.kickers.first, 9);
    });

    test('wheel straight (A-2-3-4-5) high is 5', () {
      final r = evaluate5([
        c(Rank.ace, Suit.clubs), c(Rank.two, Suit.diamonds), c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.spades), c(Rank.five, Suit.clubs),
      ]);
      expect(r.category, HandCategory.straight);
      expect(r.kickers.first, 5);
    });

    test('four of a kind', () {
      final r = evaluate5([
        c(Rank.nine, Suit.clubs), c(Rank.nine, Suit.diamonds), c(Rank.nine, Suit.hearts),
        c(Rank.nine, Suit.spades), c(Rank.king, Suit.clubs),
      ]);
      expect(r.category, HandCategory.fourOfAKind);
      expect(r.kickers, [9, 13]);
    });

    test('full house', () {
      final r = evaluate5([
        c(Rank.king, Suit.clubs), c(Rank.king, Suit.diamonds), c(Rank.king, Suit.hearts),
        c(Rank.queen, Suit.spades), c(Rank.queen, Suit.clubs),
      ]);
      expect(r.category, HandCategory.fullHouse);
      expect(r.kickers, [13, 12]);
    });

    test('flush beats straight', () {
      final flush = evaluate5([
        c(Rank.two, Suit.hearts), c(Rank.five, Suit.hearts), c(Rank.seven, Suit.hearts),
        c(Rank.nine, Suit.hearts), c(Rank.king, Suit.hearts),
      ]);
      final straight = evaluate5([
        c(Rank.six, Suit.clubs), c(Rank.seven, Suit.diamonds), c(Rank.eight, Suit.hearts),
        c(Rank.nine, Suit.spades), c(Rank.ten, Suit.clubs),
      ]);
      expect(flush.compareTo(straight), greaterThan(0));
    });

    test('two pair with kicker', () {
      final r = evaluate5([
        c(Rank.ten, Suit.clubs), c(Rank.ten, Suit.diamonds), c(Rank.four, Suit.hearts),
        c(Rank.four, Suit.spades), c(Rank.ace, Suit.clubs),
      ]);
      expect(r.category, HandCategory.twoPair);
      expect(r.kickers, [10, 4, 14]);
    });

    test('high card', () {
      final r = evaluate5([
        c(Rank.two, Suit.clubs), c(Rank.four, Suit.diamonds), c(Rank.six, Suit.hearts),
        c(Rank.eight, Suit.spades), c(Rank.king, Suit.clubs),
      ]);
      expect(r.category, HandCategory.highCard);
    });
  });

  group('bestHand (7 cards)', () {
    test('picks straight flush over pair', () {
      // 手牌一对 A，公共牌含同花顺
      final r = bestHand([
        c(Rank.ace, Suit.diamonds), c(Rank.ace, Suit.clubs),
        c(Rank.nine, Suit.spades), c(Rank.eight, Suit.spades), c(Rank.seven, Suit.spades),
        c(Rank.six, Suit.spades), c(Rank.five, Suit.spades),
      ]);
      expect(r.category, HandCategory.straightFlush);
    });

    test('pair in hand plus community makes trips not visible if not present', () {
      final r = bestHand([
        c(Rank.ace, Suit.diamonds), c(Rank.king, Suit.clubs),
        c(Rank.two, Suit.hearts), c(Rank.four, Suit.spades), c(Rank.six, Suit.clubs),
        c(Rank.eight, Suit.diamonds), c(Rank.ten, Suit.hearts),
      ]);
      expect(r.category, HandCategory.highCard);
    });

    test('comparison: higher two pair wins', () {
      final a = bestHand([
        c(Rank.ace, Suit.diamonds), c(Rank.ace, Suit.clubs),
        c(Rank.king, Suit.hearts), c(Rank.king, Suit.spades),
        c(Rank.two, Suit.clubs), c(Rank.three, Suit.diamonds), c(Rank.four, Suit.hearts),
      ]);
      final b = bestHand([
        c(Rank.king, Suit.diamonds), c(Rank.king, Suit.clubs),
        c(Rank.queen, Suit.hearts), c(Rank.queen, Suit.spades),
        c(Rank.two, Suit.clubs), c(Rank.three, Suit.diamonds), c(Rank.four, Suit.hearts),
      ]);
      expect(a.compareTo(b), greaterThan(0));
    });
  });
}
