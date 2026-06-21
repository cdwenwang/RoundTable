import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../poker/betting.dart';
import '../../session/table_game.dart';
import '../widgets/playing_card.dart';
import '../widgets/playing_card.dart';

class TableScreen extends StatefulWidget {
  final int seats;
  final String sceneLabel;
  final int buyIn;
  final int smallBlind;
  final int bigBlind;

  const TableScreen({
    super.key,
    required this.seats,
    required this.sceneLabel,
    required this.buyIn,
    required this.smallBlind,
    required this.bigBlind,
  });

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> with SingleTickerProviderStateMixin {
  late final TableGame _game;
  final TextEditingController _chatCtrl = TextEditingController();
  final List<_Msg> _chat = [];
  late final AnimationController _turnCtrl;

  String? _sel; // 预选/当前选择：fold/check/call/raise
  int _raiseAmt = 0;
  int _rebuyAmount = 1000;
  int _lastTurnId = 0;

  @override
  void initState() {
    super.initState();
    _game = TableGame(
      capacity: widget.seats,
      smallBlind: widget.smallBlind,
      bigBlind: widget.bigBlind,
      defaultBuyIn: widget.buyIn,
    );
    _turnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: kTurnSeconds),
    );
    _game.addListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    if (_game.turnId != _lastTurnId) {
      _lastTurnId = _game.turnId;
      if (_game.handInProgress) {
        _turnCtrl.forward(from: 0);
      } else {
        _turnCtrl.reset();
      }
    }
    if (!_game.handInProgress) {
      _sel = null;
    }
    setState(() {});
  }

  void _sendChat(String text) {
    if (text.isEmpty) return;
    setState(() {
      _chat.add(_Msg.text('你', text));
      if (_chat.length > 8) _chat.removeAt(0);
    });
    _chatCtrl.clear();
  }

  void _sendVoice(int seconds) {
    setState(() {
      _chat.add(_Msg.voice('你', seconds));
      if (_chat.length > 8) _chat.removeAt(0);
    });
  }

  void _select(String type) {
    if (type == 'raise') {
      // 已在加注模式 → 确认加注；否则进入加注模式或设为预选
      if (_game.isHeroTurn && _sel == 'raise') {
        final legal = _game.legalForHero();
        _game.executeHeroNow('raise', _raiseAmt.clamp(legal.minRaiseTo, legal.maxRaiseTo));
        setState(() => _sel = null);
        return;
      }
      // 进入加注模式 / 预选
      setState(() {
        _sel = 'raise';
        final legal = _game.legalForHero();
        _raiseAmt = legal.minRaiseTo;
      });
      _game.setHeroPre('raise', _raiseAmt);
    } else {
      // 盖牌/让牌/跟注：自己回合立即执行，否则预选
      if (_game.isHeroTurn) {
        _game.executeHeroNow(type);
        setState(() => _sel = null);
      } else {
        setState(() => _sel = type);
        _game.setHeroPre(type);
      }
    }
  }

  void _setRaise(int v) {
    setState(() => _raiseAmt = v);
    _game.setHeroPre('raise', v);
  }

  @override
  void dispose() {
    _game.removeListener(_onChanged);
    _game.dispose();
    _turnCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('${widget.sceneLabel} · 第 ${_game.handCount} 手'),
        actions: [
          if (!_game.handInProgress)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _leave,
                  child: const Text('离开', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        color: const Color(0xFF0B6E4F),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _Ring(
                  game: _game,
                  chat: _chat,
                  turnAnim: _turnCtrl,
                  showSlider: _sel == 'raise',
                  raiseTo: _raiseAmt,
                  onRaiseChanged: _setRaise,
                ),
              ),
              _HeroHand(game: _game),
              _ActionBar(
                game: _game,
                sel: _sel,
                onSelect: _select,
                rebuyAmount: _rebuyAmount,
                onRebuyChanged: (v) => setState(() => _rebuyAmount = v),
                onStart: _game.startHand,
                onLeave: _leave,
              ),
              _ChatBar(controller: _chatCtrl, onSendText: _sendChat, onSendVoice: _sendVoice),
            ],
          ),
        ),
      ),
    );
  }

  void _leave() {
    if (_game.handInProgress) return;
    final settle = _game.settle();
    _game.leaveTable();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SettleDialog(settle: settle, onClose: () => Navigator.of(context).popUntil((r) => r.isFirst)),
    );
  }
}

