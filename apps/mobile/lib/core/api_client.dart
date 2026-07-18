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

  /// Called on HTTP 401 after a failed refresh attempt.
  Future<void> Function()? onUnauthorized;

  /// Attempt to rotate access token; return true if a new token was stored.
  Future<bool> Function()? refreshAccessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuthRefresh = false,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 401 && !skipAuthRefresh) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          final retry = await http
              .post(
                Uri.parse('$baseUrl$path'),
                headers: _headers,
                body: jsonEncode(body ?? {}),
              )
              .timeout(const Duration(seconds: 8));
          return _decode(retry, skipAuthRefresh: true) as Map<String, dynamic>;
        }
      }
      return _decode(res, skipAuthRefresh: skipAuthRefresh) as Map<String, dynamic>;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Cannot reach the server. Check your connection and try again.',
        0,
      );
    }
  }

  Future<bool> _tryRefresh() async {
    final fn = refreshAccessToken;
    if (fn == null) return false;
    return fn();
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

  /// Raw binary PUT used for direct uploads. `target` may be an absolute URL
  /// (S3 presigned) or an API-relative path (local dev blob endpoint). For S3
  /// we deliberately omit the Authorization header so it does not interfere
  /// with the presigned query signature.
  Future<void> putBinary(
    String target, {
    required List<int> bytes,
    required String contentType,
    Map<String, String> signedHeaders = const {},
  }) async {
    final isAbsolute = target.startsWith('http');
    final uri = isAbsolute ? Uri.parse(target) : Uri.parse('$baseUrl$target');
    // Every signed header (e.g. x-amz-tagging) must be echoed verbatim or S3
    // rejects the signature.
    final headers = <String, String>{...signedHeaders};
    headers['Content-Type'] = contentType;
    if (!isAbsolute && token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    try {
      final res = await http
          .put(uri, headers: headers, body: bytes)
          .timeout(const Duration(minutes: 3));
      if (res.statusCode >= 400) {
        throw ApiException('Upload failed (${res.statusCode})', res.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Upload failed. Check your connection and try again.', 0);
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

  Future<String> getText(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) {
        _decode(res);
      }
      return res.body;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Cannot reach the server. Check your connection and try again.',
        0,
      );
    }
  }

  dynamic _decode(http.Response res, {bool skipAuthRefresh = false}) {
    final body = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && !skipAuthRefresh) {
        final cb = onUnauthorized;
        if (cb != null) {
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
