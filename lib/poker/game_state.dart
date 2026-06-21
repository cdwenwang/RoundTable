import 'card.dart';

/// 一手牌的阶段。
enum Phase { preflop, flop, turn, river, showdown, handOver }

/// 玩家可执行的动作类型。`raise` 的金额为「加注到的总额」（raise-to）。
enum ActType { fold, check, call, raise }

class Action {
  final String playerId;
  final ActType type;

  /// 仅 [ActType.raise] 使用：加注到的目标总额（本轮该玩家的累计下注）。
  /// 例如当前最高下注 100，玩家 raise to 300 表示再投入 200。
  final int amount;

  const Action.fold(this.playerId)
      : type = ActType.fold,
        amount = 0;
  const Action.check(this.playerId)
      : type = ActType.check,
        amount = 0;
  const Action.call(this.playerId)
      : type = ActType.call,
        amount = 0;
  const Action.raise(this.playerId, this.amount) : type = ActType.raise;
}

class Player {
  final String id;
  String name;
  int stack;

  List<Card> holeCards;
  int bet; // 本轮已下注
  int totalBet; // 本手累计下注（用于边池）
  bool folded;
  bool allIn;
  bool hasActedThisRound;

  Player({
    required this.id,
    required this.name,
    required this.stack,
    List<Card>? holeCards,
    this.bet = 0,
    this.totalBet = 0,
    this.folded = false,
    this.allIn = false,
    this.hasActedThisRound = false,
  }) : holeCards = holeCards ?? [];

  bool get isInHand => !folded;
  bool get canAct => !folded && !allIn && stack > 0;

  void resetForHand() {
    holeCards = [];
    bet = 0;
    totalBet = 0;
    folded = false;
    allIn = false;
    hasActedThisRound = false;
  }

  void resetForRound() {
    bet = 0;
    hasActedThisRound = false;
  }

  /// 下注 [amount] 筹码（从 stack 扣除，加入 bet/totalBet），返回实际投入。
  int betChips(int amount) {
    final actual = amount > stack ? stack : amount;
    stack -= actual;
    bet += actual;
    totalBet += actual;
    if (stack == 0) allIn = true;
    return actual;
  }

  @override
  String toString() => '$name(stack=$stack, bet=$bet, folded=$folded, allIn=$allIn)';
}

/// 完整的一手牌状态。由 [GameEngine] 推进。
class GameState {
  final List<Player> players;
  int dealerIndex;
  final int smallBlind;
  final int bigBlind;

  List<Card> community;
  Phase phase;

  int currentPlayerIndex;
  int currentBet; // 本轮最高下注额
  int minRaise; // 最小加注增量

  GameState({
    required this.players,
    required this.dealerIndex,
    required this.smallBlind,
    required this.bigBlind,
    List<Card>? community,
    this.phase = Phase.handOver,
    int? currentPlayerIndex,
    this.currentBet = 0,
    this.minRaise = 0,
  })  : community = community ?? [],
        currentPlayerIndex = currentPlayerIndex ?? 0;

  Player get currentPlayer => players[currentPlayerIndex];
  int get pot => players.fold(0, (s, p) => s + p.totalBet);
  List<Player> get inHandPlayers => players.where((p) => p.isInHand).toList();
  bool get onlyOneInHand => inHandPlayers.length == 1;

  /// 第一个可行动的玩家索引，从 [from]（含）顺时针找。
  int firstActingFrom(int from) {
    var i = from % players.length;
    for (var n = 0; n < players.length; n++) {
      if (players[i].canAct) return i;
      i = (i + 1) % players.length;
    }
    return -1;
  }
}
