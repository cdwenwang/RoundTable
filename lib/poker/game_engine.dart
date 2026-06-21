import 'deck.dart';
import 'betting.dart';
import 'game_state.dart';
import 'hand_evaluator.dart';

/// 推进 [GameState] 的德州扑克引擎。
///
/// 单机模式：调用 [startHandLocal] 用明文 [Deck] 发牌，再循环 [applyAction]。
/// 联机模式：心智扑克协议负责发牌（直接写入玩家底牌/公共牌），复用
/// [applyAction] / [resolveShowdown] 的下注与结算逻辑。
class GameEngine {
  final GameState state;
  Deck? _deck;

  GameEngine(this.state);

  /// 单机开局：重置、发底牌、下盲注，进入 preflop。
  void startHandLocal(Deck deck) {
    _deck = deck;
    for (final p in state.players) {
      p.resetForHand();
    }
    state.community = [];

    // 发两张底牌，从庄家下家开始，每人一张，发两圈。
    for (var round = 0; round < 2; round++) {
      for (var i = 1; i <= state.players.length; i++) {
        final idx = (state.dealerIndex + i) % state.players.length;
        state.players[idx].holeCards.add(deck.draw());
      }
    }

    _postBlinds();
    state.phase = Phase.preflop;
    _beginBettingRound();
  }

  void _postBlinds() {
    final n = state.players.length;
    if (n == 2) {
      // heads-up: 庄家是 SB，先行动。
      state.players[state.dealerIndex].betChips(state.smallBlind);
      state.players[(state.dealerIndex + 1) % n].betChips(state.bigBlind);
    } else {
      state.players[(state.dealerIndex + 1) % n].betChips(state.smallBlind);
      state.players[(state.dealerIndex + 2) % n].betChips(state.bigBlind);
    }
    state.currentBet = state.bigBlind;
    state.minRaise = state.bigBlind;
  }

  /// 设置本轮起始行动者。
  /// - preflop：2 人桌庄家(SB)先动；其余桌 UTG（BB 下家）先动。
  /// - 其他 street：庄家下家第一个可行动者先动。
  void _beginBettingRound() {
    final n = state.players.length;
    final start = state.phase == Phase.preflop
        ? (n == 2 ? state.dealerIndex : (state.dealerIndex + 3) % n)
        : (state.dealerIndex + 1) % n;
    final idx = state.firstActingFrom(start);
    state.currentPlayerIndex = idx < 0 ? 0 : idx % n;
  }

  /// 应用一个动作。返回是否因此进入摊牌/结束。
  void applyAction(Action action) {
    final p = state.currentPlayer;
    if (p.id != action.playerId) {
      throw StateError('Not ${action.playerId}\'s turn (current=${p.id})');
    }

    switch (action.type) {
      case ActType.fold:
        p.folded = true;
        break;
      case ActType.check:
        break;
      case ActType.call:
        final toCall = state.currentBet - p.bet;
        if (toCall > 0) p.betChips(toCall);
        break;
      case ActType.raise:
        final raiseTo = action.amount;
        if (raiseTo <= state.currentBet) {
          throw StateError('Raise must exceed current bet ${state.currentBet}');
        }
        final delta = raiseTo - p.bet;
        p.betChips(delta);
        final raiseSize = raiseTo - state.currentBet;
        state.currentBet = p.bet;
        if (raiseSize > state.minRaise) state.minRaise = raiseSize;
        // 加注重置其他可行动玩家的行动权。
        for (final other in state.players) {
          if (!identical(other, p) && other.canAct) {
            other.hasActedThisRound = false;
          }
        }
        break;
    }
    p.hasActedThisRound = true;

    if (state.onlyOneInHand) {
      awardToLastStanding();
      return;
    }
    if (_isRoundComplete()) {
      _advancePhase();
    } else {
      _moveToNextActor();
    }
  }

  bool _isRoundComplete() {
    final canAct = state.players.where((p) => p.canAct).toList();
    if (canAct.isEmpty) return true;
    return canAct.every((p) => p.hasActedThisRound && (p.bet == state.currentBet));
  }

  void _moveToNextActor() {
    final n = state.players.length;
    var i = (state.currentPlayerIndex + 1) % n;
    for (var k = 0; k < n; k++) {
      if (state.players[i].canAct) {
        state.currentPlayerIndex = i;
        return;
      }
      i = (i + 1) % n;
    }
  }

  void _advancePhase() {
    for (final p in state.players) {
      p.resetForRound();
    }
    state.currentBet = 0;
    state.minRaise = state.bigBlind;

    switch (state.phase) {
      case Phase.preflop:
        state.phase = Phase.flop;
        _dealStreet(3);
        break;
      case Phase.flop:
        state.phase = Phase.turn;
        _dealStreet(1);
        break;
      case Phase.turn:
        state.phase = Phase.river;
        _dealStreet(1);
        break;
      case Phase.river:
        resolveShowdown();
        return;
      default:
        return;
    }

    if (state.onlyOneInHand) {
      awardToLastStanding();
      return;
    }
    // 若无人可行动（全员 all-in），继续发到摊牌。
    if (state.players.where((p) => p.canAct).isEmpty) {
      _advancePhase();
      return;
    }
    _beginBettingRound();
  }

  void _dealStreet(int count) {
    final deck = _deck;
    if (deck == null) {
      // 联机模式由协议直接写入 community，这里跳过。
      return;
    }
    state.community.addAll(deck.drawMany(count));
  }

  /// 仅剩一人时，该玩家赢得全部底池。
  void awardToLastStanding() {
    final winner = state.inHandPlayers.single;
    winner.stack += state.pot;
    for (final p in state.players) {
      p.bet = 0;
      p.totalBet = 0;
    }
    state.phase = Phase.handOver;
  }

  /// 摊牌结算：计算主池/边池，按最佳手牌分配。
  void resolveShowdown() {
    state.phase = Phase.showdown;
    final pots = computePots(state.players);
    for (final pot in pots) {
      if (pot.eligiblePlayerIds.isEmpty) {
        // 罕见边角：无资格者，均分给所有未弃牌玩家。
        final inHand = state.inHandPlayers;
        if (inHand.isEmpty) continue;
        final share = pot.amount ~/ inHand.length;
        for (final p in inHand) {
          p.stack += share;
        }
        inHand.first.stack += pot.amount - share * inHand.length;
        continue;
      }

      final eligible = state.players.where((p) => pot.eligiblePlayerIds.contains(p.id)).toList();
      final evaluated = eligible.map((p) {
        final r = bestHand([...p.holeCards, ...state.community]);
        return (player: p, result: r);
      }).toList()
        ..sort((a, b) => b.result.compareTo(a.result));

      final best = evaluated.first.result;
      final winners = evaluated.where((e) => e.result.compareTo(best) == 0).toList();
      final share = pot.amount ~/ winners.length;
      for (final w in winners) {
        w.player.stack += share;
      }
      winners.first.player.stack += pot.amount - share * winners.length;
    }

    for (final p in state.players) {
      p.bet = 0;
      p.totalBet = 0;
    }
    state.phase = Phase.handOver;
  }

  /// 移动庄家按钮到下一家（开局新一手前调用）。
  void moveButton() {
    state.dealerIndex = (state.dealerIndex + 1) % state.players.length;
  }
}
