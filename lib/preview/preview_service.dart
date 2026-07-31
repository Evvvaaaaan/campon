/// 밤 미리보기를 프록시에서 받아온다. 실패하면 로컬 장면으로 대체한다.
library;

import 'dart:convert';
import 'dart:io';

import 'preview_models.dart';

typedef PreviewFetcher = Future<String> Function(Uri url, String body);

const _defaultBase = String.fromEnvironment(
  'PLAN_PROXY_URL',
  defaultValue: 'https://campon-ai-proxy.azurewebsites.net',
);

Future<String> _httpFetcher(Uri url, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.postUrl(url);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(body));
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

class PreviewService {
  PreviewService({PreviewFetcher? fetcher, String? baseUrl})
    : _fetch = fetcher ?? _httpFetcher,
      _baseUrl = baseUrl ?? _defaultBase;

  final PreviewFetcher _fetch;
  final String _baseUrl;

  Future<NightPreview> generate(PreviewInput input) async {
    try {
      final url = Uri.parse('$_baseUrl/api/preview');
      final raw = await _fetch(url, jsonEncode(input.toRequestJson()));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final preview = decoded['preview'];
      if (preview is Map<String, dynamic>) {
        final parsed = NightPreview.fromJson(preview);
        if (parsed != null) return parsed;
      }
      return buildLocalNightPreview(input);
    } catch (_) {
      return buildLocalNightPreview(input);
    }
  }
}
