import 'game_state.dart';

/// 一个底池（可能是主池或边池）。`eligiblePlayerIds` 为有资格争夺该池的玩家。
class Pot {
  final int amount;
  final List<String> eligiblePlayerIds;
  const Pot(this.amount, this.eligiblePlayerIds);

  @override
  String toString() => 'Pot($amount, eligible=$eligiblePlayerIds)';
}

/// 根据各玩家本手的 [Player.totalBet] 计算主池与边池。
///
/// 已弃牌玩家的筹码仍按其贡献计入相应层级的池，但他们不在 `eligiblePlayerIds` 中，
/// 无法争夺该池。
List<Pot> computePots(List<Player> players) {
  final contributions = {
    for (final p in players) p.id: p.totalBet,
  };
  final levels = contributions.values.where((v) => v > 0).toSet().toList()..sort();
  if (levels.isEmpty) return const [];

  final pots = <Pot>[];
  var prev = 0;
  for (final level in levels) {
    final layer = level - prev;
    var amount = 0;
    final eligible = <String>[];
    for (final p in players) {
      if (contributions[p.id]! >= level) {
        amount += layer;
        if (p.isInHand) eligible.add(p.id);
      }
    }
    if (amount > 0) pots.add(Pot(amount, eligible));
    prev = level;
  }
  return pots;
}

/// 当前玩家可执行的动作集合（用于 UI 启用/禁用按钮与 AI 决策）。
class LegalActions {
  final bool canFold;
  final bool canCheck;
  final bool canCall;
  final int callAmount; // 跟注还需补的筹码
  final bool canRaise;
  final int minRaiseTo; // 最小加注到的总额
  final int maxRaiseTo; // all-in 加注到的总额

  const LegalActions({
    required this.canFold,
    required this.canCheck,
    required this.canCall,
    required this.callAmount,
    required this.canRaise,
    required this.minRaiseTo,
    required this.maxRaiseTo,
  });
}

/// 计算 [state.currentPlayer] 的合法动作。
LegalActions legalActionsFor(GameState state) {
  final p = state.currentPlayer;
  final toCall = state.currentBet - p.bet;
  final canAct = p.canAct;

  final canFold = canAct;
  final canCheck = canAct && toCall <= 0;
  final callAmount = toCall < 0 ? 0 : toCall;
  final canCall = canAct && toCall > 0;

  // 加注：最小加注到 currentBet + minRaise（且不超过 all-in 总额）。
  final minRaiseTo = state.currentBet + state.minRaise;
  final maxRaiseTo = p.bet + p.stack; // 全部筹码加注到
  // 只要还能投入超过当前最高下注即可加注（含 all-in 不足最小加注的情况）。
  final canRaise = canAct && maxRaiseTo > state.currentBet;

  return LegalActions(
    canFold: canFold,
    canCheck: canCheck,
    canCall: canCall,
    callAmount: callAmount > p.stack ? p.stack : callAmount,
    canRaise: canRaise,
    minRaiseTo: minRaiseTo,
    maxRaiseTo: maxRaiseTo,
  );
}
