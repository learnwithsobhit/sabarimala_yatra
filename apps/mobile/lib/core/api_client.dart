import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  });

  final String baseUrl;
  String? token;

  /// Called on HTTP 401 so the app can clear session and send user to login.
  Future<void> Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 8));
      return _decode(res) as Map<String, dynamic>;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Cannot reach the server. Check your connection and try again.',
        0,
      );
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 8));
      return _decode(res) as Map<String, dynamic>;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Cannot reach the server. Check your connection and try again.',
        0,
      );
    }
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      for (final e in fields.entries) {
        req.fields[e.key] = e.value;
      }
      req.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          bytes,
          filename: filename,
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      return _decode(res) as Map<String, dynamic>;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Cannot upload to $baseUrl$path ($e)', 0);
    }
  }

  Future<dynamic> get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return _decode(res);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Cannot reach the server. Check your connection and try again.',
        0,
      );
    }
  }

  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      if (res.statusCode == 401) {
        final cb = onUnauthorized;
        if (cb != null) {
          // Fire-and-forget; logout notifies listeners.
          Future.microtask(cb);
        }
      }
      final msg = body is Map && body['error'] != null
          ? body['error'].toString()
          : 'Something went wrong. Please try again.';
      throw ApiException(msg, res.statusCode);
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