class _Msg {
  final String sender;
  final String? text;
  final int? voiceSeconds;
  final bool isVoice;
  const _Msg.text(this.sender, this.text) : voiceSeconds = null, isVoice = false;
  const _Msg.voice(this.sender, this.voiceSeconds) : text = null, isVoice = true;
}

class _Ring extends StatelessWidget {
  final TableGame game;
  final List<_Msg> chat;
  final Animation<double> turnAnim;
  final bool showSlider;
  final int raiseTo;
  final ValueChanged<int> onRaiseChanged;

  const _Ring({
    required this.game,
    required this.chat,
    required this.turnAnim,
    required this.showSlider,
    required this.raiseTo,
    required this.onRaiseChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final W = c.maxWidth;
        final H = c.maxHeight;
        final positions = _layout(game.capacity, W, H);
        final currentId = (game.handInProgress && game.state != null) ? game.state!.currentPlayer.id : null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: W / 2 - 155, top: H / 2 - 60, child: _Center(game: game)),
            if (chat.isNotEmpty)
              Positioned(
                left: 8,
                bottom: 4,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 230),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final m in chat) _ChatBubble(msg: m)],
                  ),
                ),
              ),
            for (final p in positions)
              Positioned(
                left: p.dx,
                top: p.dy,
                child: _RingSeat(
                  number: p.number,
                  seat: game.seats[p.number - 1],
                  game: game,
                  isCurrent: currentId != null &&
                      game.seats[p.number - 1] != null &&
                      game.seats[p.number - 1]!.player.id == currentId,
                  turnAnim: turnAnim,
                ),
              ),
            if (showSlider && game.canHeroRaise)
              Positioned(
                right: 8,
                top: 40,
                bottom: 8,
                child: _RaiseSlider(game: game, value: raiseTo, onChanged: onRaiseChanged),
              ),
          ],
        );
      },
    );
  }
}

class _Position {
  final int number;
  final double dx;
  final double dy;
  const _Position(this.number, this.dx, this.dy);
}

List<_Position> _layout(int n, double W, double H) {
  const seatW = 74.0;
  const margin = 4.0;
  final leftX = margin;
  final rightX = W - seatW - margin;
  final centerX = W / 2 - seatW / 2;
  final topY = margin;
  final sideTopY = margin + 6;
  final sideBottomY = H * 0.62;
  final span = sideBottomY - sideTopY;

  final odd = n % 2 == 1;
  final l = odd ? (n - 1) ~/ 2 : n ~/ 2;
  final out = <_Position>[];

  double sideY(int j, int count) {
    if (count <= 1) return (sideTopY + sideBottomY) / 2;
    return sideTopY + (j - 1) * span / (count - 1);
  }

  for (var k = 1; k <= l; k++) {
    final j = l - k + 1;
    out.add(_Position(k, leftX, sideY(j, l)));
  }
  if (odd) {
    out.add(_Position(l + 1, centerX, topY));
  }
  final startRight = l + (odd ? 1 : 0) + 1;
  for (var idx = 0; idx < l; idx++) {
    final k = startRight + idx;
    out.add(_Position(k, rightX, sideY(idx + 1, l)));
  }
  return out;
}

class _RingSeat extends StatelessWidget {
  final int number;
  final Seat? seat;
  final TableGame game;
  final bool isCurrent;
  final Animation<double> turnAnim;

  const _RingSeat({
    required this.number,
    required this.seat,
    required this.game,
    required this.isCurrent,
    required this.turnAnim,
  });

