import 'dart:async';
import 'dart:convert';

import 'package:campon/motion/motion.dart';
import 'package:campon/preview/night_preview_screen.dart';
import 'package:campon/preview/preview_models.dart';
import 'package:campon/preview/preview_service.dart';
import 'package:campon/tonight/night_models.dart';
import 'package:campon/tonight/tonight_card.dart';
import 'package:campon/tonight/tonight_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 오늘부터 시작하는 맑은 밤 예보. 카드가 실제로 도는 시각을 그대로 쓴다.
String _clearForecastJson({double cloud = 4}) {
  final start = DateTime.now();
  final times = <String>[];
  for (var hour = 0; hour < 15 * 24; hour++) {
    final at = DateTime(
      start.year,
      start.month,
      start.day,
    ).add(Duration(hours: hour));
    times.add(
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}T'
      '${at.hour.toString().padLeft(2, '0')}:00',
    );
  }
  return jsonEncode({
    'current': {'temperature_2m': 30},
    'hourly': {
      'time': times,
      'cloud_cover': List.filled(times.length, cloud),
      'precipitation_probability': List.filled(times.length, 0),
      'wind_speed_10m': List.filled(times.length, 4.3),
      'temperature_2m': List.filled(times.length, 14),
    },
  });
}

Widget _hostCard({
  required TonightService service,
  Future<String?> Function()? destinationLoader,
  VoidCallback? onExplore,
  NightPreviewRequested? onPreview,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: TonightCard(
        regionName: '강원',
        lat: 37.82,
        lon: 128.16,
        service: service,
        destinationLoader: destinationLoader,
        onExplore: onExplore ?? () {},
        onPreview: onPreview ?? (_, _, _) {},
      ),
    ),
  ),
);

