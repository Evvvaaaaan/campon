import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plan_models.dart';

typedef PlanFetcher = Future<String> Function(Uri url, String body);

// Azure Functions host. The real name is confirmed at deploy time and can be
// overridden with --dart-define=PLAN_PROXY_URL=https://<app>.azurewebsites.net
const _defaultBase = String.fromEnvironment(
  'PLAN_PROXY_URL',
  defaultValue: 'https://campon-ai-proxy.azurewebsites.net',
);

Future<String> _httpFetcher(Uri url, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(url);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.add(utf8.encode(body));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
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
      if (plan is Map<String, dynamic>) {
        final source = decoded['source'] == 'llm'
            ? PlanGenerationSource.ai
            : PlanGenerationSource.fallback;
        return CampPlan.fromJson(plan, source: source);
      }
      debugPrint('[PlanService] 응답에 plan 필드가 없어 로컬 폴백을 사용합니다: $raw');
      return buildLocalFallbackPlan(input);
    } catch (e) {
      debugPrint('[PlanService] AI 플랜 요청 실패, 로컬 폴백을 사용합니다: $e');
      return buildLocalFallbackPlan(input);
    }
  }
}