  @override
  Widget build(BuildContext context) {
    final s = seat;
    final empty = s == null;
    final isHero = s != null && s.player.id == 'hero';
    final out = s != null && s.sittingOut;
    final reveal = s != null && game.shouldReveal(s);
    final canTap = !game.handInProgress && (empty || (!isHero));
    final bet = (!empty && game.handInProgress) ? s.player.bet : 0;

    return GestureDetector(
      onTap: canTap
          ? () {
              if (empty) {
                game.addBot(number - 1);
              } else if (!isHero) {
                game.removeSeat(s.index);
              }
            }
          : null,
      child: SizedBox(
        width: 74,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: (empty ? false : s.player.folded) ? 0.35 : 1.0,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 倒计时圆环（头像下层）
                if (isCurrent)
                  Positioned(
                    child: AnimatedBuilder(
                      animation: turnAnim,
                      builder: (_, __) => SizedBox(
                        width: 60, height: 60,
                        child: CustomPaint(painter: _TurnRingPainter(turnAnim.value)),
                      ),
                    ),
                  ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: empty ? Colors.white10 : isHero ? const Color(0xFF0B6E4F) : Colors.black38,
                    border: Border.all(
                      color: reveal ? Colors.yellow : isCurrent ? Colors.amber : isHero ? Colors.white : Colors.white24,
                      width: (reveal || isCurrent) ? 2.5 : 1,
                    ),
                  ),
                  child: Icon(
                    empty ? Icons.add : s.isBot ? Icons.smart_toy : Icons.person,
                    color: empty ? Colors.white38 : Colors.white,
                    size: 26,
                  ),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isHero ? Colors.amber : const Color(0xFF1A3A5C),
                      border: Border.all(color: Colors.white54, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Text('$number',
                        style: TextStyle(
                            color: isHero ? Colors.black : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                // 房主标识
                if (isHero)
                  Positioned(
                    left: -4,
                    bottom: -4,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      alignment: Alignment.center,
                      child: const Text('主', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // 庄家(D)标识
                if (_isDealer(s, game))
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      alignment: Alignment.center,
                      child: const Text('D', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // 小盲标识
                if (_isSB(s, game))
                  Positioned(
                    left: 26, top: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1565C0)),
                      alignment: Alignment.center,
                      child: const Text('SB', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // 大盲标识
                if (_isBB(s, game))
                  Positioned(
                    right: 26, top: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC62828)),
                      alignment: Alignment.center,
                      child: const Text('BB', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // ALL IN 标识
                if (!empty && s.player.allIn)
                  Positioned(
                    left: 0, right: 0, top: 48,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ALL IN', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              empty ? '空位' : s.player.name,
              style: TextStyle(
                color: out ? Colors.redAccent : Colors.white,
                fontSize: 11,
                fontWeight: isHero ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (reveal)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(game.handCategoryFor(s) ?? '',
                        style: const TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in s.player.holeCards)
                          Padding(padding: const EdgeInsets.only(right: 1), child: PlayingCardView(card: c, width: 22)),
                      ],
                    ),
                  ],
                ),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    empty ? '加机器人' : out ? '已出局' : '${s.player.stack}',
                    style: TextStyle(color: out ? Colors.redAccent : Colors.amber, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (bet > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate((bet / game.bigBlind).ceil().clamp(1, 2), (_) =>
                            Padding(
                              padding: const EdgeInsets.only(right: 1),
                              child: _ChipIcon(size: 14, color: const Color(0xFFFFD54F)),
                            )),
                          const SizedBox(width: 4),
                          Text('$bet', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
          ),
          ),
        )
    );
  }

  bool _isDealer(Seat? s, TableGame game) {
    if (s == null || game.state == null) return false;
    final idx = game.state!.players.indexOf(s.player);
    return idx >= 0 && game.state!.dealerIndex == idx;
  }

  bool _isSB(Seat? s, TableGame game) {
    if (s == null || game.state == null) return false;
    final players = game.state!.players;
    if (players.length < 2) return false;
    final idx = players.indexOf(s.player);
    return idx >= 0 && idx == (game.state!.dealerIndex + 1) % players.length;
  }

  bool _isBB(Seat? s, TableGame game) {
    if (s == null || game.state == null) return false;
    final players = game.state!.players;
    if (players.length < 2) return false;
    final idx = players.indexOf(s.player);
    final bbIdx = players.length == 2
        ? (game.state!.dealerIndex + 1) % players.length
        : (game.state!.dealerIndex + 2) % players.length;
    return idx >= 0 && idx == bbIdx;
  }
}

/// 倒计时圆环：从 12 点顺时针扫过，1 圈 30s，绿→黄→红。
class _TurnRingPainter extends CustomPainter {
  final double progress; // 0..1
  _TurnRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // 底环
    canvas.drawArc(rect, 0, 2 * 3.14159265, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white24);
    // 进度弧（从12点顺时针，绿→黄→红）
    final color = _colorFor(progress);
    canvas.drawArc(rect, -3.14159265 / 2, progress * 2 * 3.14159265, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..color = color);
  }

  Color _colorFor(double p) {
    if (p < 0.5) {
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFEB3B), p / 0.5)!;
    } else {
      return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFE53935), (p - 0.5) / 0.5)!;
    }
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) => old.progress != progress;
}

