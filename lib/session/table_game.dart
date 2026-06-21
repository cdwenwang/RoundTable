import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/bot.dart';
import '../poker/betting.dart';
import '../poker/card.dart';
import '../poker/deck.dart';
import '../poker/game_engine.dart';
import '../poker/game_state.dart';
import '../poker/hand_evaluator.dart';

/// 一个座位：可能为空（null），或坐着玩家/机器人。
class Seat {
  final int index;
  final Player player;
  final bool isBot;
  int totalBuyIn;
  bool sittingOut;

  Seat({
    required this.index,
    required this.player,
    required this.isBot,
    required this.totalBuyIn,
    this.sittingOut = false,
  });

  int get stack => player.stack;
  int get net => player.stack - totalBuyIn;
  bool get isActive => !sittingOut && player.stack > 0;
}

class Settlement {
  final String name;
  final int net;
  final bool isBot;
  const Settlement({required this.name, required this.net, required this.isBot});
}

/// 预选动作（玩家在非自己回合时提前勾选）。
class PreAction {
  final String type; // fold / check / call / raise
  final int? amount;
  const PreAction(this.type, [this.amount]);
}

const int kTurnSeconds = 30;

/// 持久牌桌控制器。
class TableGame extends ChangeNotifier {
  final int capacity;
  final int smallBlind;
  final int bigBlind;
  final int defaultBuyIn;
  final Random rng;

  final List<Seat?> seats;
  int handCount = 0;
  GameState? state;
  GameEngine? engine;
  bool handInProgress = false;
  String? lastResult;
  String? notice;
  bool gameOver = false;
  bool autoAdvancing = false;
  String? hostId; // 当前房主 id

  // 摊牌赢家信息
  Set<String> winnerIds = {};
  Map<String, HandResult> winnerHands = {};
  Map<String, List<Card>> winnerCards = {}; // 赢家最佳5张牌组合
  int revealIdx = -1; // 逐一展示索引（-1=未开始）
  List<String> get revealList => _revealList;

  int turnId = 0; // 每次轮到新玩家递增，驱动倒计时圆环
  PreAction? heroPre;

  // 玩家最近操作记录（供 UI 动效与声音）
  final Map<String, String> lastActions = {}; // playerId → fold/check/call/raise
  final Map<String, DateTime> actionTimes = {};

  final Map<String, Bot> _bots = {};
  Timer? _turnTimer;
  Timer? _autoTimer;
  bool _disposed = false;

  TableGame({
    required this.capacity,
    required this.smallBlind,
    required this.bigBlind,
    required this.defaultBuyIn,
    Random? rng,
  })  : rng = rng ?? Random(),
        seats = List<Seat?>.filled(capacity, null) {
    _sit(0, 'hero', '你', defaultBuyIn, isBot: false);
    hostId = 'hero';
  }

  // --- 座位 ---

  void _sit(int idx, String id, String name, int buyIn, {required bool isBot}) {
    final p = Player(id: id, name: name, stack: buyIn);
    seats[idx] = Seat(index: idx, player: p, isBot: isBot, totalBuyIn: buyIn);
    if (isBot) _bots[id] = Bot(id, Random());
  }

  void addBot(int idx) {
    if (handInProgress) return;
    if (idx < 0 || idx >= capacity || seats[idx] != null) return;
    _sit(idx, 'bot$idx', '机器人 ${idx + 1}', defaultBuyIn, isBot: true);
    notifyListeners();
  }

  void removeSeat(int idx) {
    if (handInProgress || idx == 0) return;
    seats[idx] = null;
    notifyListeners();
  }

  void rebuy(int amount) {
    final hero = seats[0]!;
    hero.player.stack += amount;
    hero.totalBuyIn += amount;
    hero.sittingOut = false;
    notice = null;
    notifyListeners();
  }

  /// 玩家离开座位（如房主离开）。房主离开则转交场上号最小的活人，无活人则解散。
  void leaveTable() {
    _cancelTimers();
    gameOver = true;
    notifyListeners();
  }

  Seat get hero => seats[0]!;
  bool get isHeroTurn =>
      handInProgress && state != null && state!.phase != Phase.handOver && state!.currentPlayer.id == 'hero';
  List<Seat> get activeSeats =>
      seats.whereType<Seat>().where((s) => s.isActive).toList();

  // --- 预选动作 ---

  void setHeroPre(String type, [int? amount]) {
    heroPre = PreAction(type, amount);
    notifyListeners();
  }

  void clearHeroPre() {
    heroPre = null;
    notifyListeners();
  }

  /// 立即执行（确认按钮）。
  void executeHeroNow(String type, [int? amount]) {
    if (!isHeroTurn) return;
    _applyHeroAction(_actionOf(type, amount));
  }

