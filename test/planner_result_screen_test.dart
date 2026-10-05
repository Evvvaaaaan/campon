import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/motion/motion.dart';
import 'package:campon/planner/plan_models.dart';
import 'package:campon/planner/planner_result_screen.dart';

CampPlan _plan({PlanGenerationSource source = PlanGenerationSource.fallback}) =>
    CampPlan.fromJson({
      'summary': {'title': '강원 오토캠핑', 'mood': '편안하게', 'oneLiner': '2명 강원 캠핑'},
      'weather': {
        'grade': 'caution',
        'nightLowC': 6,
        'precipPct': 40,
        'windMs': 4.0,
        'diurnalRangeC': 12,
        'advice': '겉옷을 챙기세요.',
      },
      'campsites': [
        {'name': '가리왕산 캠핑장', 'reason': '접근성이 좋아요'},
        {'name': '이름이 어긋난 캠핑장', 'reason': '후보 목록에 없어요'},
      ],
      'checklist': [
        {
          'category': '취사',
          'items': ['버너', '코펠'],
        },
      ],
      'timeline': [
        {'time': '14:00', 'title': '도착', 'detail': '설치'},
        {'time': '17:00', 'title': '저녁', 'detail': '식사'},
        {'time': '22:00', 'title': '취침', 'detail': '휴식'},
      ],
    }, source: source);

void main() {
  testWidgets('renders all five sections and fires checklist handoff', (
    tester,
  ) async {
    List<String>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerResultScreen(
            plan: _plan(),
            onBack: () {},
            onSendToChecklist: (items) => sent = items,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('강원 오토캠핑'), findsOneWidget);
    expect(find.text('기본 준비 가이드'), findsOneWidget);
    expect(find.text('캠핑 날씨'), findsOneWidget);
    expect(find.text('추천 캠핑장'), findsOneWidget);
    expect(find.text('스마트 준비물'), findsOneWidget);
    expect(find.text('하루 타임라인'), findsOneWidget);
    expect(find.text('주의'), findsOneWidget);

    await tester.tap(find.text('체크리스트로 보내기'));
    await tester.pump();
    expect(sent, ['버너', '코펠']);
  });

  testWidgets('모델이 생성한 결과는 AI 캠핑 플랜으로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerResultScreen(
            plan: _plan(source: PlanGenerationSource.ai),
            onBack: () {},
            onSendToChecklist: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('AI 캠핑 플랜'), findsOneWidget);
    expect(find.text('기본 준비 가이드'), findsNothing);
  });

  testWidgets('예보가 없으면 수치를 만들지 않고 상태를 알린다', (tester) async {
    final plan = CampPlan.fromJson({
      'summary': {'title': '강원 캠핑', 'mood': '안전하게', 'oneLiner': '준비해요'},
      'weather': {
        'grade': 'unavailable',
        'nightLowC': null,
        'precipPct': null,
        'windMs': null,
        'diurnalRangeC': null,
        'advice': '선택한 날짜는 단기 예보 범위 밖이에요.',
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerResultScreen(
            plan: plan,
            onBack: () {},
            onSendToChecklist: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('예보 없음'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('예보 범위 밖'), findsOneWidget);
    expect(find.textContaining('캠핑 좋음'), findsNothing);
  });

  testWidgets('후보 목록에 있는 추천 캠핑장만 눌러서 상세로 간다', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerResultScreen(
            plan: _plan(),
            onBack: () {},
            onSendToChecklist: (_) {},
            openableCampsites: const {'가리왕산 캠핑장'},
            onOpenCampsite: opened.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // 추천 캠핑장 카드는 접힌 화면 아래에 있다. 눌리는 자리까지 올린다.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('가리왕산 캠핑장'));
    await tester.pump();
    expect(opened, ['가리왕산 캠핑장']);

    // 글자뿐 아니라 줄 전체가 눌린다.
    final row = find.ancestor(
      of: find.text('가리왕산 캠핑장'),
      matching: find.byType(Pressable),
    );
    final rect = tester.getRect(row.first);
    await tester.tapAt(Offset(rect.right - 60, rect.center.dy));
    await tester.pump();
    expect(opened, ['가리왕산 캠핑장', '가리왕산 캠핑장']);
    opened.clear();

    // 후보 목록에 없는 이름은 눌러도 아무 일도 없다.
    await tester.tap(find.text('이름이 어긋난 캠핑장'), warnIfMissed: false);
    await tester.pump();
    expect(opened, isEmpty);
  });
}
