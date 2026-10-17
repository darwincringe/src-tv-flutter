/// A phrase like "disturbing movies" turned into TMDB discover filters.
///
/// No network here: keyword ids are resolved later, after a keyword search.
class HelperRequest {
  const HelperRequest({
    required this.summary,
    this.likeTitle,
    this.mood,
    this.genreWord,
    this.movieGenreId,
    this.tvGenreId,
    this.language,
    this.languageName,
    this.yearFrom,
    this.yearTo,
    this.movies = true,
    this.series = true,
    this.keywordQueries = const [],
    this.withoutGenres,
    this.minRating,
    this.personName,
    this.personRole,
  });

  /// Short line shown above the results, e.g. "Disturbing movies".
  final String summary;

  /// "movies like Inception" — look the title up, then use recommendations.
  final String? likeTitle;

  /// Leftover theme words, e.g. "disturbing". Looked up as TMDB keywords.
  final String? mood;

  /// Genre name used as a keyword on the side that has no genre id.
  /// TV has no horror genre, so "scary movies" still works for series.
  final String? genreWord;

  final String? movieGenreId;
  final String? tvGenreId;
  final String? language;
  final String? languageName;
  final int? yearFrom;
  final int? yearTo;
  final bool movies;
  final bool series;

  /// Extra keyword searches, combined with OR. Used when the obvious keyword
  /// name is unused on real titles (for example "mind-bending").
  final List<String> keywordQueries;

  /// Genres to exclude, such as horror on a feel-good list.
  final String? withoutGenres;

  /// Minimum TMDB rating, so a broad genre stays a list people want.
  final double? minRating;

  /// "bruce willis movies" — a person's name, not a theme keyword.
  final String? personName;

  /// `cast` or `crew` when the phrase says starring or directed. Null lets
  /// the person's own department decide.
  final String? personRole;

  bool get isLike => likeTitle != null && likeTitle!.isNotEmpty;

  /// What the filters understood, shown under the results.
  String get explained {
    if (isLike) {
      final kind = series && !movies
          ? 'series'
          : movies && !series
              ? 'movies'
              : 'titles';
      return 'Similar $kind';
    }
    final kind = movies && series
        ? 'Movies and series'
        : movies
            ? 'Movies'
            : 'Series';
    final bits = <String>[
      ?languageName,
      if (yearFrom != null && yearTo != null) '$yearFrom–$yearTo',
      ?genreWord,
      ?mood,
      if (personName != null) _nameCase(personName!),
    ];
    if (bits.isEmpty) return kind;
    return '$kind · ${bits.join(' · ')}';
  }
}

class TmdbKeyword {
  const TmdbKeyword(this.id, this.name);
  final int id;
  final String name;
}

