import 'dart:async';
import 'dart:convert';

import 'package:campon/weather/campsite_weather_card.dart';
import 'package:campon/weather/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// api.open-meteo.com이 실제로 돌려준 응답을 그대로 붙여 둔 것.
/// 필드 이름이나 단위가 바뀌면 이 테스트가 먼저 깨진다.
const _realResponse = '''
{"latitude":37.8,"longitude":128.1875,"utc_offset_seconds":32400,
"timezone":"Asia/Seoul",
"current_units":{"temperature_2m":"°C","wind_speed_10m":"km/h"},
"current":{"time":"2026-08-21T14:15","interval":900,"temperature_2m":23.5,
"apparent_temperature":28.0,"relative_humidity_2m":91,"weather_code":55,
"wind_speed_10m":2.3},
"daily":{"time":["2026-08-21","2026-08-22","2026-08-23"],
"weather_code":[61,53,53],"temperature_2m_max":[24.5,25.8,28.0],
"temperature_2m_min":[21.1,21.4,22.3],
"precipitation_probability_max":[100,100,22]}}
''';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('실제 응답을 그대로 넣으면 그곳의 날씨가 뜬다', (tester) async {
    await tester.pumpWidget(
      _host(
        CampsiteWeatherCard(
          lat: 37.8213,
          lon: 128.1567,
          service: WeatherService(fetcher: (_) async => _realResponse),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('24°'), findsOneWidget);
    expect(find.text('이슬비 · 체감 28°'), findsOneWidget);
    expect(find.text('0.6m/s'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('25° / 21°'), findsOneWidget);
    // 실제 응답의 강수 확률은 [100, 100, 22]다.
    expect(find.text('비 100%'), findsNWidgets(2));
    expect(find.text('비 22%'), findsOneWidget);
    // 비 확률이 100%면 방수 장비를 알려야 한다.
    expect(find.textContaining('방수'), findsOneWidget);
    expect(find.textContaining('Open-Meteo'), findsOneWidget);
  });

  testWidgets('불러오는 동안에는 안내와 함께 기다린다', (tester) async {
    final gate = Completer<String>();
    await tester.pumpWidget(
      _host(
        CampsiteWeatherCard(
          lat: 37.8213,
          lon: 128.1567,
          service: WeatherService(fetcher: (_) => gate.future),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('날씨를 불러오는 중이에요.'), findsOneWidget);

    gate.complete(_realResponse);
    await tester.pumpAndSettle();
    expect(find.text('24°'), findsOneWidget);
  });

  testWidgets('실패하면 다시 시도할 수 있고, 눌러서 복구된다', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _host(
        CampsiteWeatherCard(
          lat: 37.8213,
          lon: 128.1567,
          service: WeatherService(
            fetcher: (_) async {
              attempts++;
              if (attempts == 1) throw Exception('offline');
              return _realResponse;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('지금은 날씨를 불러오지 못했어요.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('24°'), findsOneWidget);
  });

  testWidgets('서비스를 주입하지 않아도 화면이 멈추지 않는다', (tester) async {
    // 상세 화면은 서비스를 주입하지 않는다. 테스트 환경에서는 실제 통신이 막히므로
    // 실패 상태로 내려앉아야 하고, 로딩이 남아 pumpAndSettle을 붙잡아서는 안 된다.
    await tester.pumpWidget(
      _host(const CampsiteWeatherCard(lat: 37.8213, lon: 128.1567)),
    );
    await tester.pumpAndSettle();

    expect(find.text('날씨를 불러오는 중이에요.'), findsNothing);
    expect(find.text('지금은 날씨를 불러오지 못했어요.'), findsOneWidget);
  });

  test('날짜 라벨은 오늘·내일·모레만 말로 적는다', () {
    final now = DateTime(2026, 8, 21);
    expect(dayLabel(DateTime(2026, 8, 21), now: now), '오늘');
    expect(dayLabel(DateTime(2026, 8, 22), now: now), '내일');
    expect(dayLabel(DateTime(2026, 8, 23), now: now), '모레');
    expect(dayLabel(DateTime(2026, 8, 24), now: now), '8/24');
  });

  test('붙여 둔 실제 응답이 지금도 해석된다', () {
    final parsed = parseCampsiteWeather(
      jsonDecode(_realResponse) as Map<String, dynamic>,
    );
    expect(parsed, isNotNull);
    expect(parsed!.days, hasLength(3));
  });
}
