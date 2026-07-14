import 'package:dio/dio.dart';

/// TMDB HTTP configuration. The API key is appended to every request by a dio
/// interceptor, mirroring the Kotlin OkHttp interceptor in `TmdbClient.kt`.
class TmdbClient {
  static const String baseUrl = 'https://api.themoviedb.org/3/';
  static const String apiKey = '6e2c4366ba3f7d2eaec2dbd59b31e6ff';

  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.queryParameters = {
            ...options.queryParameters,
            'api_key': apiKey,
          };
          handler.next(options);
        },
      ),
    );
    return dio;
  }
}
