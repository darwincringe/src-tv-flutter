import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/models/media_item.dart';
import 'package:srctv_flutter/data/repository/media_repository.dart';
import 'package:srctv_flutter/data/tmdb/tmdb_api.dart';

void main() {
  test('see more adds 10 titles until the catalog runs out', () async {
    final api = _PagedApi([
      _posters(1, 20),
      _posters(21, 20),
      _posters(41, 5),
    ]);
    final repo = MediaRepository(api: api);

    final first = await repo.findByDescription('disturbing movies');
    expect(first.items, hasLength(10));
    expect(first.items.first.id, 1);
    expect(first.items.last.id, 10);
    expect(first.hasMore, isTrue);
    expect(api.discoverCalls, 1);

    final second = await repo.moreByDescription('disturbing movies');
    expect(second.items, hasLength(20));
    expect(second.items.last.id, 20);
    expect(second.hasMore, isTrue);
    expect(api.discoverCalls, 1);

    final third = await repo.moreByDescription('disturbing movies');
    expect(third.items, hasLength(30));
    expect(third.hasMore, isTrue);
    expect(api.discoverCalls, 2);

    HelperFeed feed = third;
    while (feed.hasMore) {
      feed = await repo.moreByDescription('disturbing movies');
    }
    expect(feed.items, hasLength(45));
    expect(feed.items.last.id, 45);
    expect(feed.hasMore, isFalse);
    expect(api.discoverCalls, 3);
  });

  test('a person query uses their films', () async {
    final actor = _PersonApi(
      people: [(id: 62, name: 'Bruce Willis', department: 'Acting', popularity: 50)],
    );
    final repo = MediaRepository(api: actor);
    final feed = await repo.findByDescription('bruce willis movies');
    expect(actor.personQuery, 'bruce willis');
    expect(actor.lastPersonId, 62);
    expect(actor.lastRole, 'cast');
    expect(actor.keywordCalls, 0);
    expect(feed.items.single.id, 1);

    final director = _PersonApi(
      people: [(id: 525, name: 'Christopher Nolan', department: 'Directing', popularity: 40)],
    );
    await MediaRepository(api: director).findByDescription('christopher nolan movies');
    expect(director.lastPersonId, 525);
    expect(director.lastRole, 'crew');
  });
}

List<MediaItem> _posters(int start, int count) => [
      for (var i = 0; i < count; i++)
        MediaItem(
          id: start + i,
          title: 'Title ${start + i}',
          posterPath: '/p${start + i}.jpg',
        ),
    ];

class _PersonApi extends TmdbApi {
  _PersonApi({required this.people}) : super(Dio());

  final List<({int id, String name, String department, double popularity})> people;
  String? personQuery;
  int? lastPersonId;
  String? lastRole;
  int keywordCalls = 0;

  @override
  Future<List<({int id, String name, String department, double popularity})>>
      searchPeople(String query) async {
    personQuery = query;
    return people;
  }

  @override
  Future<List<({int id, String name})>> searchKeywords(String query) async {
    keywordCalls++;
    return const [];
  }

  @override
  Future<TmdbListPage> discoverFiltered(
    String type, {
    String? genres,
    String? keywords,
    String? language,
    int? yearFrom,
    int? yearTo,
    int page = 1,
    String? withoutGenres,
    double? minRating,
    int? personId,
    String? personRole,
  }) async {
    lastPersonId = personId;
    lastRole = personRole;
    return TmdbListPage(
      items: [
        const MediaItem(id: 1, title: 'Die Hard', posterPath: '/p.jpg'),
      ],
      page: 1,
      totalPages: 1,
    );
  }
}

class _PagedApi extends TmdbApi {
  _PagedApi(this.pages) : super(Dio());

  final List<List<MediaItem>> pages;
  int discoverCalls = 0;

  @override
  Future<List<({int id, String name})>> searchKeywords(String query) async {
    return [(id: 7, name: query)];
  }

  @override
  Future<TmdbListPage> discoverFiltered(
    String type, {
    String? genres,
    String? keywords,
    String? language,
    int? yearFrom,
    int? yearTo,
    int page = 1,
    String? withoutGenres,
    double? minRating,
    int? personId,
    String? personRole,
  }) async {
    discoverCalls++;
    final items = page <= pages.length ? pages[page - 1] : const <MediaItem>[];
    return TmdbListPage(items: items, page: page, totalPages: pages.length);
  }
}
