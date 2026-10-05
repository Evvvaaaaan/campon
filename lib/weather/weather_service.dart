/// 캠핑장 좌표의 실제 날씨.
///
/// Open-Meteo(무료·API 키 불필요·로그인 없음)를 앱이 직접 부른다. AI 프록시를 거치지
/// 않으므로 프록시가 죽어 있어도 이 섹션은 살아 있다. `TonightService`와 같은 호스트를
/// 쓰지만 그쪽은 밤 시간대만 잘라 점수를 내는 용도이고, 여기는 "지금 거기 날씨"와
/// 며칠치 예보를 그대로 보여주기 위한 것이다.
library;

import 'dart:convert';
import 'dart:io';

typedef WeatherFetcher = Future<String> Function(Uri url);

/// 오늘 포함 며칠치를 받을지. Open-Meteo 무료 예보 범위 안이다.
const int _forecastDays = 3;

Future<String> _httpFetcher(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// WMO 날씨 코드를 화면에서 다룰 만한 갈래로 줄인 것.
enum WeatherCondition {
  clear('맑음'),
  partlyCloudy('구름 조금'),
  cloudy('흐림'),
  fog('안개'),
  drizzle('이슬비'),
  rain('비'),
  snow('눈'),
  thunder('뇌우');

  const WeatherCondition(this.label);

  final String label;
}

/// Open-Meteo의 WMO 코드 표를 그대로 옮긴 것.
/// https://open-meteo.com/en/docs — Weather variable documentation
WeatherCondition conditionFromWmoCode(int code) => switch (code) {
  0 => WeatherCondition.clear,
  1 || 2 => WeatherCondition.partlyCloudy,
  3 => WeatherCondition.cloudy,
  45 || 48 => WeatherCondition.fog,
  51 || 53 || 55 || 56 || 57 => WeatherCondition.drizzle,
  61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => WeatherCondition.rain,
  71 || 73 || 75 || 77 || 85 || 86 => WeatherCondition.snow,
  95 || 96 || 99 => WeatherCondition.thunder,
  _ => WeatherCondition.cloudy,
};

class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.condition,
    required this.highC,
    required this.lowC,
    required this.precipPct,
  });

  final DateTime date;
  final WeatherCondition condition;
  final int highC;
  final int lowC;
  final int precipPct;
}

class CampsiteWeather {
  const CampsiteWeather({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.condition,
    required this.windMs,
    required this.humidityPct,
    required this.days,
  });

  final int temperatureC;
  final int feelsLikeC;
  final WeatherCondition condition;

  /// 초속. Open-Meteo는 km/h로 주므로 받아올 때 나눈 값이다.
  final double windMs;
  final int humidityPct;
  final List<DailyWeather> days;

  DailyWeather? get today => days.isEmpty ? null : days.first;

  /// 챙길 것이 달라지는 조건만 한 줄로 알린다. 해당 없으면 null이라 줄 자체가 안 뜬다.
  String? get caution {
    final today = this.today;
    if (today != null && today.precipPct >= 60) {
      return '비 올 확률이 ${today.precipPct}%예요. 타프와 방수 장비를 챙기세요.';
    }
    if (windMs >= 8) {
      return '바람이 초속 ${windMs.toStringAsFixed(1)}m로 강해요. 팩과 스트링을 단단히 고정하세요.';
    }
    if (today != null && today.lowC <= 5) {
      return '최저 ${today.lowC}도까지 떨어져요. 침낭 내한온도를 확인하세요.';
    }
    return null;
  }
}

class WeatherService {
  WeatherService({WeatherFetcher? fetcher}) : _fetch = fetcher ?? _httpFetcher;

  final WeatherFetcher _fetch;

  Uri _forecastUri(double lat, double lon) =>
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current':
            'temperature_2m,apparent_temperature,relative_humidity_2m,'
            'weather_code,wind_speed_10m',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,'
            'precipitation_probability_max',
        'timezone': 'Asia/Seoul',
        'forecast_days': '$_forecastDays',
      });

  /// 실패하면 null. 상세 화면의 한 섹션일 뿐이라 화면 전체를 막지 않는다.
  Future<CampsiteWeather?> load({
    required double lat,
    required double lon,
  }) async {
    try {
      final raw = await _fetch(_forecastUri(lat, lon));
      return parseCampsiteWeather(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// 응답에서 현재 기온이 빠져 있으면 보여줄 것이 없으므로 null을 준다.
/// 일별 예보만 비는 경우는 현재 날씨만으로도 쓸모가 있어 빈 목록으로 넘긴다.
CampsiteWeather? parseCampsiteWeather(Map<String, dynamic> decoded) {
  final current = decoded['current'];
  if (current is! Map) return null;

  final temp = _asNum(current['temperature_2m']);
  if (temp == null) return null;

  final windKmh = _asNum(current['wind_speed_10m']) ?? 0;
  return CampsiteWeather(
    temperatureC: temp.round(),
    feelsLikeC: (_asNum(current['apparent_temperature']) ?? temp).round(),
    condition: conditionFromWmoCode(
      _asNum(current['weather_code'])?.round() ?? 3,
    ),
    windMs: double.parse((windKmh / 3.6).toStringAsFixed(1)),
    humidityPct: (_asNum(current['relative_humidity_2m']) ?? 0).round(),
    days: _parseDays(decoded['daily']),
  );
}

List<DailyWeather> _parseDays(dynamic daily) {
  if (daily is! Map) return const <DailyWeather>[];

  final dates = (daily['time'] as List?)?.cast<Object?>() ?? const [];
  final codes = _numList(daily['weather_code']);
  final highs = _numList(daily['temperature_2m_max']);
  final lows = _numList(daily['temperature_2m_min']);
  final precip = _numList(daily['precipitation_probability_max']);

  final days = <DailyWeather>[];
  for (var i = 0; i < dates.length; i++) {
    final date = DateTime.tryParse('${dates[i]}');
    final high = _at(highs, i);
    final low = _at(lows, i);
    if (date == null || high == null || low == null) continue;
    days.add(
      DailyWeather(
        date: date,
        condition: conditionFromWmoCode(_at(codes, i)?.round() ?? 3),
        highC: high.round(),
        lowC: low.round(),
        precipPct: _at(precip, i)?.round() ?? 0,
      ),
    );
  }
  return days;
}

num? _asNum(dynamic value) => value is num ? value : null;

List<num?> _numList(dynamic value) =>
    value is List ? value.map(_asNum).toList() : const [];

num? _at(List<num?> values, int index) =>
    index < values.length ? values[index] : null;
