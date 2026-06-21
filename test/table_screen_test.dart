import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:round_table/ui/screens/table_screen.dart';

void main() {
  testWidgets('TableScreen: host seated, empty seats add bots, start button present',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TableScreen(
        seats: 5,
        sceneLabel: '5 人桌',
        buyIn: 1000,
        smallBlind: 10,
        bigBlind: 20,
      ),
    ));
    await tester.pump();

    // 房主就座 0 号位，其余 4 个空位可加机器人。
    expect(find.text('你'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.text('加机器人'), findsNWidgets(4));

    // 点击一个空位添加机器人。
    await tester.tap(find.text('加机器人').first);
    await tester.pump();
    expect(find.text('机器人 2'), findsOneWidget);
    // 该座位不再显示“加机器人”。
    expect(find.text('加机器人'), findsNWidgets(3));

    // 开始游戏按钮在 ≥2 名玩家时可点击（此处无断言点击后的异步牌局）。
    final startBtn = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(startBtn.onPressed, isNotNull);
  });

  testWidgets('TableScreen disband shows settlement', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TableScreen(
        seats: 5,
        sceneLabel: '5 人桌',
        buyIn: 1000,
        smallBlind: 10,
        bigBlind: 20,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('离开'));
    await tester.pumpAndSettle();
    expect(find.text('房间结算'), findsOneWidget);
    expect(find.text('你'), findsWidgets);
  });
}