  bool _preValid() {
    final pre = heroPre;
    if (pre == null || state == null) return false;
    final legal = legalActionsFor(state!);
    switch (pre.type) {
      case 'fold':
        return true;
      case 'check':
        return legal.canCheck;
      case 'call':
        return legal.canCall;
      case 'raise':
        return legal.canRaise &&
            pre.amount != null &&
            pre.amount! >= legal.minRaiseTo &&
            pre.amount! <= legal.maxRaiseTo;
    }
    return false;
  }

  Action _actionOf(String type, int? amount) {
    switch (type) {
      case 'fold':
        return Action.fold('hero');
      case 'check':
        return Action.check('hero');
      case 'call':
        return Action.call('hero');
      case 'raise':
      default:
        return Action.raise('hero', amount ?? 0);
    }
  }

  // --- 牌局 ---

  void startHand() {
    if (handInProgress || gameOver) return;
    final active = activeSeats;
    if (active.length < 2) {
      notice = '至少需要 2 名有筹码的玩家';
      notifyListeners();
      return;
    }
    handCount++;
    final players = active.map((s) => s.player).toList();
    final dealerIndex = (handCount - 1) % players.length;
    state = GameState(
      players: players,
      dealerIndex: dealerIndex,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
    );
    engine = GameEngine(state!);
    engine!.startHandLocal(Deck.fresh()..shuffle(rng));
    handInProgress = true;
    lastResult = null;
    notice = null;
    heroPre = null;
    lastActions.clear();
    actionTimes.clear();
    _drive();
  }

  void _drive() {
    if (_disposed || !handInProgress || state == null) return;
    final cur = state!.currentPlayer;
    _startTurn();
    notifyListeners();
    if (cur.id == 'hero') {
      if (_preValid()) {
        final pre = heroPre!;
        heroPre = null;
        Timer(const Duration(seconds: 5), () { if (heroPre == null) _applyHeroAction(_actionOf(pre.type, pre.amount)); });
      }
      // 否则等待玩家操作或 30s 超时
    } else if (_bots.containsKey(cur.id)) {
      Timer(const Duration(milliseconds: 650), _botAct);
    }
  }

  void _startTurn() {
    _turnTimer?.cancel();
    turnId++;
    _turnTimer = Timer(const Duration(seconds: kTurnSeconds), _timeout);
  }

  void _timeout() {
    if (_disposed || !handInProgress || state == null) return;
    final cur = state!.currentPlayer;
    final legal = legalActionsFor(state!);
    final Action a;
    if (cur.id == 'hero') {
      // 需跟注→弃牌；可过牌→让牌
      a = legal.canCall ? Action.fold('hero') : Action.check('hero');
    } else {
      a = _bots[cur.id]!.decide(state!, legal);
    }
    _recordAction(a);
    engine!.applyAction(a);
    notifyListeners();
    if (state!.phase == Phase.handOver) {
      _endHand();
      return;
    }
    _drive();
  }

  void _botAct() {
    if (_disposed || !handInProgress || state == null) return;
    final cur = state!.currentPlayer;
    if (!_bots.containsKey(cur.id)) return;
    final legal = legalActionsFor(state!);
    final action = _bots[cur.id]!.decide(state!, legal);
    _recordAction(action);
    engine!.applyAction(action);
    notifyListeners();
    if (state!.phase == Phase.handOver) {
      _endHand();
      return;
    }
    _drive();
  }

  void _applyHeroAction(Action a) {
    if (!isHeroTurn) return;
    _recordAction(a);
    try {
      engine!.applyAction(a);
    } catch (e) {
      notice = '操作无效，请重试';
      notifyListeners();
      return;
    }
    notifyListeners();
    if (state!.phase == Phase.handOver) {
      _endHand();
      return;
    }
    _drive();
  }

  void _recordAction(Action a) {
    final type = switch (a.type) {
      ActType.fold => 'fold',
      ActType.check => 'check',
      ActType.call => 'call',
      ActType.raise => 'raise',
    };
    lastActions[a.playerId] = type;
    actionTimes[a.playerId] = DateTime.now();
  }

  LegalActions legalForHero() {
    final st = state;
    if (st == null) throw StateError('No hand in progress');
    final hero = st.players.firstWhere((p) => p.id == 'hero');
    return _legalActionsForPlayer(st, hero);
  }

