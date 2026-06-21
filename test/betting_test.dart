import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/poker/betting.dart';
import 'package:round_table/poker/card.dart';
import 'package:round_table/poker/deck.dart';
import 'package:round_table/poker/game_engine.dart';
import 'package:round_table/poker/game_state.dart';

Player _p(String id, int stack) => Player(id: id, name: id, stack: stack);

void main() {
  group('computePots side pots', () {
    test('main pot only when equal contributions', () {
      final a = _p('A', 0)..totalBet = 100;
      final b = _p('B', 0)..totalBet = 100;
      final c = _p('C', 0)..totalBet = 100;
      final pots = computePots([a, b, c]);
      expect(pots.length, 1);
      expect(pots[0].amount, 300);
      expect(pots[0].eligiblePlayerIds, containsAll(['A', 'B', 'C']));
    });

    test('all-in for less creates main + side pot', () {
      final a = _p('A', 0)..totalBet = 100; // all-in short, in hand
      final b = _p('B', 0)..totalBet = 300;
      final c = _p('C', 0)..totalBet = 300;
      final pots = computePots([a, b, c]);
      expect(pots.length, 2);
      // 主池 100*3=300，A/B/C 都有资格
      expect(pots[0].amount, 300);
      expect(pots[0].eligiblePlayerIds, containsAll(['A', 'B', 'C']));
      // 边池 200*2=400，仅 B/C
      expect(pots[1].amount, 400);
      expect(pots[1].eligiblePlayerIds, containsAll(['B', 'C']));
      expect(pots[1].eligiblePlayerIds, isNot(contains('A')));
    });

    test('folded player contributes but is not eligible', () {
      final a = _p('A', 0)
        ..totalBet = 50
        ..folded = true;
      final b = _p('B', 0)..totalBet = 200;
      final c = _p('C', 0)..totalBet = 200;
      final pots = computePots([a, b, c]);
      final total = pots.fold<int>(0, (s, p) => s + p.amount);
      expect(total, 450);
      for (final pot in pots) {
        expect(pot.eligiblePlayerIds, isNot(contains('A')));
      }
    });
  });

  group('GameEngine full hand', () {
    test('heads-up, both check to showdown, pot distributed', () {
      final hero = Player(id: 'hero', name: 'Hero', stack: 1000);
      final villain = Player(id: 'villain', name: 'Villain', stack: 1000);
      final state = GameState(
        players: [hero, villain],
        dealerIndex: 0,
        smallBlind: 10,
        bigBlind: 20,
      );
      final engine = GameEngine(state);
      // 构造牌堆：让 hero 拿到 AA，villain 拿到 22，公共牌无干扰。
      // Deck.draw() 从末尾抽牌，故列表顺序与抽出顺序相反。
      // 抽出顺序：villain 2♣, hero A♠, villain 2♦, hero A♥, flop K♣ Q♦ 9♥, turn 8♠, river 3♣
      final deck = Deck.from([
        Card(Rank.three, Suit.clubs), // river
        Card(Rank.eight, Suit.spades), // turn
        Card(Rank.nine, Suit.hearts), // flop
        Card(Rank.queen, Suit.diamonds), // flop
        Card(Rank.king, Suit.clubs), // flop
        Card(Rank.ace, Suit.hearts), // hero hole 2
        Card(Rank.two, Suit.diamonds), // villain hole 2
        Card(Rank.ace, Suit.spades), // hero hole 1
        Card(Rank.two, Suit.clubs), // villain hole 1
      ]);
      engine.startHandLocal(deck);

      // preflop: hero(SB) 先动，call 到 20
      expect(state.currentPlayer.id, 'hero');
      engine.applyAction(Action.call('hero'));
      // villain(BB) check
      expect(state.currentPlayer.id, 'villain');
      engine.applyAction(Action.check('villain'));
      expect(state.phase, Phase.flop);

      // flop: heads-up postflop BB 先动 -> villain
      engine.applyAction(Action.check('villain'));
      engine.applyAction(Action.check('hero'));
      expect(state.phase, Phase.turn);

      engine.applyAction(Action.check('villain'));
      engine.applyAction(Action.check('hero'));
      expect(state.phase, Phase.river);

      engine.applyAction(Action.check('villain'));
      engine.applyAction(Action.check('hero'));
      expect(state.phase, Phase.handOver);

      // hero AA 击败 villain 22，赢下 40 的底池（净 +20）。
      expect(hero.stack, 1020);
      expect(villain.stack, 980);
      expect(state.pot, 0);
    });

    test('fold awards pot to last standing without showdown', () {
      final hero = Player(id: 'hero', name: 'Hero', stack: 1000);
      final villain = Player(id: 'villain', name: 'Villain', stack: 1000);
      final state = GameState(
        players: [hero, villain],
        dealerIndex: 0,
        smallBlind: 10,
        bigBlind: 20,
      );
      final engine = GameEngine(state);
      engine.startHandLocal(Deck.fresh()..shuffle());

      engine.applyAction(Action.call('hero')); // hero calls 20
      engine.applyAction(Action.raise('villain', 60)); // villain raises to 60
      engine.applyAction(Action.fold('hero')); // hero folds

      expect(state.phase, Phase.handOver);
      // villain 投入 60，hero 投入 20，底池 80 归 villain。
      expect(villain.stack, 1020);
      expect(hero.stack, 980);
    });
  });
}