/// 카드가 로딩을 끝내고 등장 애니메이션까지 마치도록 진행시킨다.
Future<void> _settleCard(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  testWidgets('불러오는 동안에는 스켈레톤을 보여준다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(
          fetcher: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return _clearForecastJson();
          },
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(Shimmer), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await _settleCard(tester);
    expect(find.byType(Shimmer), findsNothing);
  });

  testWidgets('점수·등급·희소성 문구가 함께 나온다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => _clearForecastJson()),
      ),
    );
    await _settleCard(tester);

    expect(find.textContaining('/ 100'), findsOneWidget);
    expect(find.textContaining('올해 남은 달 없는 토요일 밤'), findsOneWidget);
    expect(find.textContaining('구름 4%'), findsOneWidget);
    expect(find.textContaining('바람'), findsOneWidget);
    expect(find.text('이 밤 미리 보기'), findsOneWidget);
  });

  testWidgets('지역명으로 시작해 캠핑장 이름이 오면 바꿔 단다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => _clearForecastJson()),
        destinationLoader: () async => '홍천 별빛캠핑장',
      ),
    );
    await _settleCard(tester);

    expect(find.textContaining('홍천 별빛캠핑장'), findsOneWidget);
  });

  testWidgets('캠핑장 이름을 못 가져오면 지역명을 쓴다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => _clearForecastJson()),
        destinationLoader: () async => null,
      ),
    );
    await _settleCard(tester);

    expect(find.textContaining('강원 밤하늘'), findsOneWidget);
  });

  testWidgets('위치 권한이 있으면 지금 기온과의 대비를 덧붙인다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(
          fetcher: (_) async => _clearForecastJson(),
          location: () async => (lat: 37.56, lon: 126.97),
        ),
      ),
    );
    await _settleCard(tester);

    expect(find.textContaining('지금 계신 곳 30℃'), findsOneWidget);
    expect(find.textContaining('그날 밤 거기 14℃'), findsOneWidget);
  });

  testWidgets('위치 조회가 멈춰도 카드는 먼저 뜬다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(
          fetcher: (_) async => _clearForecastJson(),
          location: () => Completer<({double lat, double lon})?>().future,
        ),
      ),
    );
    await _settleCard(tester);

    expect(find.byType(Shimmer), findsNothing);
    expect(find.textContaining('/ 100'), findsOneWidget);
    expect(find.textContaining('지금 계신 곳'), findsNothing);
  });

  testWidgets('날씨 조회가 실패해도 달 정보로 카드를 채운다', (tester) async {
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => throw Exception('down')),
      ),
    );
    await _settleCard(tester);

    expect(find.byType(Shimmer), findsNothing);
    expect(find.textContaining('/ 100'), findsOneWidget);
    expect(find.textContaining('구름'), findsNothing);
    expect(find.textContaining('올해 남은 달 없는 토요일 밤'), findsOneWidget);
  });

  testWidgets('미리보기 버튼은 그 밤의 수치를 그대로 넘긴다', (tester) async {
    NightSky? handed;
    String? handedPlace;

    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => _clearForecastJson()),
        destinationLoader: () async => '홍천 별빛캠핑장',
        onPreview: (night, place, _) {
          handed = night;
          handedPlace = place;
        },
      ),
    );
    await _settleCard(tester);

    await tester.tap(find.text('이 밤 미리 보기'));
    await tester.pump();

    expect(handed, isNotNull);
    expect(handed!.cloudPct, 4);
    expect(handed!.nightLowC, 14);
    expect(handedPlace, '홍천 별빛캠핑장');
  });

  testWidgets('캠핑장 보기 버튼은 둘러보기로 연결된다', (tester) async {
    var explored = false;
    await tester.pumpWidget(
      _hostCard(
        service: TonightService(fetcher: (_) async => _clearForecastJson()),
        onExplore: () => explored = true,
      ),
    );
    await _settleCard(tester);

    await tester.tap(find.text('캠핑장 보기'));
    await tester.pump();

    expect(explored, isTrue);
  });

  group('밤 미리보기 화면', () {
    PreviewInput sampleInput() => PreviewInput(
      place: '홍천 별빛캠핑장',
      date: DateTime(2026, 8, 15),
      moonIlluminationPct: 4,
      moonInterferencePct: 2,
      score: 91,
      grade: 'milkyWay',
      cloudPct: 4,
      precipPct: 0,
      windMs: 1.2,
      nightLowC: 14,
    );

    /// 한 번에 크게 건너뛰면 애니메이션이 그 시각부터 시작한 것으로 잡힌다.
    /// 실제 프레임처럼 잘게 나눠 진행시킨다.
    Future<void> advance(WidgetTester tester, Duration total) async {
      const step = Duration(milliseconds: 100);
      for (var passed = Duration.zero; passed < total; passed += step) {
        await tester.pump(step);
      }
    }

    /// flutter_animate의 fadeIn은 위젯을 트리에 두고 투명도만 올린다.
    /// 그래서 "보이는지"는 finder가 아니라 투명도로 확인해야 한다.
    double opacityOf(WidgetTester tester, Finder text) {
      final fade = find.ancestor(
        of: text,
        matching: find.byType(FadeTransition),
      );
      return tester.widget<FadeTransition>(fade.first).opacity.value;
    }

    testWidgets('장면은 한 줄씩 순서대로 드러난다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NightPreviewScreen(
            input: sampleInput(),
            actionLabel: '이 캠핑장으로 준비 시작',
            onAction: () {},
            service: PreviewService(
              baseUrl: 'https://example.test',
              fetcher: (_, _) async => throw Exception('offline'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final firstLine = find.textContaining('밤 9시');
      final lastLine = find.textContaining('텐트 지퍼');
      final closing = find.text('이 밤은 아직 아무도 예약하지 않았다.');

      // 중간 시점: 첫 줄은 이미 보이지만 마지막 줄과 마무리는 아직 투명하다.
      await advance(tester, const Duration(seconds: 3));
      expect(opacityOf(tester, firstLine), greaterThan(0));
      expect(opacityOf(tester, lastLine), 0);
      expect(opacityOf(tester, closing), 0);

      // 연출이 끝나면 모두 완전히 보인다.
      await advance(tester, const Duration(seconds: 12));
      expect(opacityOf(tester, firstLine), 1);
      expect(opacityOf(tester, lastLine), 1);
      expect(opacityOf(tester, closing), 1);
    });

    testWidgets('장면 내용과 마무리 문구가 모두 들어간다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NightPreviewScreen(
            input: sampleInput(),
            actionLabel: '이 캠핑장으로 준비 시작',
            onAction: () {},
            service: PreviewService(
              baseUrl: 'https://example.test',
              fetcher: (_, _) async {
                await Future<void>.delayed(const Duration(milliseconds: 300));
                throw Exception('offline');
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('그날 밤을 그리는 중'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('8월 15일 밤, 홍천 별빛캠핑장'), findsOneWidget);

      // 마지막 줄과 마무리까지 흐르도록 충분히 진행시킨다.
      await tester.pump(const Duration(seconds: 8));
      expect(find.textContaining('달이 없어서'), findsOneWidget);
      expect(find.text('이 밤은 아직 아무도 예약하지 않았다.'), findsOneWidget);
      expect(find.text('이 캠핑장으로 준비 시작'), findsOneWidget);
    });

    testWidgets('액션 버튼은 화면을 닫고 콜백을 부른다', (tester) async {
      var acted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NightPreviewScreen(
            input: sampleInput(),
            actionLabel: '이 캠핑장으로 준비 시작',
            onAction: () => acted = true,
            service: PreviewService(
              baseUrl: 'https://example.test',
              fetcher: (_, _) async => jsonEncode({
                'preview': {
                  'title': '제목',
                  'lines': ['첫 줄', '둘째 줄', '셋째 줄'],
                  'closing': '마무리',
                },
              }),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));

      await tester.tap(find.text('이 캠핑장으로 준비 시작'));
      await tester.pump();

      expect(acted, isTrue);
    });
  });
}
