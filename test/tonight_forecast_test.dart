import 'dart:async';
import 'dart:convert';

import 'package:campon/tonight/night_models.dart';
import 'package:campon/tonight/tonight_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _lat = 37.82;
const _lon = 128.16;

String _timeKey(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}T'
    '${at.hour.toString().padLeft(2, '0')}:00';

/// Open-Meteo 응답 모양의 가짜 예보. 시각마다 값을 직접 정할 수 있다.
String _forecastJson({
  required DateTime start,
  int days = 15,
  double Function(DateTime at)? cloud,
  double Function(DateTime at)? precip,
  double Function(DateTime at)? windKmh,
  double Function(DateTime at)? temp,
  double currentTemp = 29,
}) {
  final times = <String>[];
  final clouds = <double>[];
  final precips = <double>[];
  final winds = <double>[];
  final temps = <double>[];
  for (var hour = 0; hour < days * 24; hour++) {
    final at = DateTime(
      start.year,
      start.month,
      start.day,
    ).add(Duration(hours: hour));
    times.add(_timeKey(at));
    clouds.add(cloud?.call(at) ?? 5);
    precips.add(precip?.call(at) ?? 0);
    winds.add(windKmh?.call(at) ?? 4);
    temps.add(temp?.call(at) ?? 15);
  }
  return jsonEncode({
    'current': {'temperature_2m': currentTemp},
    'hourly': {
      'time': times,
      'cloud_cover': clouds,
      'precipitation_probability': precips,
      'wind_speed_10m': winds,
      'temperature_2m': temps,
    },
  });
}

TonightService _serviceReturning(String body) =>
    TonightService(fetcher: (_) async => body);

