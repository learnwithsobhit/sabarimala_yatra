import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token storage: Keychain/Keystore on device; SharedPreferences fallback on web.
class SecureStore {
  static const _tokenKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'user_json';

  static const _secure = FlutterSecureStorage();

  Future<void> saveSession({
    required String token,
    required String userJson,
    String? refreshToken,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, userJson);
      if (refreshToken != null) {
        await prefs.setString(_refreshKey, refreshToken);
      }
      return;
    }
    await _secure.write(key: _tokenKey, value: token);
    await _secure.write(key: _userKey, value: userJson);
    if (refreshToken != null) {
      await _secure.write(key: _refreshKey, value: refreshToken);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_refreshKey);
  }

  Future<({String? token, String? refreshToken, String? userJson})>
      loadSession() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return (
        token: prefs.getString(_tokenKey),
        refreshToken: prefs.getString(_refreshKey),
        userJson: prefs.getString(_userKey),
      );
    }
    var token = await _secure.read(key: _tokenKey);
    var refreshToken = await _secure.read(key: _refreshKey);
    var userJson = await _secure.read(key: _userKey);
    if (token == null) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);
      refreshToken = prefs.getString(_refreshKey);
      userJson = prefs.getString(_userKey);
      if (token != null && userJson != null) {
        await saveSession(
          token: token,
          userJson: userJson,
          refreshToken: refreshToken,
        );
      }
    }
    return (token: token, refreshToken: refreshToken, userJson: userJson);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshKey);
      await prefs.remove(_userKey);
      return;
    }
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _refreshKey);
    await _secure.delete(key: _userKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }
}
