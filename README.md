# RoundTable · RoundTable Games

A Flutter-powered mobile board game platform. Launch title: Texas Hold'em, with Werewolf and more party games planned.

## Features

### Texas Hold'em
- **Monte Carlo Cheat Panel**: Type `wenwangdk` in chat for real-time equity / outs / key cards via 1500 sims
- **Mental Poker Protocol**: Commutative modular-exponentiation encryption for trustless dealing over Bluetooth — no single device knows all cards
- **Numbered Ring Seats**: NetEase Werewolf-style oval layout (odd N: 1 top + (N−1)/2 per side; even N: N/2 per side)
- **30s Turn Timer Ring**: Clockwise green→yellow→red arc; auto-fold / auto-check on timeout
- **Pre-action**: Pre-select fold/check/call/raise while it's not your turn; auto-executes when your turn arrives
- **Gear-throttle Raise Slider**: Custom `SliderComponentShape` + dark metal panel + quick bets (½ pot / pot / all-in) + tactile damping
- **Persistent Table**: Seat management / buy-in & rebuy / 0-chip auto sit-out / settlement: `net = stack − total buy-in`
- **AI Bots**: Heuristic engine based on pot odds and hand strength (planned integration with LLM-based AI)
- **Action Feedback**: Fold dims avatar / call bounces chips / raise pulses gold glow + system sounds
- **Dealer/SB/BB badges** + **ALL IN tag** + **button rotates clockwise**
- **Showdown Reveal**: Only winners show hole cards, displayed sequentially from dealer position, merging with community to highlight best 5 cards

### Chat & Voice
- Text bubbles + hold-to-talk voice recording (animated playback progress)

### Bluetooth Multiplayer (in progress)
- Distributed mental poker protocol verified in-process via `MockTransport`
- `flutter_blue_plus` BLE central-role transport (Peripheral role pending for full P2P)

## Architecture

```
lib/
├── main.dart
├── poker/            # Pure Dart: cards/deck/7-choose-5 evaluator/betting & side-pot engine/Monte Carlo equity
├── crypto/           # Mental poker (commutative encryption)
├── session/          # Persistent table controller / multiplayer session
├── ai/               # Bot decision engine
├── net/              # Transport abstraction (Mock / Bluetooth)
├── games/            # Game registry (carousel driver)
└── ui/screens/       # Carousel / lobby / table / Bluetooth
```

## Quick Start

```bash
flutter pub get
flutter run -d chrome   # Desktop debug (no Bluetooth)
flutter run -d <device> # Physical device
flutter test            # 26 unit tests passing
```

## Cheat Codes

| Command | Function |
|---------|----------|
| `wenwangdk` | Enable equity overlay (won't send to chat) |
| `wenwanggb` | Disable equity overlay (won't send to chat) |

## TODO

- [ ] LLM-powered AI bots (GPT/Claude) replacing heuristic engine
- [ ] Bluetooth Peripheral role for complete P2P multiplayer
- [ ] Werewolf game logic
- [ ] Real audio capture/playback (`record` + `audioplayers`)
- [ ] Zero-knowledge shuffle proof (mitigate active MITM in mental poker)
- [ ] 2048-bit safe prime replacing `dev` test parameters
- [ ] Dynamic cover images/videos replacing gradient placeholders

## License

MIT