void main() {
  group('오늘 밤 지수 계산', () {
    test('맑고 달 없는 밤은 은하수 등급이 된다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await _serviceReturning(
        _forecastJson(start: start),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.live, isTrue);
      // 2026-08-12는 삭이라 그 언저리 밤이 가장 어둡다.
      expect(forecast.best.grade, SkyGrade.milkyWay);
      expect(forecast.best.score, greaterThanOrEqualTo(82));
      expect(forecast.best.moonlessEnough, isTrue);
      expect(forecast.best.hasWeather, isTrue);
    });

    test('구름이 덮으면 점수가 떨어진다', () async {
      final start = DateTime(2026, 8, 10);
      final cloudy = await _serviceReturning(
        _forecastJson(start: start, cloud: (_) => 95),
      ).load(lat: _lat, lon: _lon, now: start);
      final clear = await _serviceReturning(
        _forecastJson(start: start),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(cloudy.best.score, lessThan(clear.best.score));
      expect(cloudy.best.cloudPct, 95);
    });

    test('강수확률 60% 이상이면 점수에 상한이 걸린다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await _serviceReturning(
        _forecastJson(start: start, precip: (_) => 80),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.best.score, lessThanOrEqualTo(25));
      expect(forecast.best.grade, SkyGrade.poor);
    });

    test('예보에서 고른 밤은 조회 시작일 이후 2주 안에 있다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await _serviceReturning(
        _forecastJson(start: start),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.best.date.isBefore(start), isFalse);
      expect(
        forecast.best.date.difference(start).inDays,
        lessThan(14),
      );
      expect(forecast.nights.length, greaterThan(10));
    });

    test('밤 최저기온은 새벽까지 보고 고른다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await _serviceReturning(
        _forecastJson(
          start: start,
          // 21~23시는 20도, 새벽에 9도까지 떨어진다.
          temp: (at) => at.hour >= 21 || at.hour < 3 ? 20 : 9,
        ),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.best.nightLowC, 9);
    });

    test('현재 위치 기온은 카드 본문과 따로 조회된다', () async {
      final start = DateTime(2026, 8, 10);
      final body = _forecastJson(start: start, currentTemp: 31);
      final service = TonightService(
        fetcher: (_) async => body,
        location: () async => (lat: 37.56, lon: 126.97),
      );

      final forecast = await service.load(lat: _lat, lon: _lon, now: start);
      expect(forecast.myTempC, isNull, reason: '본문은 위치를 기다리지 않는다');
      expect(await service.myTemperature(), 31);
    });

    test('위치 권한이 없으면 기온을 주지 않는다', () async {
      final body = _forecastJson(start: DateTime(2026, 8, 10));

      expect(
        await TonightService(fetcher: (_) async => body).myTemperature(),
        isNull,
      );
      expect(
        await TonightService(
          fetcher: (_) async => body,
          location: () async => null,
        ).myTemperature(),
        isNull,
      );
    });

    test('위치 조회가 멈춰 있어도 카드는 뜬다', () async {
      final start = DateTime(2026, 8, 10);
      final service = TonightService(
        fetcher: (_) async => _forecastJson(start: start),
        // 응답이 영영 오지 않는 위치 조회.
        location: () => Completer<({double lat, double lon})?>().future,
      );

      final forecast = await service
          .load(lat: _lat, lon: _lon, now: start)
          .timeout(const Duration(seconds: 2));
      expect(forecast.best.hasWeather, isTrue);
    });
  });

  group('날씨를 못 받았을 때', () {
    test('달 계산만으로 카드를 채운다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await TonightService(
        fetcher: (_) async => throw const SocketExceptionStub(),
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.live, isFalse);
      expect(forecast.nights, isNotEmpty);
      expect(forecast.best.hasWeather, isFalse);
      expect(forecast.best.cloudPct, isNull);
      expect(forecast.darkSaturdayNightsLeft, greaterThan(0));
    });

    test('응답이 깨져 있어도 예외를 흘리지 않는다', () async {
      final start = DateTime(2026, 8, 10);
      final forecast = await _serviceReturning(
        '{"hourly": null}',
      ).load(lat: _lat, lon: _lon, now: start);

      expect(forecast.live, isFalse);
      expect(forecast.best.hasWeather, isFalse);
    });
  });

  group('어느 밤을 보여줄지 고르는 규칙', () {
    NightSky nightOn(DateTime date, int score) => NightSky(
      date: date,
      score: score,
      grade: gradeForScore(score),
      moonIlluminationPct: 0,
      moonInterferencePct: 0,
    );

    // 2026-08-13은 목요일, 14일은 금요일, 15일은 토요일이다.
    final thursday = DateTime(2026, 8, 13);
    final friday = DateTime(2026, 8, 14);
    final saturday = DateTime(2026, 8, 15);

    test('테스트가 기대하는 요일이 맞다', () {
      expect(thursday.weekday, DateTime.thursday);
      expect(friday.weekday, DateTime.friday);
      expect(saturday.weekday, DateTime.saturday);
    });

    test('점수가 조금 낮아도 주말 밤을 고른다', () {
      final best = pickBestNight([
        nightOn(thursday, 90),
        nightOn(friday, 84),
        nightOn(saturday, 86),
      ]);
      expect(best.date, friday);
    });

    test('주말이 확실히 나쁘면 평일 밤을 고른다', () {
      final best = pickBestNight([
        nightOn(thursday, 90),
        nightOn(friday, 40),
        nightOn(saturday, 55),
      ]);
      expect(best.date, thursday);
    });

    test('주말 후보가 없으면 최고점을 고른다', () {
      final best = pickBestNight([
        nightOn(DateTime(2026, 8, 10), 70),
        nightOn(DateTime(2026, 8, 11), 88),
        nightOn(DateTime(2026, 8, 12), 60),
      ]);
      expect(best.score, 88);
    });
  });

  group('점수 구간', () {
    test('구간별 등급이 이어진다', () {
      expect(gradeForScore(95), SkyGrade.milkyWay);
      expect(gradeForScore(82), SkyGrade.milkyWay);
      expect(gradeForScore(81), SkyGrade.great);
      expect(gradeForScore(66), SkyGrade.great);
      expect(gradeForScore(65), SkyGrade.decent);
      expect(gradeForScore(48), SkyGrade.decent);
      expect(gradeForScore(47), SkyGrade.poor);
      expect(gradeForScore(0), SkyGrade.poor);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
