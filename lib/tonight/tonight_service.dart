/// 오늘 밤 지수를 만드는 서비스.
///
/// Open-Meteo(무료·키 불필요)에서 시간별 예보를 받아 밤 시간대만 잘라 쓰고,
/// 달 계산과 합쳐 점수를 낸다. 프록시를 거치지 않고 앱이 직접 호출하므로
/// AI 프록시가 죽어 있어도 이 카드는 살아 있다.
library;

import 'dart:convert';
import 'dart:io';

import 'night_models.dart';
import 'sky_math.dart';

typedef HourlyFetcher = Future<String> Function(Uri url);

/// 위치 권한이 "이미" 허용돼 있을 때만 좌표를 준다. 권한 팝업을 띄우지 않는다.
typedef SilentLocationReader = Future<({double lat, double lon})?> Function();

/// 예보를 받아올 날짜 수. Open-Meteo 무료 예보 범위 안이다.
const int _forecastDays = 14;

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

class TonightService {
  TonightService({HourlyFetcher? fetcher, SilentLocationReader? location})
    : _fetch = fetcher ?? _httpFetcher,
      _location = location;

  final HourlyFetcher _fetch;
  final SilentLocationReader? _location;

  Uri _forecastUri(double lat, double lon) =>
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'hourly':
            'cloud_cover,precipitation_probability,wind_speed_10m,temperature_2m',
        'timezone': 'Asia/Seoul',
        'forecast_days': '$_forecastDays',
      });

  /// 현재 기온 한 값만 필요할 때. 예보 전체를 받지 않는다.
  Uri _currentUri(double lat, double lon) =>
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current': 'temperature_2m',
        'timezone': 'Asia/Seoul',
      });

  Future<TonightForecast> load({
    required double lat,
    required double lon,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final darkSaturdays = darkSaturdayNightsLeftInYear(
      today,
      lat: lat,
      lon: lon,
    );

    List<NightSky> nights;
    var live = true;
    try {
      final raw = await _fetch(_forecastUri(lat, lon));
      nights = _parseNights(
        jsonDecode(raw) as Map<String, dynamic>,
        lat: lat,
        lon: lon,
        from: today,
      );
      if (nights.isEmpty) {
        live = false;
        nights = _astronomyOnlyNights(lat: lat, lon: lon, from: today);
      }
    } catch (_) {
      live = false;
      nights = _astronomyOnlyNights(lat: lat, lon: lon, from: today);
    }

    return TonightForecast(
      best: pickBestNight(nights),
      nights: nights,
      darkSaturdayNightsLeft: darkSaturdays,
      live: live,
    );
  }

  /// 위치 권한이 이미 있을 때만 "지금 내가 있는 곳" 기온을 준다.
  /// 권한이 없으면 조용히 null이다. 홈 진입 직후 권한 팝업을 띄우지 않기 위해서다.
  ///
  /// [load]와 분리해 둔다. 위치 조회는 기기 사정으로 오래 걸릴 수 있는데,
  /// 곁들이는 한 줄 때문에 카드 전체가 스켈레톤에 묶여서는 안 된다.
  /// 응답이 끝내 오지 않으면 그 한 줄이 영영 안 붙을 뿐, 카드는 이미 떠 있다.
  Future<int?> myTemperature() async {
    final reader = _location;
    if (reader == null) return null;
    try {
      final point = await reader();
      if (point == null) return null;
      final raw = await _fetch(_currentUri(point.lat, point.lon));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final current = decoded['current'];
      final temp = current is Map ? current['temperature_2m'] : null;
      return temp is num ? temp.round() : null;
    } catch (_) {
      return null;
    }
  }

  List<NightSky> _astronomyOnlyNights({
    required double lat,
    required double lon,
    required DateTime from,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    return List.generate(_forecastDays, (offset) {
      final date = start.add(Duration(days: offset));
      return astronomyOnlyNight(
        date: date,
        moonInterference: moonInterferenceForNight(date, lat: lat, lon: lon),
        moonIllumination: moonIllumination(
          kstToUtc(DateTime(date.year, date.month, date.day, 23)),
        ),
      );
    });
  }

  List<NightSky> _parseNights(
    Map<String, dynamic> decoded, {
    required double lat,
    required double lon,
    required DateTime from,
  }) {
    final hourly = decoded['hourly'];
    if (hourly is! Map) return const <NightSky>[];

    final times = (hourly['time'] as List?)?.cast<String>() ?? const <String>[];
    final index = <String, int>{
      for (var i = 0; i < times.length; i++) times[i]: i,
    };
    final cloud = _numList(hourly['cloud_cover']);
    final precip = _numList(hourly['precipitation_probability']);
    final wind = _numList(hourly['wind_speed_10m']);
    final temp = _numList(hourly['temperature_2m']);

    final today = DateTime(from.year, from.month, from.day);
    final nights = <NightSky>[];
    for (var offset = 0; offset < _forecastDays; offset++) {
      final date = today.add(Duration(days: offset));
      // 밤 21시~다음날 1시. 하늘을 보는 시간대다.
      final skyHours = _hourIndexes(index, date, 21, 5);
      // 밤 최저기온은 새벽까지 봐야 한다.
      final coldHours = _hourIndexes(index, date, 21, 10);
      if (skyHours.isEmpty || coldHours.isEmpty) continue;

      final cloudPct = _mean(cloud, skyHours);
      final windKmh = _mean(wind, skyHours);
      final precipPct = _max(precip, skyHours);
      final lowC = _min(temp, coldHours);
      if (cloudPct == null || windKmh == null || lowC == null) continue;

      nights.add(
        scoreNight(
          date: date,
          cloudPct: cloudPct.round(),
          precipPct: precipPct?.round() ?? 0,
          windMs: double.parse((windKmh / 3.6).toStringAsFixed(1)),
          nightLowC: lowC.round(),
          moonInterference: moonInterferenceForNight(date, lat: lat, lon: lon),
          moonIllumination: moonIllumination(
            kstToUtc(DateTime(date.year, date.month, date.day, 23)),
          ),
        ),
      );
    }
    return nights;
  }

  List<int> _hourIndexes(
    Map<String, int> index,
    DateTime date,
    int startHour,
    int count,
  ) {
    final found = <int>[];
    for (var step = 0; step < count; step++) {
      final at = DateTime(
        date.year,
        date.month,
        date.day,
        startHour,
      ).add(Duration(hours: step));
      final key =
          '${at.year.toString().padLeft(4, '0')}-'
          '${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}T'
          '${at.hour.toString().padLeft(2, '0')}:00';
      final i = index[key];
      if (i != null) found.add(i);
    }
    return found;
  }
}

List<num?> _numList(dynamic value) =>
    value is List ? value.map((e) => e is num ? e : null).toList() : const [];

double? _mean(List<num?> values, List<int> indexes) {
  final picked = _pick(values, indexes);
  if (picked.isEmpty) return null;
  return picked.reduce((a, b) => a + b) / picked.length;
}

double? _max(List<num?> values, List<int> indexes) {
  final picked = _pick(values, indexes);
  if (picked.isEmpty) return null;
  return picked.reduce((a, b) => a > b ? a : b);
}

double? _min(List<num?> values, List<int> indexes) {
  final picked = _pick(values, indexes);
  if (picked.isEmpty) return null;
  return picked.reduce((a, b) => a < b ? a : b);
}

List<double> _pick(List<num?> values, List<int> indexes) => [
  for (final i in indexes)
    if (i < values.length && values[i] != null) values[i]!.toDouble(),
];
