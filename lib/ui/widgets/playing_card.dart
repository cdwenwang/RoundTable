import 'package:flutter/material.dart' hide Card;

import '../../poker/card.dart';

/// 一张牌的展示。`card` 为 null 或 `faceDown` 时显示牌背。
class PlayingCardView extends StatelessWidget {
  final Card? card;
  final bool faceDown;
  final double width;

  const PlayingCardView({super.key, this.card, this.faceDown = false, this.width = 44});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    if (faceDown || card == null) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Center(
          child: Icon(Icons.style, color: Colors.white24, size: 20),
        ),
      );
    }
    final red = card!.suit == Suit.hearts || card!.suit == Suit.diamonds;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26, width: 1),
      ),
      child: Center(
        child: Text(
          card.toString(),
          style: TextStyle(
            fontSize: width * 0.4,
            fontWeight: FontWeight.bold,
            color: red ? Colors.red.shade700 : Colors.black87,
          ),
        ),
      ),
    );
  }
}
