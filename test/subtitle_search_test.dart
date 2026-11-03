import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/subtitle/subtitle_search.dart';

void main() {
  test('default search text is the title plus s01e01', () {
    expect(
      defaultSubtitleSearchText('Mr Robot', season: 1, episode: 1),
      'Mr Robot s01e01',
    );
    expect(
      defaultSubtitleSearchText('Dune'),
      'Dune',
    );
  });

  test('s01e01 in the box becomes the season and episode filter', () {
    final parsed = parseSubtitleSearch('Mr Robot s01e01');
    expect(parsed.q, 'Mr Robot');
    expect(parsed.season, 1);
    expect(parsed.episode, 1);
  });

  test('a title with no episode code keeps the player episode', () {
    final parsed = parseSubtitleSearch(
      'The Last of Us',
      season: 1,
      episode: 1,
    );
    expect(parsed.q, 'The Last of Us');
    expect(parsed.season, 1);
    expect(parsed.episode, 1);
  });
}
