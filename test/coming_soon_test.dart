import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/tmdb/coming_soon.dart';

void main() {
  final today = DateTime(2026, 10, 17);

  Map<String, dynamic> providers(List<String> offers) => {
        'results': {
          'US': {for (final offer in offers) offer: [{}]},
        },
      };

  Map<String, dynamic> releases(List<Map<String, dynamic>> dates) => {
        'results': [
          {'iso_3166_1': 'US', 'release_dates': dates},
        ],
      };

  test('a movie already on Netflix is not Coming Soon', () {
    final payload = providers(['flatrate']);
    expect(movieAvailableOnline(payload), isTrue);
    expect(
      movieComingSoon(
        availableOnline: true,
        theatricalDates: [DateTime(2026, 10, 1)],
        now: today,
      ),
      isFalse,
    );
  });

  test('a theatrical title with no streaming offer is Coming Soon', () {
    final dates = theatricalReleaseDates(releases([
      {'type': 3, 'release_date': '2026-10-10T00:00:00.000Z'},
      {'type': 4, 'release_date': '2026-12-01T00:00:00.000Z'},
    ]));
    expect(dates, isNotEmpty);
    expect(
      movieComingSoon(
        availableOnline: false,
        theatricalDates: dates,
        now: today,
      ),
      isTrue,
    );
  });

  test('a digital-only launch is not Coming Soon', () {
    final dates = theatricalReleaseDates(releases([
      {'type': 4, 'release_date': '2026-10-17T00:00:00.000Z'},
    ]));
    expect(dates, isEmpty);
    expect(
      movieComingSoon(
        availableOnline: false,
        theatricalDates: dates,
        now: today,
      ),
      isFalse,
    );
  });

  test('an old theatrical title is not Coming Soon', () {
    expect(
      movieComingSoon(
        availableOnline: false,
        theatricalDates: [DateTime(2024, 1, 1)],
        now: today,
      ),
      isFalse,
    );
  });
}