/// 操作动效叠加：播放音效 + 展示一次性动画。
class _ActionOverlay extends StatefulWidget {
  final String action; // fold / check / call / raise
  const _ActionOverlay({super.key, required this.action});

  @override
  State<_ActionOverlay> createState() => _ActionOverlayState();
}

class _ActionOverlayState extends State<_ActionOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    // 播放系统音效
    final sound = switch (widget.action) {
      'fold' => SystemSoundType.alert,
      'raise' => SystemSoundType.alert,
      _ => SystemSoundType.click,
    };
    SystemSound.play(sound);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.action) {
      'fold' => Icons.close,
      'check' => Icons.check_circle_outline,
      'call' => Icons.monetization_on,
      'raise' => Icons.trending_up,
      _ => Icons.circle,
    };
    final color = switch (widget.action) {
      'fold' => Colors.grey,
      'check' => const Color(0xFF66BB6A),
      'call' => const Color(0xFF42A5F5),
      'raise' => const Color(0xFFFFD54F),
      _ => Colors.white,
    };
    final label = switch (widget.action) {
      'fold' => '弃牌',
      'check' => '过牌',
      'call' => '跟注',
      'raise' => '加注',
      _ => '',
    };
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: (1 - _ctrl.value).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.5 + 0.8 * _ctrl.value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 32),
                Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 筹码图标：带内圈装饰的圆片。
class _ChipIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _ChipIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 2, offset: const Offset(0, 1))],
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
      child: Center(
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.5),
            border: Border.all(color: Colors.white54, width: 0.8),
          ),
        ),
      ),
    );
  }
}

/// 赢家最佳 5 张牌，缩放渐入 + 金框。
class _WinnerCards extends StatelessWidget {
  final TableGame game;
  final String wid;
  const _WinnerCards({super.key, required this.game, required this.wid});

