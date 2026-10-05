import 'dart:convert';

import 'package:campon/weather/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Open-Meteo 응답 모양의 가짜 날씨.
String _weatherJson({
  double temperature = 12.4,
  double apparent = 10.6,
  double windKmh = 10.8,
  int humidity = 63,
  int currentCode = 3,
  List<int> dailyCodes = const [61, 0, 2],
  List<double> highs = const [16.2, 19.4, 21.0],
  List<double> lows = const [7.5, 8.1, 9.9],
  List<int> precip = const [70, 10, 0],
}) => jsonEncode({
  'current': {
    'temperature_2m': temperature,
    'apparent_temperature': apparent,
    'relative_humidity_2m': humidity,
    'weather_code': currentCode,
    'wind_speed_10m': windKmh,
  },
  'daily': {
    'time': ['2026-08-21', '2026-08-22', '2026-08-23'],
    'weather_code': dailyCodes,
    'temperature_2m_max': highs,
    'temperature_2m_min': lows,
    'precipitation_probability_max': precip,
  },
});

void main() {
  group('Open-Meteo 응답 해석', () {
    test('현재 날씨와 일별 예보를 읽는다', () async {
      final weather = await WeatherService(
        fetcher: (_) async => _weatherJson(),
      ).load(lat: 37.82, lon: 128.16);

      expect(weather, isNotNull);
      expect(weather!.temperatureC, 12);
      expect(weather.feelsLikeC, 11);
      expect(weather.humidityPct, 63);
      expect(weather.condition, WeatherCondition.cloudy);
      // km/h로 오는 값을 m/s로 바꿔 들고 있어야 한다.
      expect(weather.windMs, 3.0);

      expect(weather.days, hasLength(3));
      expect(weather.days.first.date, DateTime(2026, 8, 21));
      expect(weather.days.first.condition, WeatherCondition.rain);
      expect(weather.days.first.highC, 16);
      expect(weather.days.first.lowC, 8);
      expect(weather.days.first.precipPct, 70);
      expect(weather.days.last.condition, WeatherCondition.partlyCloudy);
    });

    test('현재 기온이 없으면 보여줄 것이 없으므로 null이다', () async {
      final weather = await WeatherService(
        fetcher: (_) async => jsonEncode({
          'current': {'weather_code': 0},
        }),
      ).load(lat: 37.82, lon: 128.16);

      expect(weather, isNull);
    });

    test('일별 예보가 비어도 현재 날씨는 살린다', () async {
      final weather = await WeatherService(
        fetcher: (_) async => jsonEncode({
          'current': {'temperature_2m': 21.0, 'weather_code': 0},
        }),
      ).load(lat: 37.82, lon: 128.16);

      expect(weather, isNotNull);
      expect(weather!.temperatureC, 21);
      expect(weather.days, isEmpty);
      expect(weather.caution, isNull);
    });

    test('네트워크가 실패하면 null을 준다', () async {
      final weather = await WeatherService(
        fetcher: (_) async => throw Exception('offline'),
      ).load(lat: 37.82, lon: 128.16);

      expect(weather, isNull);
    });

    test('요청 URL에 키 없이 좌표와 시간대만 붙는다', () async {
      late Uri seen;
      await WeatherService(
        fetcher: (url) async {
          seen = url;
          return _weatherJson();
        },
      ).load(lat: 37.8213, lon: 128.1567);

      expect(seen.host, 'api.open-meteo.com');
      expect(seen.queryParameters['latitude'], '37.8213');
      expect(seen.queryParameters['longitude'], '128.1567');
      expect(seen.queryParameters['timezone'], 'Asia/Seoul');
      expect(seen.queryParameters.containsKey('apikey'), isFalse);
    });
  });

  group('WMO 코드 분류', () {
    test('맑음부터 뇌우까지 갈래를 나눈다', () {
      expect(conditionFromWmoCode(0), WeatherCondition.clear);
      expect(conditionFromWmoCode(2), WeatherCondition.partlyCloudy);
      expect(conditionFromWmoCode(45), WeatherCondition.fog);
      expect(conditionFromWmoCode(55), WeatherCondition.drizzle);
      expect(conditionFromWmoCode(82), WeatherCondition.rain);
      expect(conditionFromWmoCode(75), WeatherCondition.snow);
      expect(conditionFromWmoCode(99), WeatherCondition.thunder);
      // 표에 없는 값이 와도 화면이 비지 않아야 한다.
      expect(conditionFromWmoCode(123), WeatherCondition.cloudy);
    });
  });

  group('주의 문구', () {
    CampsiteWeather build({
      double windMs = 2,
      int precipPct = 0,
      int lowC = 15,
    }) => CampsiteWeather(
      temperatureC: 18,
      feelsLikeC: 18,
      condition: WeatherCondition.clear,
      windMs: windMs,
      humidityPct: 50,
      days: [
        DailyWeather(
          date: DateTime(2026, 8, 21),
          condition: WeatherCondition.clear,
          highC: 22,
          lowC: lowC,
          precipPct: precipPct,
        ),
      ],
    );

    test('평범한 날은 아무 말도 하지 않는다', () {
      expect(build().caution, isNull);
    });

    test('비 확률이 높으면 방수 장비를 알린다', () {
      expect(build(precipPct: 70).caution, contains('방수'));
    });

    test('바람이 세면 고정을 알린다', () {
      expect(build(windMs: 9.2).caution, contains('바람'));
    });

    test('밤이 추우면 침낭을 알린다', () {
      expect(build(lowC: 3).caution, contains('침낭'));
    });
  });
}