/// Picks up to two keyword ids that actually match the words the user typed.
/// Pipe-joined so TMDB treats them as "either".
String _keywordKey(String value) => value
    .toLowerCase()
    .replaceAll('-', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? pickKeywordIds(String query, List<TmdbKeyword> found) {
  if (found.isEmpty) return null;
  final q = _keywordKey(query);
  if (q.isEmpty) return null;
  final exact = found.where((k) => _keywordKey(k.name) == q).toList();
  final pool = exact.isNotEmpty
      ? exact
      : found.where((k) {
          final n = _keywordKey(k.name);
          return n.contains(q) || q.contains(n);
        }).toList();
  if (pool.isEmpty) return null;
  return pool.take(2).map((k) => k.id).join('|');
}

class HelperPerson {
  const HelperPerson(this.id, this.name, this.department, this.popularity);

  final int id;
  final String name;
  final String department;
  final double popularity;
}

/// The person whose name is the phrase, preferring the best-known match.
HelperPerson? pickPerson(String query, List<HelperPerson> found) {
  final q = _keywordKey(query);
  if (q.isEmpty || found.isEmpty) return null;
  final exact = found.where((p) => _keywordKey(p.name) == q).toList();
  if (exact.isEmpty) return null;
  exact.sort((a, b) => b.popularity.compareTo(a.popularity));
  return exact.first;
}

/// Cast for an actor, crew for a director, unless the phrase already said which.
String personCredit(String? role, String department) {
  if (role == 'cast' || role == 'crew') return role!;
  if (department.toLowerCase() == 'directing') return 'crew';
  return 'cast';
}

HelperRequest? parseHelperQuery(String raw) {
  var s = raw.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;

  final like = RegExp(
    r'^(?:(movies?|films?|series|shows?)\s+)?(?:like|similar to)\s+(.+)$',
  ).firstMatch(s);
  if (like != null) {
    final title = like.group(2)!.trim();
    if (title.isEmpty) return null;
    final kind = like.group(1);
    final movies = kind == null || kind.startsWith('movie') || kind.startsWith('film');
    final series = kind == null || kind.startsWith('series') || kind.startsWith('show');
    return HelperRequest(
      summary: _titleCase(raw.trim()),
      likeTitle: title,
      movies: movies,
      series: series,
    );
  }

  for (final lead in const [
    'show me',
    'find me',
    'give me',
    'i want',
    'a list of',
    'list of',
  ]) {
    if (s.startsWith('$lead ')) s = s.substring(lead.length).trim();
  }

  for (final alias in _phraseAliases.entries) {
    s = s.replaceAll(alias.key, alias.value);
  }

  final tokens = s.split(' ').where((t) => t.isNotEmpty).toList();
  var movies = false;
  var series = false;
  String? movieGenreId;
  String? tvGenreId;
  String? genreWord;
  String? language;
  String? languageName;
  int? yearFrom;
  int? yearTo;
  List<String> keywordQueries = const [];
  String? withoutGenres;
  double? minRating;
  String? personRole;
  final mood = <String>[];

  for (final token in tokens) {
    if (token == 'with' || token == 'starring' || token == 'featuring') {
      personRole = 'cast';
      continue;
    }
    if (token == 'directed' || token == 'director') {
      personRole = 'crew';
      continue;
    }
    if (token == 'by') continue;
    if (_filler.contains(token)) continue;
    if (_movieWords.contains(token)) {
      movies = true;
      continue;
    }
    if (_seriesWords.contains(token)) {
      series = true;
      continue;
    }
    final lang = _languages[token];
    if (lang != null) {
      language = lang.$1;
      languageName = lang.$2;
      continue;
    }
    final decade = _decade(token);
    if (decade != null) {
      yearFrom = decade.$1;
      yearTo = decade.$2;
      continue;
    }
    final genre = _genres[token];
    if (genre != null) {
      movieGenreId = genre.movieId ?? movieGenreId;
      tvGenreId = genre.tvId ?? tvGenreId;
      genreWord = genre.word;
      continue;
    }
    final spec = _moods[token];
    if (spec != null) {
      movieGenreId = spec.movieId ?? movieGenreId;
      tvGenreId = spec.tvId ?? tvGenreId;
      genreWord = spec.word;
      keywordQueries = spec.keywordQueries;
      withoutGenres = spec.withoutGenres;
      minRating = spec.minRating;
      continue;
    }
    mood.add(_wordAliases[token] ?? token);
  }

  if (!movies && !series) {
    movies = true;
    series = true;
  }

  final loose = mood.join(' ');
  final asPerson = personRole != null ? mood.isNotEmpty : mood.length >= 2;
  final personName = asPerson ? loose : null;
  final moodText = asPerson || mood.isEmpty ? null : loose;
  if (personName == null &&
      moodText == null &&
      genreWord == null &&
      language == null &&
      yearFrom == null) {
    return null;
  }

  return HelperRequest(
    summary: _titleCase(raw.trim()),
    mood: moodText,
    genreWord: genreWord,
    movieGenreId: movieGenreId,
    tvGenreId: tvGenreId,
    language: language,
    languageName: languageName,
    yearFrom: yearFrom,
    yearTo: yearTo,
    movies: movies,
    series: series,
    keywordQueries: keywordQueries,
    withoutGenres: withoutGenres,
    minRating: minRating,
    personName: personName,
    personRole: personName == null ? null : personRole,
  );
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

String _nameCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

(int, int)? _decade(String token) {
  final m = RegExp(r'^((?:19|20)\d{2}|[2-9]0)s$').firstMatch(token);
  if (m == null) return null;
  final raw = m.group(1)!;
  final start = raw.length == 2 ? 1900 + int.parse(raw) : int.parse(raw);
  if (start % 10 != 0) return null;
  return (start, start + 9);
}

class _Genre {
  const _Genre(this.word, this.movieId, this.tvId);
  final String word;
  final String? movieId;
  final String? tvId;
}

/// Moods whose obvious TMDB keyword is unused on real titles. These point at
/// a genre or at keyword names that actually have a catalog.
class _Mood {
  const _Mood({
    required this.word,
    this.movieId,
    this.tvId,
    this.keywordQueries = const [],
    this.withoutGenres,
    this.minRating,
  });

  final String word;
  final String? movieId;
  final String? tvId;
  final List<String> keywordQueries;
  final String? withoutGenres;
  final double? minRating;
}

const _feelGood = _Mood(
  word: 'feel-good',
  movieId: '35',
  tvId: '35',
  withoutGenres: '27,53',
  minRating: 7,
);

const _moods = <String, _Mood>{
  'feelgood': _feelGood,
  'wholesome': _feelGood,
  'mindbending': _Mood(
    word: 'mind-bending',
    keywordQueries: ['time loop', 'plot twist', 'surreal'],
  ),
};

const _filler = {
  'a',
  'an',
  'the',
  'some',
  'me',
  'of',
  'for',
  'with',
  'about',
  'very',
  'really',
  'good',
  'best',
  'top',
  'and',
  'to',
  'please',
};

const _movieWords = {'movie', 'movies', 'film', 'films'};
const _seriesWords = {'series', 'show', 'shows', 'tv'};

const _languages = <String, (String, String)>{
  'korean': ('ko', 'Korean'),
  'korea': ('ko', 'Korean'),
  'japanese': ('ja', 'Japanese'),
  'japan': ('ja', 'Japanese'),
  'french': ('fr', 'French'),
  'spanish': ('es', 'Spanish'),
  'hindi': ('hi', 'Hindi'),
  'chinese': ('zh', 'Chinese'),
  'thai': ('th', 'Thai'),
  'german': ('de', 'German'),
  'italian': ('it', 'Italian'),
  'filipino': ('tl', 'Filipino'),
  'tagalog': ('tl', 'Filipino'),
  'english': ('en', 'English'),
};

const _genres = <String, _Genre>{
  'scifi': _Genre('science fiction', '878', '10765'),
  'action': _Genre('action', '28', '10759'),
  'adventure': _Genre('adventure', '12', '10759'),
  'animation': _Genre('animation', '16', '16'),
  'animated': _Genre('animation', '16', '16'),
  'anime': _Genre('animation', '16', '16'),
  'comedy': _Genre('comedy', '35', '35'),
  'funny': _Genre('comedy', '35', '35'),
  'crime': _Genre('crime', '80', '80'),
  'documentary': _Genre('documentary', '99', '99'),
  'drama': _Genre('drama', '18', '18'),
  'family': _Genre('family', '10751', '10751'),
  'fantasy': _Genre('fantasy', '14', '10765'),
  'horror': _Genre('horror', '27', null),
  'scary': _Genre('horror', '27', null),
  'thriller': _Genre('thriller', '53', null),
  'thrillers': _Genre('thriller', '53', null),
  'romance': _Genre('romance', '10749', null),
  'romantic': _Genre('romance', '10749', null),
  'mystery': _Genre('mystery', '9648', '9648'),
  'war': _Genre('war', '10752', '10768'),
  'western': _Genre('western', '37', '37'),
  'music': _Genre('music', '10402', null),
  'kids': _Genre('kids', '10751', '10762'),
};

/// Longer phrases first. Values are single tokens the genre/mood maps know.
const _phraseAliases = <String, String>{
  'science fiction': 'scifi',
  'sci-fi': 'scifi',
  'sci fi': 'scifi',
  'feel-good': 'feelgood',
  'feel good': 'feelgood',
  'mind-bending': 'mindbending',
  'mind bending': 'mindbending',
  'based on a true story': 'truestory',
  'true story': 'truestory',
  'time travel': 'timetravel',
};

const _wordAliases = <String, String>{
  'sad': 'tearjerker',
  'heartbreaking': 'tearjerker',
  'unsettling': 'disturbing',
  'shocking': 'disturbing',
  'gory': 'gore',
  'weird': 'surrealism',
  'truestory': 'based on a true story',
  'timetravel': 'time travel',
};
