import 'dart:math';

import '../poker/betting.dart';
import '../poker/card.dart';
import '../poker/game_state.dart';
import '../poker/hand_evaluator.dart';

/// 单机机器人决策：基于粗略牌力 + 底池赔率 + 随机性。
///
/// 非最优策略，仅供单机娱乐；联机对局中不参与（联机都是真人，发牌走心智扑克）。
class Bot {
  final String playerId;
  final Random rng;

  Bot(this.playerId, [Random? rng]) : rng = rng ?? Random();

  Action decide(GameState state, LegalActions legal) {
    final p = state.players.firstWhere((e) => e.id == playerId);
    final strength = _strength(p.holeCards, state.community);
    final toCall = legal.callAmount;
    final pot = state.pot;
    final potOdds = toCall == 0 ? 0.0 : toCall / (pot + toCall);

    // 强牌：有一定概率加注。
    if (strength > 0.75 && legal.canRaise && rng.nextDouble() < 0.5) {
      return Action.raise(playerId, _raiseTo(state, legal, p, strength, 0.3));
    }
    // 免费过牌时，偶诈唬加注。
    if (toCall == 0) {
      if (strength > 0.6 && legal.canRaise && rng.nextDouble() < 0.25) {
        return Action.raise(playerId, _raiseTo(state, legal, p, strength, 0.12));
      }
      return Action.check(playerId);
    }
    // 需要跟注：牌力不及底池赔率则弃牌。
    if (strength < potOdds - 0.05) {
      return Action.fold(playerId);
    }
    if (legal.canCall) return Action.call(playerId);
    return Action.check(playerId);
  }

  int _raiseTo(GameState state, LegalActions legal, Player p, double strength, double frac) {
    var amount = state.currentBet + state.minRaise + (p.stack * strength * frac).toInt();
    if (amount < legal.minRaiseTo) amount = legal.minRaiseTo;
    if (amount > legal.maxRaiseTo) amount = legal.maxRaiseTo;
    return amount;
  }

  double _strength(List<Card> hole, List<Card> community) {
    if (community.isEmpty) return _preflopStrength(hole);
    final r = bestHand([...hole, ...community]);
    // 类别 0..8 映射到 ~0.2..1.0。
    return (r.category.index / 8) * 0.8 + 0.2;
  }

  double _preflopStrength(List<Card> hole) {
    if (hole.length < 2) return 0.3;
    final v1 = hole[0].value, v2 = hole[1].value;
    final hi = v1 > v2 ? v1 : v2;
    final lo = v1 > v2 ? v2 : v1;
    var s = (hi - 2) / 12 * 0.5;
    if (v1 == v2) s += 0.35; // 对子
    if (hole[0].suit == hole[1].suit) s += 0.08; // 同花
    if (hi - lo == 1) s += 0.05; // 连张
    return s.clamp(0.0, 1.0);
  }
}
