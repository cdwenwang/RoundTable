import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/ui/app.dart';

void main() {
  testWidgets('App opens on game carousel; swipe switches games', (tester) async {
    await tester.pumpWidget(const RoundTableApp());
    await tester.pump();

    expect(find.text('德州扑克'), findsOneWidget);
    expect(find.text('选择游戏'), findsOneWidget);

    // 左滑切到第二个游戏（狼人杀）。用 pump 推进，避免与封面呼吸动画的 pumpAndSettle 冲突。
    await tester.drag(find.text('德州扑克'), const Offset(-600, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('狼人杀'), findsOneWidget);
    expect(find.text('敬请期待'), findsWidgets);
  });
}