  @override
  Widget build(BuildContext context) {
    final cards = game.winnerCards[wid];
    if (cards == null || cards.length < 5) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (_, v, __) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: (0.7 + 0.3 * v).clamp(0.0, 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text('最佳组合', style: TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in cards)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: Colors.yellow.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1),
                          ],
                        ),
                        child: PlayingCardView(card: c, width: 52),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Center extends StatelessWidget {
  final TableGame game;
  const _Center({required this.game});

  @override
  Widget build(BuildContext context) {
    final st = game.state;
    final community = st?.community ?? const [];
    return SizedBox(
      width: 310,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: i < community.length
                      ? PlayingCardView(card: community[i], width: 62)
                      : const PlayingCardView(faceDown: true, width: 62),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 3; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: i < community.length
                      ? PlayingCardView(card: community[i], width: 62)
                      : const PlayingCardView(faceDown: true, width: 62),
                ),
            ],
          ),
          if (game.lastResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(game.lastResult!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          // 赢家最佳5张牌（揭示时）
          if (game.revealIdx >= 0 && game.revealList.length > game.revealIdx)
            _WinnerCards(key: ValueKey(game.revealList[game.revealIdx]), game: game, wid: game.revealList[game.revealIdx]),
          if (game.notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(game.notice!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// 英雄底牌（放大，无多余文字）。
class _HeroHand extends StatelessWidget {
  final TableGame game;
  const _HeroHand({required this.game});

  @override
  Widget build(BuildContext context) {
    final hero = game.hero;
    final inHand = game.handInProgress && game.state != null && game.state!.players.any((p) => p.id == 'hero');
    final cards = hero.player.holeCards;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (inHand && cards.isNotEmpty)
            for (final c in cards)
              Padding(padding: const EdgeInsets.only(left: 6), child: PlayingCardView(card: c, width: 62))
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(hero.sittingOut ? '已出局，请补码' : '等待发牌',
                  style: const TextStyle(color: Colors.white54)),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final TableGame game;
  final String? sel;
  final ValueChanged<String> onSelect;
  final int rebuyAmount;
  final ValueChanged<int> onRebuyChanged;
  final VoidCallback onStart;
  final VoidCallback onLeave;

  const _ActionBar({
    required this.game,
    required this.sel,
    required this.onSelect,
    required this.rebuyAmount,
    required this.onRebuyChanged,
    required this.onStart,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    if (game.gameOver) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: onLeave, child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('游戏结束 · 查看结算'))),
      );
    }

    if (!game.handInProgress) {
      if (game.handCount == 0) {
        final ready = game.activeSeats.length >= 2;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: FilledButton(
            onPressed: ready ? onStart : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('开始游戏', style: TextStyle(fontSize: 16)),
            ),
          ),
        );
      }
      if (game.hero.sittingOut) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final c in const [500, 1000, 2000])
                    Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text('+$c'), selected: rebuyAmount == c, onSelected: (_) => onRebuyChanged(c))),
                  FilledButton(onPressed: () => game.rebuy(rebuyAmount), child: const Text('补码')),
                ],
              ),
            ],
          ),
        );
      }
      // 揭示赢家 / 自动下一手
      if (game.revealIdx >= 0 && game.revealList.length > game.revealIdx) {
        final wid = game.revealList[game.revealIdx];
        final seat = game.seats.cast<Seat?>().firstWhere((s) => s?.player.id == wid, orElse: () => null);
        final cat = seat != null ? game.handCategoryFor(seat) ?? '' : '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('${seat?.player.name ?? ""} 亮牌 · $cat',
              style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(game.autoAdvancing ? '下一手即将开始…' : '本手结束',
            style: const TextStyle(color: Colors.white70)),
      );
    }

    // 牌局进行中：单选，单击即操作（盖牌/让牌/跟注直接执行；加注滑轨→再点确认）
    final legal = game.legalForHero();
    final heroTurn = game.isHeroTurn;
    final raiseLabel = (sel == 'raise' && heroTurn) ? '确认' : '加注';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _radio('盖牌', 'fold', true),
              _radio('让牌', 'check', legal.canCheck),
              _radio('跟注', 'call', legal.canCall),
              _radio(raiseLabel, 'raise', legal.canRaise),
            ],
          ),
        ],
      ),
    );
  }

  Widget _radio(String label, String type, bool enabled) {
    final selected = sel == type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: enabled ? () => onSelect(type) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1565C0) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? Colors.lightBlueAccent : Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16, color: enabled ? Colors.white : Colors.white24),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.white24, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _RaiseSlider extends StatelessWidget {
  final TableGame game;
  final int value;
  final ValueChanged<int> onChanged;

  const _RaiseSlider({required this.game, required this.value, required this.onChanged});

  int get _min => _safeLegal()?.minRaiseTo ?? 0;
  int get _max => _safeLegal()?.maxRaiseTo ?? 0;
  int get _pot => game.state?.pot ?? 0;
  int get _currentBet => game.state?.currentBet ?? 0;
  LegalActions? _safeLegal() {
    final st = game.state;
    if (st == null || !st.players.any((p) => p.id == 'hero')) return null;
    return game.legalForHero();
  }

  void _set(int v) => onChanged(v.clamp(_min, _max));

  @override
  Widget build(BuildContext context) {
    final step = game.bigBlind;
    return Container(
      width: 84,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF1A3A5C), Color(0xFF0D1F3C)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A5A7C)),
        boxShadow: [const BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(1, 1))],
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Column(
        children: [
          // 金额显示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text(value.toString(),
                style: const TextStyle(color: Color(0xFF80DEEA), fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const SizedBox(height: 8),
          // 齿轮滑块（拉长填充）
          Expanded(
            child: Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10, width: 0.5),
            ),
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 5,
                  thumbShape: _GearThumbShape(),
                  activeTrackColor: const Color(0xFF80DEEA),
                  inactiveTrackColor: Colors.white10,
                  overlayColor: const Color(0xFF80DEEA).withValues(alpha: 0.1),
                ),
                child: Slider(
                  min: _min.toDouble(),
                  max: _max.toDouble(),
                  value: value.toDouble().clamp(_min.toDouble(), _max.toDouble()),
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // + / -
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.remove, () => _set(value - step)),
              const SizedBox(width: 8),
              _btn(Icons.add, () => _set(value + step)),
            ],
          ),
          const SizedBox(height: 8),
          // 快选按钮
          _quickBtn('1/2 底池', () => _set(_currentBet + (_pot / 2).round())),
          const SizedBox(height: 4),
          _quickBtn('底池', () => _set(_currentBet + _pot)),
          const SizedBox(height: 4),
          _quickBtn('全押', () => _set(_max)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => SizedBox(
        width: 26, height: 26,
        child: Material(
          color: const Color(0xFF3A5A7C),
          borderRadius: BorderRadius.circular(5),
          child: InkWell(onTap: onTap, child: Icon(icon, size: 15, color: Colors.white)),
        ),
      );

  Widget _quickBtn(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 6),
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ),
      );
}

