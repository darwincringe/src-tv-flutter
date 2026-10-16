import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srctv_flutter/ui/player/sound_boost.dart';
import 'package:srctv_flutter/ui/player/sound_pref.dart';

void main() {
  test('talking lifts voices and action lifts bass', () {
    final off = SoundCurve.forMode(SoundMode.off);
    final talking = SoundCurve.forMode(SoundMode.talking);
    final action = SoundCurve.forMode(SoundMode.action);

    expect(off.makeup, 1);
    expect(off.lowShelfDb, 0);
    expect(off.presenceDb, 0);
    expect(off.ratio, 1);

    expect(talking.presenceDb, greaterThan(0));
    expect(talking.lowShelfDb, lessThan(0));
    expect(talking.makeup, greaterThan(1));
    expect(talking.ratio, greaterThan(action.ratio));

    expect(action.lowShelfDb, greaterThan(talking.lowShelfDb));
    expect(action.highShelfDb, greaterThan(0));
    expect(action.makeup, greaterThan(1));
  });

  test('unknown saved names fall back to off', () {
    expect(SoundMode.fromName(null), SoundMode.off);
    expect(SoundMode.fromName('nope'), SoundMode.off);
    expect(SoundMode.fromName('talking'), SoundMode.talking);
  });

  test('the choice is kept on this device', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SoundPrefStore.init();
    expect(SoundPrefStore.mode, SoundMode.off);
    await SoundPrefStore.save(SoundMode.action);
    expect(SoundPrefStore.mode, SoundMode.action);
  });
}
