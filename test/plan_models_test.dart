import 'package:flutter_test/flutter_test.dart';
import 'package:campon/planner/plan_models.dart';

void main() {
  test('CampPlan.fromJson parses full payload', () {
    final json = {
      'summary': {'title': '강원 오토캠핑', 'mood': '편안하게', 'oneLiner': '2명 강원 캠핑'},
      'weather': {
        'grade': 'caution', 'nightLowC': 6, 'precipPct': 40, 'windMs': 4.0,
        'diurnalRangeC': 12, 'advice': '겉옷 챙기세요.'
      },
      'campsites': [
        {'name': '가리왕산', 'reason': '접근성 좋음'}
      ],
      'checklist': [
        {'category': '취사', 'items': ['버너', '코펠']}
      ],
      'timeline': [
        {'time': '14:00', 'title': '도착', 'detail': '설치'}
      ],
    };
    final plan = CampPlan.fromJson(json);
    expect(plan.summary.title, '강원 오토캠핑');
    expect(plan.weather.grade, WeatherGrade.caution);
    expect(plan.campsites.first.name, '가리왕산');
    expect(plan.checklist.first.items.length, 2);
    expect(plan.timeline.first.time, '14:00');
  });

  test('CampPlan.fromJson tolerates missing and malformed fields', () {
    final plan = CampPlan.fromJson({'summary': {'title': 'T'}});
    expect(plan.summary.title, 'T');
    expect(plan.summary.oneLiner, isA<String>());
    expect(plan.weather.grade, WeatherGrade.good);
    expect(plan.campsites, isEmpty);
  });

  test('local fallback fills all sections', () {
    final input = PlanInput(
      query: '주말 강원', date: '2026-08-01', people: 2, hasCar: true,
      experience: '초보', region: '강원', lat: 37.8, lon: 128.9,
      preferences: const [], equipment: const [], candidates: const [],
    );
    final plan = buildLocalFallbackPlan(input);
    expect(plan.campsites, isNotEmpty);
    expect(plan.checklist, isNotEmpty);
    expect(plan.timeline.length, greaterThanOrEqualTo(3));
  });

  test('PlanInput.toRequestJson has the proxy contract shape', () {
    final input = PlanInput(
      query: 'q', date: '2026-08-01', people: 2, hasCar: false,
      experience: '중급', region: '경기', lat: 37.4, lon: 127.5,
      preferences: const ['SHOWER'], equipment: const ['TENT'],
      candidates: [
        PlanCandidate(name: 'A', facility: const ['ELECTRICITY'], equipmentRental: const [])
      ],
    );
    final json = input.toRequestJson();
    expect(json['query'], 'q');
    expect((json['context'] as Map)['people'], 2);
    expect((json['coords'] as Map)['lat'], 37.4);
    expect((json['candidates'] as List).first['name'], 'A');
  });
}