/// 齿轮推杆风格滑块手柄。
class _GearThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 36);

  @override
  void paint(PaintingContext context, Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // 主体
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 20, height: 30), const Radius.circular(5));
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF37474F));
    // 凹槽
    final inner = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 12, height: 22), const Radius.circular(3));
    canvas.drawRRect(inner, Paint()..color = const Color(0xFF263238));
    // 横纹
    final lp = Paint()..color = const Color(0xFF546E7A)..strokeWidth = 1.2;
    for (var i = -1; i <= 1; i++) {
      final y = center.dy + i * 7;
      canvas.drawLine(Offset(center.dx - 8, y), Offset(center.dx + 8, y), lp);
    }
    // 高光
    final hl = Paint()..color = const Color(0xFF80CBC4).withValues(alpha: 0.25)..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - 6, center.dy - 10), Offset(center.dx - 6, center.dy + 10), hl);
  }
}

class _ChatBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSendText;
  final ValueChanged<int> onSendVoice;

  const _ChatBar({required this.controller, required this.onSendText, required this.onSendVoice});

  @override
  State<_ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<_ChatBar> {
  bool _voiceMode = false;
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;

  void _startRecord() {
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _seconds++));
  }

  void _stopRecord() {
    _timer?.cancel();
    _timer = null;
    final secs = _seconds;
    setState(() => _recording = false);
    if (secs > 0) widget.onSendVoice(secs.clamp(1, 60));
    _seconds = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      color: Colors.black26,
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _voiceMode = !_voiceMode),
            icon: Icon(_voiceMode ? Icons.keyboard : Icons.mic, color: Colors.white70),
          ),
          Expanded(
            child: _voiceMode
                ? GestureDetector(
                    onLongPressStart: (_) => _startRecord(),
                    onLongPressEnd: (_) => _stopRecord(),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                      child: Text(_recording ? '松开发送 · ${_seconds}s' : '按住 说话', style: const TextStyle(color: Colors.white70)),
                    ),
                  )
                : TextField(
                    controller: widget.controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '发言到房间…',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                    onSubmitted: widget.onSendText,
                  ),
          ),
          IconButton(
            onPressed: () {
              if (!_voiceMode) widget.onSendText(widget.controller.text);
            },
            icon: const Icon(Icons.send, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatefulWidget {
  final _Msg msg;
  const _ChatBubble({required this.msg});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _playing = false;
  double _progress = 0;
  Timer? _timer;

  void _play() {
    if (_playing) return;
    final dur = widget.msg.voiceSeconds ?? 1;
    setState(() {
      _playing = true;
      _progress = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      setState(() => _progress += 0.1 / dur);
      if (_progress >= 1) {
        t.cancel();
        setState(() {
          _playing = false;
          _progress = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${m.sender}：', style: const TextStyle(color: Colors.amber, fontSize: 12)),
          if (m.isVoice)
            GestureDetector(
              onTap: _play,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_playing ? Icons.pause : Icons.play_arrow, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 50,
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.lightBlueAccent),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${m.voiceSeconds}"', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            )
          else
            Text(m.text ?? '', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SettleDialog extends StatelessWidget {
  final List<Settlement> settle;
  final VoidCallback onClose;

  const _SettleDialog({required this.settle, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('房间结算'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in settle)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s.name),
                  Text('${s.net >= 0 ? '+' : ''}${s.net}',
                      style: TextStyle(color: s.net >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
      actions: [TextButton(onPressed: onClose, child: const Text('关闭'))],
    );
  }
}
