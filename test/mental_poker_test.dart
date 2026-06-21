import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/crypto/mental_poker.dart';
import 'package:round_table/poker/card.dart';

void main() {
  final params = MentalPokerParams.dev;
  // 固定种子保证可复现。
  Random rng(int seed) => Random(seed);

  group('MentalPoker protocol', () {
    test('shuffle then deal all 52 cards yields a full unique deck', () {
      final parts = [
        MentalPokerParticipant.random('A', params, rng(1)),
        MentalPokerParticipant.random('B', params, rng(2)),
      ];
      final mp = MentalPoker(params, parts, rng(3));
      mp.shuffle();

      final dealt = <Card>{};
      while (mp.remaining > 0) {
        dealt.add(mp.dealHoleTo('A'));
      }
      expect(dealt.length, 52);
      expect(dealt.toSet().length, 52);
    });

    test('2-player: hole cards + community all distinct', () {
      final parts = [
        MentalPokerParticipant.random('A', params, rng(10)),
        MentalPokerParticipant.random('B', params, rng(20)),
      ];
      final mp = MentalPoker(params, parts, rng(30));
      mp.shuffle();

      final a1 = mp.dealHoleTo('A');
      final b1 = mp.dealHoleTo('B');
      final a2 = mp.dealHoleTo('A');
      final b2 = mp.dealHoleTo('B');
      final flop1 = mp.revealCommunity();
      final flop2 = mp.revealCommunity();
      final flop3 = mp.revealCommunity();
      final turn = mp.revealCommunity();
      final river = mp.revealCommunity();

      final all = [a1, a2, b1, b2, flop1, flop2, flop3, turn, river];
      expect(all.toSet().length, 9);
      expect(mp.community.length, 5);
      expect(mp.holeCards['A'], [a1, a2]);
      expect(mp.holeCards['B'], [b1, b2]);
    });

    test('3-player and 4-player round trips are consistent', () {
      for (final n in [3, 4]) {
        final parts = [
          for (var i = 0; i < n; i++)
            MentalPokerParticipant.random('P$i', params, rng(100 + i)),
        ];
        final mp = MentalPoker(params, parts, rng(200 + n));
        mp.shuffle();

        final dealt = <Card>{};
        for (var r = 0; r < 2; r++) {
          for (var i = 0; i < n; i++) {
            dealt.add(mp.dealHoleTo('P$i'));
          }
        }
        for (var i = 0; i < 5; i++) {
          dealt.add(mp.revealCommunity());
        }
        expect(dealt.length, 2 * n + 5);
        expect(dealt.toSet().length, 2 * n + 5);
      }
    });

    test('commutativity: decrypt order does not matter', () {
      final a = MentalPokerParticipant.random('A', params, rng(1));
      final b = MentalPokerParticipant.random('B', params, rng(2));
      final c = MentalPokerParticipant.random('C', params, rng(3));

      final original = params.g.modPow(BigInt.from(7), params.p);
      var enc = a.encrypt(original);
      enc = b.encrypt(enc);
      enc = c.encrypt(enc);

      final order1 = c.decryptLayer(b.decryptLayer(a.decryptLayer(enc)));
      final order2 = a.decryptLayer(c.decryptLayer(b.decryptLayer(enc)));
      expect(order1, original);
      expect(order2, original);
    });

    test('privacy: a single participant alone cannot recover the plaintext', () {
      // 核心隐私性质：双方加密后，仅靠一方的密钥无法还原明文。
      // g^(i·kA·kB) 经 A 单独去层得 g^(i·kB)，因 kB≠1 故 ≠ g^i（明文）。
      // 该性质对任意素数都成立；"中间值不撞上任意牌值"仅在大素数下才概率可忽略
      //（dev 小素数 p=167 下会有碰撞，故不在此断言）。
      final a = MentalPokerParticipant.random('A', params, rng(1));
      final b = MentalPokerParticipant.random('B', params, rng(2));

      final plain = params.g.modPow(BigInt.one, params.p); // g^1，即第 1 张牌
      final enc = b.encrypt(a.encrypt(plain)); // g^(kA·kB)

      final aAlone = a.decryptLayer(enc); // g^(kB)
      expect(aAlone, isNot(plain));
    });
  });
}
