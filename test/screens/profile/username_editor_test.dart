import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kotabi/screens/profile/profile_screen.dart';

void main() {
  testWidgets('tap username editor invokes edit callback', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsernameEditor(
            username: 'alice',
            onEdit: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(UsernameEditor));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
