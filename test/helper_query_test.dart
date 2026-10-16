import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/helper/helper_query.dart';

void main() {
  test('disturbing movies is a movie keyword search', () {
    final q = parseHelperQuery('disturbing movies');
    expect(q, isNotNull);
    expect(q!.mood, 'disturbing');
    expect(q.movies, isTrue);
    expect(q.series, isFalse);
    expect(q.movieGenreId, isNull);
    expect(q.explained, 'Movies · disturbing');
  });

  test('show me is a filler, not a series request', () {
    final q = parseHelperQuery('show me disturbing movies');
    expect(q!.mood, 'disturbing');
    expect(q.series, isFalse);
  });

  test('korean thrillers keep the language and the thriller genre', () {
    final q = parseHelperQuery('korean thrillers');
    expect(q!.language, 'ko');
    expect(q.languageName, 'Korean');
    expect(q.movieGenreId, '53');
    expect(q.tvGenreId, isNull);
    expect(q.genreWord, 'thriller');
    expect(q.movies, isTrue);
    expect(q.series, isTrue);
  });

  test('scary movies use the horror genre', () {
    final q = parseHelperQuery('scary movies');
    expect(q!.movieGenreId, '27');
    expect(q.series, isFalse);
    expect(q.mood, isNull);
  });

  test('funny series is comedy, series only', () {
    final q = parseHelperQuery('funny series');
    expect(q!.movieGenreId, '35');
    expect(q.tvGenreId, '35');
    expect(q.movies, isFalse);
    expect(q.series, isTrue);
  });

  test('90s action movies span that decade', () {
    final q = parseHelperQuery('90s action movies');
    expect(q!.yearFrom, 1990);
    expect(q.yearTo, 1999);
    expect(q.movieGenreId, '28');
    expect(q.series, isFalse);
  });

  test('feel-good uses well-liked comedies, not an empty keyword', () {
    final q = parseHelperQuery('feel-good movies')!;
    expect(q.mood, isNull);
    expect(q.movieGenreId, '35');
    expect(q.withoutGenres, '27,53');
    expect(q.minRating, 7);
    expect(q.keywordQueries, isEmpty);
    expect(parseHelperQuery('feel good movies')!.movieGenreId, '35');
  });

  test('mind-bending searches keywords that have a real catalog', () {
    final q = parseHelperQuery('mind-bending movies')!;
    expect(q.keywordQueries, ['time loop', 'plot twist', 'surreal']);
    expect(q.movieGenreId, isNull);
    expect(parseHelperQuery('sad movies')!.mood, 'tearjerker');
  });

  test('movies like a title uses recommendations', () {
    final q = parseHelperQuery('movies like Inception');
    expect(q!.isLike, isTrue);
    expect(q.likeTitle, 'inception');
    expect(q.movies, isTrue);
    expect(q.series, isFalse);
    expect(q.explained, 'Similar movies');
  });

  test('a bare word is not a list', () {
    expect(parseHelperQuery('movies'), isNull);
    expect(parseHelperQuery(''), isNull);
    expect(parseHelperQuery('the'), isNull);
  });

  test('keyword picker prefers an exact name', () {
    const found = [
      TmdbKeyword(1, 'disturbing the peace'),
      TmdbKeyword(2, 'disturbing'),
      TmdbKeyword(3, 'psychological'),
    ];
    expect(pickKeywordIds('disturbing', found), '2');
  });

  test('keyword picker treats a hyphen as a space', () {
    const found = [TmdbKeyword(4, 'feel good')];
    expect(pickKeywordIds('feel-good', found), '4');
  });

  test('keyword picker skips unrelated names', () {
    const found = [TmdbKeyword(9, 'musical')];
    expect(pickKeywordIds('disturbing', found), isNull);
  });
}
