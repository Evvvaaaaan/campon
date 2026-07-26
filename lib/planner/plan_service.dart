import 'dart:convert';
import 'dart:io';

import 'plan_models.dart';

typedef PlanFetcher = Future<String> Function(Uri url, String body);

const _defaultBase = String.fromEnvironment(
  'PLAN_PROXY_URL',
  defaultValue: 'https://campon-ai-proxy.vercel.app',
);

Future<String> _httpFetcher(Uri url, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(url);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.add(utf8.encode(body));
    final res = await req.close();
    return res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

class PlanService {
  PlanService({PlanFetcher? fetcher, String? baseUrl})
      : _fetcher = fetcher ?? _httpFetcher,
        _baseUrl = baseUrl ?? _defaultBase;

  final PlanFetcher _fetcher;
  final String _baseUrl;

  Future<CampPlan> generate(PlanInput input) async {
    try {
      final url = Uri.parse('$_baseUrl/api/plan');
      final raw = await _fetcher(url, jsonEncode(input.toRequestJson()));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final plan = decoded['plan'];
      if (plan is Map<String, dynamic>) return CampPlan.fromJson(plan);
      return buildLocalFallbackPlan(input);
    } catch (_) {
      return buildLocalFallbackPlan(input);
    }
  }
}
