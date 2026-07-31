import 'dart:convert';

import 'package:campon/preview/preview_models.dart';
import 'package:campon/preview/preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

PreviewInput input({
  int? nightLowC = 15,
  double? windMs = 1.2,
  int? cloudPct = 5,
  int moonInterferencePct = 3,
  int moonIlluminationPct = 4,
}) => PreviewInput(
  place: '홍천 별빛캠핑장',
  date: DateTime(2026, 8, 15),
  moonIlluminationPct: moonIlluminationPct,
  moonInterferencePct: moonInterferencePct,
  score: 91,
  grade: 'milkyWay',
  cloudPct: cloudPct,
  precipPct: 0,
  windMs: windMs,
  nightLowC: nightLowC,
);

void main() {
  group('요청 본문', () {
    test('날짜와 수치를 프록시 계약대로 담는다', () {
      final json = input().toRequestJson();

      expect(json['place'], '홍천 별빛캠핑장');
      expect(json['date'], '2026-08-15');
      expect((json['weather'] as Map)['nightLowC'], 15);
      expect((json['weather'] as Map)['windMs'], 1.2);
      expect((json['sky'] as Map)['moonInterferencePct'], 3);
    });

    test('날씨를 모르면 null로 보낸다', () {
      final json = input(
        nightLowC: null,
        windMs: null,
        cloudPct: null,
      ).toRequestJson();

      expect((json['weather'] as Map)['nightLowC'], isNull);
      expect((json['weather'] as Map)['cloudPct'], isNull);
    });
  });

  group('응답 파싱', () {
    test('정상 응답을 읽는다', () {
      final preview = NightPreview.fromJson({
        'title': '8월 15일 밤, 홍천',
        'lines': ['한 줄', '두 줄', '세 줄'],
        'closing': '마무리',
      });

      expect(preview, isNotNull);
      expect(preview!.lines.length, 3);
      expect(preview.closing, '마무리');
    });

    test('줄이 세 개 미만이면 받아들이지 않는다', () {
      expect(
        NightPreview.fromJson({
          'title': '제목',
          'lines': ['한 줄', '두 줄'],
        }),
        isNull,
      );
    });

    test('제목이나 lines 타입이 어긋나면 받아들이지 않는다', () {
      expect(NightPreview.fromJson({'lines': ['a', 'b', 'c']}), isNull);
      expect(NightPreview.fromJson({'title': '제목', 'lines': '문자열'}), isNull);
      expect(
        NightPreview.fromJson({
          'title': '   ',
          'lines': ['a', 'b', 'c'],
        }),
        isNull,
      );
    });

    test('빈 줄은 걸러낸다', () {
      final preview = NightPreview.fromJson({
        'title': '제목',
        'lines': ['한 줄', '  ', '두 줄', '', '세 줄'],
      });

      expect(preview!.lines, ['한 줄', '두 줄', '세 줄']);
    });
  });

  group('로컬 장면', () {
    test('밤 기온에 따라 첫 줄이 달라진다', () {
      final warm = buildLocalNightPreview(input(nightLowC: 24)).lines.first;
      final mild = buildLocalNightPreview(input(nightLowC: 15)).lines.first;
      final cold = buildLocalNightPreview(input(nightLowC: 3)).lines.first;

      expect(warm, contains('열기'));
      expect(mild, contains('서늘'));
      expect(cold, contains('입김'));
    });

    test('바람이 세면 팩을 확인하는 장면이 나온다', () {
      final calm = buildLocalNightPreview(input(windMs: 1)).lines[1];
      final windy = buildLocalNightPreview(input(windMs: 7)).lines[1];

      expect(calm, contains('흔들리지 않고'));
      expect(windy, contains('팩'));
    });

    test('달이 없고 맑으면 별이 두 배라고 말한다', () {
      final line = buildLocalNightPreview(input()).lines[2];
      expect(line, contains('달이 없어서'));
    });

    test('달이 차 있으면 조도를 그대로 말한다', () {
      final line = buildLocalNightPreview(
        input(moonInterferencePct: 60, moonIlluminationPct: 74),
      ).lines[2];
      expect(line, contains('74%'));
    });

    test('구름이 많으면 별 대신 불빛을 본다', () {
      final line = buildLocalNightPreview(input(cloudPct: 90)).lines[2];
      expect(line, contains('불빛'));
    });

    test('제목에 날짜와 장소가 들어간다', () {
      final preview = buildLocalNightPreview(input());
      expect(preview.title, '8월 15일 밤, 홍천 별빛캠핑장');
      expect(preview.lines.length, 5);
    });
  });

  group('PreviewService', () {
    test('프록시 응답을 그대로 쓴다', () async {
      final service = PreviewService(
        baseUrl: 'https://example.test',
        fetcher: (_, _) async => jsonEncode({
          'preview': {
            'title': 'AI가 쓴 제목',
            'lines': ['첫 줄', '둘째 줄', '셋째 줄'],
            'closing': 'AI 마무리',
          },
        }),
      );

      final preview = await service.generate(input());
      expect(preview.title, 'AI가 쓴 제목');
      expect(preview.closing, 'AI 마무리');
    });

    test('응답이 비면 로컬 장면으로 대체한다', () async {
      final service = PreviewService(
        baseUrl: 'https://example.test',
        fetcher: (_, _) async => jsonEncode({'preview': null}),
      );

      final preview = await service.generate(input());
      expect(preview.title, contains('홍천 별빛캠핑장'));
      expect(preview.lines.length, 5);
    });

    test('네트워크가 죽어도 장면이 나온다', () async {
      final service = PreviewService(
        baseUrl: 'https://example.test',
        fetcher: (_, _) async => throw Exception('down'),
      );

      final preview = await service.generate(input());
      expect(preview.lines, isNotEmpty);
    });

    test('줄이 모자란 응답은 신뢰하지 않고 대체한다', () async {
      final service = PreviewService(
        baseUrl: 'https://example.test',
        fetcher: (_, _) async => jsonEncode({
          'preview': {'title': '제목', 'lines': ['한 줄']},
        }),
      );

      final preview = await service.generate(input());
      expect(preview.lines.length, 5);
    });
  });
}
