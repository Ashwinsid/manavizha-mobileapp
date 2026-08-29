import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// Result of a call to the manavizha Next.js API.
///
/// [ok] mirrors `res.ok` on the web; [data] is the decoded JSON body (empty
/// map when the body was not JSON); [error] is the server's `error` field or
/// a network failure description; [status] is the HTTP status (0 = network
/// error before a response).
@immutable
class WebApiResult {
  const WebApiResult({
    required this.ok,
    required this.status,
    this.data = const {},
    this.error,
  });

  final bool ok;
  final int status;
  final Map<String, dynamic> data;
  final String? error;
}

/// Authenticated client for the manavizha web app's `/api/*` routes.
///
/// Every call sends the current Supabase session `access_token` as a Bearer
/// header — the same contract as the web's `authFetch()` in
/// `manavizha/lib/api-client.ts`. All server-side enforcement (block checks,
/// premium gating, tier limits, notifications, settings validation and photo
/// password hashing) happens behind these routes, so mobile writes MUST go
/// through here instead of writing Supabase tables directly.
class WebApi {
  WebApi._();

  static const Duration _timeout = Duration(seconds: 20);

  static String get _base =>
      AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/$'), '');

  static Map<String, String> _headers() {
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<WebApiResult> get(String path,
      {Map<String, String>? query}) async {
    return _send(() {
      var uri = Uri.parse('$_base$path');
      if (query != null && query.isNotEmpty) {
        uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
      }
      return http.get(uri, headers: _headers()).timeout(_timeout);
    });
  }

  static Future<WebApiResult> post(String path, Map<String, dynamic> body) {
    return _send(() => http
        .post(Uri.parse('$_base$path'),
            headers: _headers(), body: jsonEncode(body))
        .timeout(_timeout));
  }

  static Future<WebApiResult> patch(String path, Map<String, dynamic> body) {
    return _send(() => http
        .patch(Uri.parse('$_base$path'),
            headers: _headers(), body: jsonEncode(body))
        .timeout(_timeout));
  }

  static Future<WebApiResult> delete(String path, Map<String, dynamic> body) {
    return _send(() => http
        .delete(Uri.parse('$_base$path'),
            headers: _headers(), body: jsonEncode(body))
        .timeout(_timeout));
  }

  static Future<WebApiResult> _send(
      Future<http.Response> Function() request) async {
    if (_base.contains('10.0.2.2') || _base.contains('localhost')) {
      debugPrint('====================================================');
      debugPrint('WARNING: WebApi is using local loopback: $_base');
      debugPrint('Social actions will fail on a real physical device!');
      debugPrint('Compile with --dart-define=WEB_APP_BASE_URL=https://...');
      debugPrint('====================================================');
    }
    try {
      final res = await request();
      Map<String, dynamic> data = const {};
      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {}
      }
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      return WebApiResult(
        ok: ok,
        status: res.statusCode,
        data: data,
        error: ok ? null : (data['error']?.toString() ?? 'Request failed (${res.statusCode})'),
      );
    } catch (e) {
      debugPrint('WebApi request failed: $e');
      return WebApiResult(ok: false, status: 0, error: 'Network error. Please check your connection.');
    }
  }
}
