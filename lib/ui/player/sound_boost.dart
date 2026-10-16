/// How the web player shapes the soundtrack.
enum SoundMode {
  off,
  talking,
  action;

  String get label => switch (this) {
        SoundMode.off => 'Off',
        SoundMode.talking => 'Talking',
        SoundMode.action => 'Action',
      };

  String get detail => switch (this) {
        SoundMode.off => 'Normal sound',
        SoundMode.talking =>
          'Voices come forward and loud effects ease off',
        SoundMode.action => 'More bass and punch for fights and explosions',
      };

  static SoundMode fromName(String? name) => switch (name) {
        'talking' => SoundMode.talking,
        'action' => SoundMode.action,
        _ => SoundMode.off,
      };
}

/// One equalizer setting, in the units the Web Audio nodes expect.
class SoundCurve {
  const SoundCurve({
    required this.highpassHz,
    required this.lowShelfHz,
    required this.lowShelfDb,
    required this.presenceHz,
    required this.presenceDb,
    required this.presenceQ,
    required this.highShelfHz,
    required this.highShelfDb,
    required this.thresholdDb,
    required this.kneeDb,
    required this.ratio,
    required this.attackSec,
    required this.releaseSec,
    required this.makeup,
  });

  final double highpassHz;
  final double lowShelfHz;
  final double lowShelfDb;
  final double presenceHz;
  final double presenceDb;
  final double presenceQ;
  final double highShelfHz;
  final double highShelfDb;
  final double thresholdDb;
  final double kneeDb;
  final double ratio;
  final double attackSec;
  final double releaseSec;

  /// Linear output gain after the compressor. 1 is unity.
  final double makeup;

  static SoundCurve forMode(SoundMode mode) => switch (mode) {
        SoundMode.off => _off,
        SoundMode.talking => _talking,
        SoundMode.action => _action,
      };

  /// Flat. The filters stay in the chain so switching modes doesn't click
  /// the graph apart, but none of them change the tone.
  static const _off = SoundCurve(
    highpassHz: 20,
    lowShelfHz: 200,
    lowShelfDb: 0,
    presenceHz: 2500,
    presenceDb: 0,
    presenceQ: 1,
    highShelfHz: 8000,
    highShelfDb: 0,
    thresholdDb: 0,
    kneeDb: 0,
    ratio: 1,
    attackSec: 0.003,
    releaseSec: 0.25,
    makeup: 1,
  );

  /// Lift the band where consonants live, trim rumble that masks speech,
  /// and compress so a blast doesn't jump out over the dialogue.
  static const _talking = SoundCurve(
    highpassHz: 120,
    lowShelfHz: 220,
    lowShelfDb: -3,
    presenceHz: 2500,
    presenceDb: 5.5,
    presenceQ: 1,
    highShelfHz: 9000,
    highShelfDb: -1.5,
    thresholdDb: -26,
    kneeDb: 16,
    ratio: 4,
    attackSec: 0.015,
    releaseSec: 0.2,
    makeup: 1.5,
  );

  /// Shelf up the low end and the top so hits and effects read louder,
  /// with only a light compressor so the hits still have impact.
  static const _action = SoundCurve(
    highpassHz: 30,
    lowShelfHz: 80,
    lowShelfDb: 6.5,
    presenceHz: 3200,
    presenceDb: 3,
    presenceQ: 0.9,
    highShelfHz: 8000,
    highShelfDb: 4.5,
    thresholdDb: -14,
    kneeDb: 8,
    ratio: 1.8,
    attackSec: 0.005,
    releaseSec: 0.12,
    makeup: 1.12,
  );
}