  LegalActions _legalActionsForPlayer(GameState st, Player p) {
    final toCall = st.currentBet - p.bet;
    final canAct = p.canAct;
    final canFold = canAct;
    final canCheck = canAct && toCall <= 0;
    final callAmount = toCall < 0 ? 0 : toCall;
    final canCall = canAct && toCall > 0;
    final minRaiseTo = st.currentBet + st.minRaise;
    final maxRaiseTo = p.bet + p.stack;
    final canRaise = canAct && maxRaiseTo > st.currentBet;
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

  void _endHand() {
    _turnTimer?.cancel();
    handInProgress = false;
    for (final s in seats.whereType<Seat>()) {
      if (s.player.stack <= 0) s.sittingOut = true;
    }
    _recordResult(); // 内部启动揭示流程→_finishReveal 管理后续
    heroPre = null;
    notifyListeners();
  }

  void _recordResult() {
    winnerIds.clear();
    winnerHands.clear();
    final st = state;
    if (st == null || st.players.isEmpty) return;
    final inHand = st.players.where((p) => !p.folded).toList();
    if (inHand.length == 1) {
      // 全部弃牌赢：不亮牌，直接推进
      lastResult = '${inHand.first.name} 获胜（其余弃牌）';
      _afterHandDone();
      return;
    }
    // 摊牌：赢家亮牌
    winnerCards.clear();
    final evaluated = inHand
        .map((p) {
          final r = bestHandWithCards([...p.holeCards, ...st.community]);
          return (p, r.result, r.cards);
        })
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final best = evaluated.first.$2;
    for (final e in evaluated) {
      if (e.$2.compareTo(best) == 0) {
        winnerIds.add(e.$1.id);
        winnerHands[e.$1.id] = e.$2;
        winnerCards[e.$1.id] = e.$3;
      }
    }
    final names = evaluated.where((e) => e.$2.compareTo(best) == 0).map((e) => e.$1.name).join('、');
    lastResult = '$names 以 ${_categoryName(best.category)} 获胜';
    // 逐一展示赢家（按离庄家顺时针位置从小到大）
    _startReveal();
  }

  void _afterHandDone() {
    // 不需要亮牌 → 直接自动下一手
    if (activeSeats.length < 2) {
      gameOver = true;
      notifyListeners();
      return;
    }
    if (hero.sittingOut) {
      notice = '你的筹码用完，补码后继续';
      notifyListeners();
      return;
    }
    autoAdvancing = true;
    notifyListeners();
    _autoTimer = Timer(const Duration(milliseconds: 2500), () {
      autoAdvancing = false;
      if (!_disposed) startHand();
    });
  }

  bool get canHeroRaise {
    final st = state;
    if (st == null || !st.players.any((p) => p.id == 'hero')) return false;
    return legalForHero().canRaise;
  }

  String? handCategoryFor(Seat s) {
    final h = winnerHands[s.player.id];
    if (h == null) return null;
    return _categoryName(h.category);
  }

  /// 摊牌时仅赢家亮出底牌。
  bool shouldReveal(Seat s) {
    final st = state;
    if (st == null || st.phase != Phase.handOver) return false;
    if (revealIdx < 0) return false;
    return winnerIds.contains(s.player.id);
  }

  void _startReveal() {
    _revealTimer?.cancel();
    if (winnerIds.isEmpty) {
      _finishReveal();
      return;
    }
    // 按相对庄家位置从小到大排序
    final st = state!;
    final playerIds = st.players.map((p) => p.id).toList();
    final dealerIdx = st.dealerIndex;
    final sorted = winnerIds.toList()
      ..sort((a, b) {
        final aIdx = playerIds.indexOf(a);
        final bIdx = playerIds.indexOf(b);
        if (aIdx < 0 || bIdx < 0) return 0;
        final aDist = (aIdx - dealerIdx + playerIds.length) % playerIds.length;
        final bDist = (bIdx - dealerIdx + playerIds.length) % playerIds.length;
        return aDist.compareTo(bDist);
      });
    revealIdx = 0;
    _revealList = sorted;
    notifyListeners();
    _revealTimer = Timer(const Duration(seconds: 2), _nextReveal);
  }

  List<String> _revealList = [];
  Timer? _revealTimer;

  void _nextReveal() {
    revealIdx++;
    notifyListeners();
    if (revealIdx < _revealList.length) {
      _revealTimer = Timer(const Duration(seconds: 2), _nextReveal);
    } else {
      // 全部展示完毕
      _revealTimer = Timer(const Duration(seconds: 2), _finishReveal);
    }
  }

  void _finishReveal() {
    revealIdx = -1;
    _revealList.clear();
    _afterHandDone();
  }

  List<Settlement> settle() =>
      seats.whereType<Seat>().map((s) => Settlement(name: s.player.name, net: s.net, isBot: s.isBot)).toList();

  static String _categoryName(HandCategory c) => switch (c) {
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

  void _cancelTimers() {
    _turnTimer?.cancel();
    _autoTimer?.cancel();
    _revealTimer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
