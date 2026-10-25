import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A slow, polite HTTP client: one request at a time with a pause between
/// them, a few retries on server errors, and a simple cookie jar.
class PoliteClient {
  PoliteClient({
    this.delay = const Duration(milliseconds: 800),
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  static const userAgent =
      'Mozilla/5.0 (compatible; TeamRankBot/0.1; +https://github.com/jfreema/TeamRank)';

  final Duration delay;
  final http.Client _inner;
  final Map<String, Map<String, String>> _cookies = {};
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  int requestCount = 0;

  Future<String> get(String url, {Map<String, String>? headers}) =>
      _send('GET', url, headers: headers);

  Future<String> post(String url,
          {Map<String, String>? headers, Object? body}) =>
      _send('POST', url, headers: headers, body: body);

  Future<dynamic> postJson(String url,
      {Map<String, String>? headers, required Object body}) async {
    final text = await post(url,
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode(body));
    return jsonDecode(text);
  }

  Future<String> _send(String method, String url,
      {Map<String, String>? headers, Object? body}) async {
    final uri = Uri.parse(url);
    for (var attempt = 1;; attempt++) {
      final wait = delay - DateTime.now().difference(_last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _last = DateTime.now();
      requestCount++;

      final req = http.Request(method, uri)
        ..followRedirects = true
        ..headers.addAll({
          'User-Agent': userAgent,
          'Accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
          if (_cookieHeader(uri) case final c?) 'Cookie': c,
          ...?headers,
        });
      if (body is String) {
        req.body = body;
      } else if (body is Map<String, String>) {
        req.bodyFields = body;
      }

      try {
        final res = await http.Response.fromStream(
            await _inner.send(req).timeout(const Duration(seconds: 45)));
        _storeCookies(uri, res.headers['set-cookie']);
        if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
        if (res.statusCode < 500 && res.statusCode != 429) {
          throw HttpStatusException(res.statusCode, '$method $url -> ${res.statusCode}', uri: uri);
        }
        if (attempt >= 4) {
          throw HttpStatusException(res.statusCode, '$method $url -> ${res.statusCode}', uri: uri);
        }
      } on TimeoutException {
        if (attempt >= 4) rethrow;
      } on SocketException {
        if (attempt >= 4) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 2 << attempt));
    }
  }

  String? _cookieHeader(Uri uri) {
    final jar = _cookies[uri.host];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _storeCookies(Uri uri, String? setCookie) {
    if (setCookie == null) return;
    final jar = _cookies.putIfAbsent(uri.host, () => {});
    // package:http joins multiple Set-Cookie headers with commas. Split only on
    // commas that start a new `name=` pair, not those inside Expires dates.
    for (final part in setCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final pair = part.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq > 0) jar[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }

  void close() => _inner.close();
}

/// An error status from a site, such as 404 for a page that does not exist.
class HttpStatusException extends HttpException {
  HttpStatusException(this.statusCode, super.message, {super.uri});

  final int statusCode;
}
