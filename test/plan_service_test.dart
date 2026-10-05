import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/planner/plan_models.dart';
import 'package:campon/planner/plan_service.dart';

PlanInput _input() => PlanInput(
  query: '주말 강원',
  date: '2026-08-01',
  people: 2,
  hasCar: true,
  experience: '초보',
  region: '강원',
  lat: 37.8,
  lon: 128.9,
  preferences: const [],
  equipment: const [],
  candidates: const [],
);

void main() {
  test('parses proxy plan payload', () async {
    final svc = PlanService(
      fetcher: (url, body) async => jsonEncode({
        'source': 'llm',
        'plan': {
          'summary': {'title': 'T', 'mood': 'M', 'oneLiner': 'O'},
          'weather': {
            'grade': 'risk',
            'nightLowC': 2,
            'precipPct': 80,
            'windMs': 10.0,
            'diurnalRangeC': 16,
            'advice': 'A',
          },
          'campsites': [
            {'name': 'C', 'reason': 'R'},
          ],
          'checklist': [
            {
              'category': 'K',
              'items': ['a'],
            },
          ],
          'timeline': [
            {'time': '14:00', 'title': 'X', 'detail': 'Y'},
            {'time': '17:00', 'title': 'X2', 'detail': 'Y2'},
            {'time': '22:00', 'title': 'X3', 'detail': 'Y3'},
          ],
        },
      }),
    );
    final plan = await svc.generate(_input());
    expect(plan.summary.title, 'T');
    expect(plan.weather.grade, WeatherGrade.risk);
    expect(plan.source, PlanGenerationSource.ai);
  });

  test('falls back locally on fetch error', () async {
    final svc = PlanService(
      fetcher: (url, body) async => throw Exception('network'),
    );
    final plan = await svc.generate(_input());
    expect(plan.campsites, isNotEmpty);
    expect(plan.weather.grade, WeatherGrade.unavailable);
    expect(plan.weather.nightLowC, isNull);
    expect(plan.weather.advice, isNot(contains('안정적')));
    expect(plan.source, PlanGenerationSource.fallback);
  });

  test('falls back on null plan', () async {
    final svc = PlanService(
      fetcher: (url, body) async => jsonEncode({'plan': null}),
    );
    final plan = await svc.generate(_input());
    expect(plan.timeline.length, greaterThanOrEqualTo(3));
    expect(plan.source, PlanGenerationSource.fallback);
  });

  test('sends the request contract to the proxy url', () async {
    Uri? seenUrl;
    String? seenBody;
    final svc = PlanService(
      baseUrl: 'https://example.test',
      fetcher: (url, body) async {
        seenUrl = url;
        seenBody = body;
        return jsonEncode({'plan': null});
      },
    );
    await svc.generate(_input());
    expect(seenUrl.toString(), 'https://example.test/api/plan');
    expect(jsonDecode(seenBody!)['query'], '주말 강원');
  });

  test('reads a real response that arrives in multiple chunks', () async {
    // Regression test for the default (non-injected) HTTP fetcher: the plan
    // response must be fully read even when it arrives over more than one
    // TCP read, e.g. a large LLM-generated plan on a slow connection.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final plan = jsonEncode({
      'summary': {'title': 'T', 'mood': 'M', 'oneLiner': 'O'},
    });
    unawaited(
      server.first.then((req) async {
        req.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        req.response.add(
          utf8.encode('{"plan": ${plan.substring(0, plan.length ~/ 2)}'),
        );
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        req.response.add(utf8.encode('${plan.substring(plan.length ~/ 2)}}'));
        await req.response.close();
      }),
    );

    final svc = PlanService(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    try {
      final result = await svc.generate(_input());
      expect(result.summary.title, 'T');
    } finally {
      await server.close(force: true);
    }
  });
}
