import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stream/stream_client.dart';
import 'premium_access.dart';

/// Account state + register/login against the backend (`api.srctv.space`). The
/// JWT and the user are persisted in shared_preferences so the session survives
/// restarts. The app talks only to these HTTPS endpoints — never to Mongo.
///
/// Browsing works signed out. Playing and adding to the library require an
/// admin or a premium account that has not expired (see [canStream]).
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
  static const _kAdmin = 'auth_admin';
  static const _kPremium = 'auth_premium';
  static const _kPremiumExpires = 'auth_premium_expires';
  static const _kOnboarded = 'auth_onboarded'; // welcome gate seen/dismissed

  /// Bumped on sign-in/out so screens (Settings, the welcome gate) rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String? _token;
  static String? _userId;
  static String? _username;
  static String? _email;
  static int _admin = 0;
  static int _premium = 0;
  static String? _premiumExpiresAt;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _emptyToNull(_prefs.getString(_kToken));
    _userId = _emptyToNull(_prefs.getString(_kUserId));
    _username = _emptyToNull(_prefs.getString(_kUsername));
    _email = _emptyToNull(_prefs.getString(_kEmail));
    _admin = _prefs.getInt(_kAdmin) ?? 0;
    _premium = _prefs.getInt(_kPremium) ?? 0;
    _premiumExpiresAt = _emptyToNull(_prefs.getString(_kPremiumExpires));
    StreamClient.bearerToken = () => _token;
    if (_token != null) await refreshProfile();
  }

  static String? _emptyToNull(String? s) => (s == null || s.isEmpty) ? null : s;

  static bool get isSignedIn => _token != null;
  static String? get token => _token;
  static String? get userId => _userId;
  static String? get username => _username;
  static String? get email => _email;
  static int get admin => _admin;
  static int get premium => _premium;
  static String? get premiumExpiresAt => _premiumExpiresAt;

  /// Admin, or premium that has not expired. Null expiry means it never expires.
  static bool get canStream => canAccessStreams(
        admin: _admin,
        premium: _premium,
        premiumExpiresAt: _premiumExpiresAt,
      );

  /// Reload admin / premium from the server so a grant or expiry is current.
  /// A 401 drops the session. Network errors keep the last saved flags.
  static Future<void> refreshProfile() async {
    if (_token == null) return;
    try {
      final resp = await _dio.get(
        'auth/me',
        options: authOptions().copyWith(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final data = resp.data;
      final user = data is Map ? data['user'] : null;
      if (user is! Map) return;
      _readUser(Map<String, dynamic>.from(user));
      await _persistAccount();
      revision.value++;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await signOut();
    } catch (_) {}
  }

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

  static void _readUser(Map<String, dynamic> u) {
    final id = u['id'];
    if (id is String && id.isNotEmpty) _userId = id;
    final username = u['username'];
    if (username is String && username.isNotEmpty) _username = username;
    final email = u['email'];
    if (email is String && email.isNotEmpty) _email = email;
    _admin = _asFlag(u['admin']);
    _premium = _asFlag(u['premium']);
    _premiumExpiresAt = _asExpiry(u['premium_expires_at'] ?? u['expires_at']);
  }

  static int _asFlag(Object? v) {
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt() == 1 ? 1 : 0;
    if (v is String && (v == '1' || v.toLowerCase() == 'true')) return 1;
    return 0;
  }

  /// Null or blank means the premium grant does not expire.
  static String? _asExpiry(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  static Future<void> _persistAccount() async {
    await _prefs.setString(_kToken, _token ?? '');
    await _prefs.setString(_kUserId, _userId ?? '');
    await _prefs.setString(_kUsername, _username ?? '');
    await _prefs.setString(_kEmail, _email ?? '');
    await _prefs.setInt(_kAdmin, _admin);
    await _prefs.setInt(_kPremium, _premium);
    if (_premiumExpiresAt == null) {
      await _prefs.remove(_kPremiumExpires);
    } else {
      await _prefs.setString(_kPremiumExpires, _premiumExpiresAt!);
    }
  }

  static Future<void> _store(Map<String, dynamic> data) async {
    _token = data['token'] as String?;
    final u = data['user'];
    if (u is Map) _readUser(Map<String, dynamic>.from(u));
    await _persistAccount();
    await _prefs.setBool(_kOnboarded, true);
    revision.value++;
  }

  static Future<void> signOut() async {
    _token = null;
    _userId = null;
    _username = null;
    _email = null;
    _admin = 0;
    _premium = 0;
    _premiumExpiresAt = null;
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kUsername);
    await _prefs.remove(_kEmail);
    await _prefs.remove(_kAdmin);
    await _prefs.remove(_kPremium);
    await _prefs.remove(_kPremiumExpires);
    revision.value++;
  }

  /// Authenticated request options (Bearer token) for SyncService.
  static Options authOptions() =>
      Options(headers: {'Authorization': 'Bearer ${_token ?? ''}'});

  static Dio get dio => _dio;
}
