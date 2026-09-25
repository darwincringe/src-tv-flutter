import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stream/stream_client.dart';

/// Account state + register/login against the backend (`api.srctv.space`). The
/// JWT and the user are persisted in shared_preferences so the session survives
/// restarts. The app talks only to these HTTPS endpoints — never to Mongo.
///
/// Signed-out is a fully supported mode: everything still works from the local
/// stores; signing in just adds cross-device sync (see SyncService).
class AuthService {
  static late SharedPreferences _prefs;
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: StreamClient.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static const _kToken = 'auth_token';
  static const _kUserId = 'auth_user_id';
  static const _kUsername = 'auth_username';
  static const _kEmail = 'auth_email';
  static const _kOnboarded = 'auth_onboarded'; // welcome gate seen/dismissed

  /// Bumped on sign-in/out so screens (Settings, the welcome gate) rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String? _token;
  static String? _userId;
  static String? _username;
  static String? _email;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _emptyToNull(_prefs.getString(_kToken));
    _userId = _emptyToNull(_prefs.getString(_kUserId));
    _username = _emptyToNull(_prefs.getString(_kUsername));
    _email = _emptyToNull(_prefs.getString(_kEmail));
  }

  static String? _emptyToNull(String? s) => (s == null || s.isEmpty) ? null : s;

  static bool get isSignedIn => _token != null;
  static String? get token => _token;
  static String? get userId => _userId;
  static String? get username => _username;
  static String? get email => _email;

  /// Whether the first-run welcome gate has been dealt with (signed in, or the
  /// user tapped "Skip"). Once true, we never force the gate again.
  static bool get onboardingDone => _prefs.getBool(_kOnboarded) ?? false;

  static Future<void> markOnboarded() async {
    await _prefs.setBool(_kOnboarded, true);
    revision.value++;
  }

  /// Register. Returns null on success, or a human-readable error string.
  static Future<String?> register(
    String username,
    String email,
    String password,
  ) =>
      _authPost('auth/register', {
        'username': username,
        'email': email,
        'password': password,
      });

  /// Login with email OR username. Returns null on success, or an error string.
  static Future<String?> login(String emailOrUsername, String password) =>
      _authPost('auth/login', {
        'emailOrUsername': emailOrUsername,
        'password': password,
      });

  static Future<String?> _authPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final resp = await _dio.post(path, data: body);
      final data = resp.data;
      if (data is Map<String, dynamic> && (data['token'] as String?) != null) {
        await _store(data);
        return null;
      }
      return 'Unexpected response from the server.';
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Cannot reach the server. Check your connection.';
      }
      return 'Something went wrong. Please try again.';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  static Future<void> _store(Map<String, dynamic> data) async {
    _token = data['token'] as String?;
    final u = data['user'];
    if (u is Map) {
      _userId = u['id'] as String?;
      _username = u['username'] as String?;
      _email = u['email'] as String?;
    }
    await _prefs.setString(_kToken, _token ?? '');
    await _prefs.setString(_kUserId, _userId ?? '');
    await _prefs.setString(_kUsername, _username ?? '');
    await _prefs.setString(_kEmail, _email ?? '');
    await _prefs.setBool(_kOnboarded, true);
    revision.value++;
  }

  static Future<void> signOut() async {
    _token = null;
    _userId = null;
    _username = null;
    _email = null;
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kUsername);
    await _prefs.remove(_kEmail);
    revision.value++;
  }

  /// Authenticated request options (Bearer token) for SyncService.
  static Options authOptions() =>
      Options(headers: {'Authorization': 'Bearer ${_token ?? ''}'});

  static Dio get dio => _dio;
}
