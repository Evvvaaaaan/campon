import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/planner/plan_models.dart';
import 'package:campon/planner/planner_result_screen.dart';

CampPlan _plan() => CampPlan.fromJson({
      'summary': {'title': '강원 오토캠핑', 'mood': '편안하게', 'oneLiner': '2명 강원 캠핑'},
      'weather': {
        'grade': 'caution', 'nightLowC': 6, 'precipPct': 40, 'windMs': 4.0,
        'diurnalRangeC': 12, 'advice': '겉옷을 챙기세요.'
      },
      'campsites': [
        {'name': '가리왕산 캠핑장', 'reason': '접근성이 좋아요'}
      ],
      'checklist': [
        {'category': '취사', 'items': ['버너', '코펠']}
      ],
      'timeline': [
        {'time': '14:00', 'title': '도착', 'detail': '설치'},
        {'time': '17:00', 'title': '저녁', 'detail': '식사'},
        {'time': '22:00', 'title': '취침', 'detail': '휴식'},
      ],
    });

void main() {
  testWidgets('renders all five sections and fires checklist handoff', (tester) async {
    List<String>? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlannerResultScreen(
          plan: _plan(),
          onBack: () {},
          onSendToChecklist: (items) => sent = items,
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('강원 오토캠핑'), findsOneWidget);
    expect(find.text('캠핑 날씨'), findsOneWidget);
    expect(find.text('추천 캠핑장'), findsOneWidget);
    expect(find.text('스마트 준비물'), findsOneWidget);
    expect(find.text('하루 타임라인'), findsOneWidget);
    expect(find.text('주의'), findsOneWidget);

    await tester.tap(find.text('체크리스트로 보내기'));
    await tester.pump();
    expect(sent, ['버너', '코펠']);
  });
}
