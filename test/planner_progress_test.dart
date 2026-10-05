import 'dart:async';

import 'package:campon/planner/plan_models.dart';
import 'package:campon/planner/plan_service.dart';
import 'package:campon/planner/planner_input_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlanInput _input() => PlanInput(
      query: '주말 강원', date: '2026-08-01', people: 2, hasCar: true,
      experience: '초보', region: '강원', lat: 37.8, lon: 128.9,
      preferences: const [], equipment: const [], candidates: const [],
    );

void main() {
  testWidgets('플랜을 기다리는 동안 단계 진행 바가 앞으로 나아간다', (tester) async {
    // 응답을 붙잡아 두고 대기 화면만 관찰한다.
    final pending = Completer<String>();
    final service = PlanService(
      fetcher: (url, body) => pending.future,
      baseUrl: 'https://example.test',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlannerInputScreen(
          prefill: _input(),
          onGenerated: (_) {},
          onBack: () {},
          service: service,
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('플랜 생성'));
    await tester.pump();

    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('입력한 조건을 정리하고 있어요'), findsOneWidget);

    final start = tester.widget<LinearProgressIndicator>(bar).value!;
    await tester.pump(const Duration(seconds: 6));
    final later = tester.widget<LinearProgressIndicator>(bar).value!;

    expect(later, greaterThan(start));
    expect(find.text('1/4'), findsNothing);

    // 응답 전에는 100%까지 차지 않는다.
    await tester.pump(const Duration(seconds: 30));
    expect(tester.widget<LinearProgressIndicator>(bar).value, lessThan(1.0));
    expect(find.text('4/4'), findsOneWidget);

    // 대기 중인 티커를 정리한다.
    await tester.pumpWidget(const SizedBox());
    pending.complete('{}');
  });
}
