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
}

List<MediaItem> _posters(int start, int count) => [
      for (var i = 0; i < count; i++)
        MediaItem(
          id: start + i,
          title: 'Title ${start + i}',
          posterPath: '/p${start + i}.jpg',
        ),
    ];

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
  }) async {
    discoverCalls++;
    final items = page <= pages.length ? pages[page - 1] : const <MediaItem>[];
    return TmdbListPage(items: items, page: page, totalPages: pages.length);
  }
}
