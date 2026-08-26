import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchnext/providers/up_next_lag_provider.dart';

void main() {
  group('UpNextLagController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to 6h when no prior selection is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = UpNextLagController(prefs);
      expect(c.state, kUpNextLagHoursDefault);
      expect(c.state, 6);
    });

    test('rehydrates a previously-stored valid value', () async {
      SharedPreferences.setMockInitialValues({kUpNextLagHoursKey: 12});
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final c = UpNextLagController(prefs);
      expect(c.state, 12);
    });

    test('set persists to SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = UpNextLagController(prefs);
      await c.set(24);
      expect(prefs.getInt(kUpNextLagHoursKey), 24);
      expect(c.state, 24);
    });

    test('unknown/invalid stored value falls back to the default', () async {
      SharedPreferences.setMockInitialValues({kUpNextLagHoursKey: 999});
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final c = UpNextLagController(prefs);
      expect(c.state, kUpNextLagHoursDefault);
    });

    test('kUpNextLagChoices contains the default', () {
      expect(kUpNextLagChoices, contains(kUpNextLagHoursDefault));
    });
  });
}
