import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/widgets/unread_badge.dart';

void main() {
  testWidgets('UnreadBadge hides at zero and caps at 99+', (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 0, child: Icon(CupertinoIcons.bell))));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 5, child: Icon(CupertinoIcons.bell))));
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(const CupertinoApp(home: UnreadBadge(count: 150, child: Icon(CupertinoIcons.bell))));
    expect(find.text('99+'), findsOneWidget);
  });
}
