import 'package:shared_preferences/shared_preferences.dart';

import 'sound_boost.dart';

/// The web player's sound booster, remembered on this device only.
class SoundPrefStore {
  static late SharedPreferences _prefs;
  static const _key = 'sound_mode';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SoundMode get mode => SoundMode.fromName(_prefs.getString(_key));

  static Future<void> save(SoundMode mode) {
    return _prefs.setString(_key, mode.name);
  }
}
