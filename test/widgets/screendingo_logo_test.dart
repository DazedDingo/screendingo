import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchnext/widgets/screendingo_logo.dart';

void main() {
  group('ScreenDingoLogo', () {
    testWidgets('Dingo Text leaves height unset so the g descender stays '
        'inside ShaderMask bounds', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: ScreenDingoLogo())),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final dingo = tester.widget<Text>(find.text('Dingo'));
      expect(dingo.style?.height, isNull,
          reason: 'A fixed height (esp. 1.0) collapses the line box to the EM '
              'box, which clips the g descender out of ShaderMask.maskRect — '
              'the descender then renders white instead of the gradient.');
    });
  });
}
