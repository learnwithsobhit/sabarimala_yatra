import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/push_bootstrap.dart';
import '../core/secure_store.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final api = ApiClient();
  return api;
});

final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  final c = AuthController(ref.watch(apiClientProvider));
  c.bootstrap();
  return c;
});

class AuthController extends ChangeNotifier {
  AuthController(this._api) {
    _api.onUnauthorized = logout;
    _api.refreshAccessToken = refreshAccessToken;
  }

  final ApiClient _api;
  final _store = SecureStore();
  String? token;
  String? refreshToken;
  Map<String, dynamic>? user;
  String? lastError;
  bool _refreshing = false;

  Future<void> bootstrap() async {
    final session = await _store.loadSession();
    token = session.token;
    refreshToken = session.refreshToken;
    final raw = session.userJson;
    if (raw != null) {
      try {
        user = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        user = null;
      }
    }
    _api.token = token;
    notifyListeners();
  }

  Future<String?> requestOtp(String phone) async {
    lastError = null;
    try {
      final res = await _api.post('/auth/otp/request', body: {'phone': phone});
      return res['dev_hint'] as String?;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> verifyOtp(String phone, String code) async {
    lastError = null;
    try {
      final res = await _api.post(
        '/auth/otp/verify',
        body: {'phone': phone, 'code': code},
      );
      await _applyAuthResponse(res);
      notifyListeners();
      await PushBootstrap(_api).registerIfLoggedIn();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> refreshAccessToken() async {
    if (_refreshing) return false;
    final rt = refreshToken;
    if (rt == null || rt.isEmpty) return false;
    _refreshing = true;
    try {
      final res = await _api.post(
        '/auth/refresh',
        body: {'refresh_token': rt},
        skipAuthRefresh: true,
      );
      await _applyAuthResponse(res);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> res) async {
    token = res['access_token'] as String;
    refreshToken = res['refresh_token'] as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    _api.token = token;
    await _store.saveSession(
      token: token!,
      userJson: jsonEncode(user),
      refreshToken: refreshToken,
    );
  }

  Future<void> logout() async {
    token = null;
    refreshToken = null;
    user = null;
    _api.token = null;
    await _store.clear();
    notifyListeners();
  }

  bool get isLeaderOrVolunteer {
    final role = user?['role'];
    return role == 'leader' || role == 'volunteer';
  }
}
