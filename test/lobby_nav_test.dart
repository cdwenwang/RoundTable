import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/ui/screens/texas_lobby_screen.dart';

void main() {
  testWidgets('Lobby create-table navigates to table screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TexasLobbyScreen()));
    await tester.pump();

    expect(find.text('创建新桌子'), findsOneWidget);
    await tester.tap(find.text('创建新桌子'));
    await tester.pumpAndSettle();

    // 进入牌桌：房主就座 + 开始游戏按钮。
    expect(find.text('你'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.text('加机器人'), findsNWidgets(4));
  });
}
