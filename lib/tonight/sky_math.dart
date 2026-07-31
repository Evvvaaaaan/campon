/// 달의 위상과 고도를 구하는 순수 계산 모듈.
///
/// 외부 API·패키지에 의존하지 않는다. 네트워크가 끊겨도 "달이 얼마나 밝은지",
/// "그 시간에 달이 떠 있는지"는 항상 계산할 수 있어야 하기 때문이다.
///
/// 정확도는 저정밀 근사(달 위치 오차 약 0.3도, 태양 약 0.01도)다.
/// "달빛이 별을 얼마나 가리는가"를 판단하는 용도에는 충분하다.
library;

import 'dart:math' as math;

const double _degToRad = math.pi / 180;
const double _radToDeg = 180 / math.pi;

/// 한국 표준시 오프셋. Open-Meteo를 `timezone=Asia/Seoul`로 부르기 때문에
/// 앱이 다루는 밤 시각은 모두 KST 벽시계 기준이다.
const Duration kstOffset = Duration(hours: 9);

double _sinDeg(double deg) => math.sin(deg * _degToRad);
double _cosDeg(double deg) => math.cos(deg * _degToRad);

double _norm360(double deg) {
  final value = deg % 360;
  return value < 0 ? value + 360 : value;
}

/// KST 벽시계 시각을 UTC 순간으로 바꾼다.
DateTime kstToUtc(DateTime wallClock) => DateTime.utc(
  wallClock.year,
  wallClock.month,
  wallClock.day,
  wallClock.hour,
  wallClock.minute,
).subtract(kstOffset);

/// 율리우스일.
double julianDay(DateTime time) =>
    time.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;

/// J2000.0(2000-01-01 12:00 UTC)로부터 경과한 일수.
double _daysSinceJ2000(DateTime time) => julianDay(time) - 2451545.0;

/// 태양의 황경(도).
double _sunLongitude(double days) {
  final meanLongitude = 280.460 + 0.9856474 * days;
  final meanAnomaly = _norm360(357.528 + 0.9856003 * days);
  return _norm360(
    meanLongitude +
        1.915 * _sinDeg(meanAnomaly) +
        0.020 * _sinDeg(2 * meanAnomaly),
  );
}

class _Ecliptic {
  const _Ecliptic(this.longitude, this.latitude);

  final double longitude;
  final double latitude;
}

/// 달의 황경·황위(도).
_Ecliptic _moonEcliptic(double days) {
  final meanLongitude = 218.316 + 13.176396 * days;
  final meanAnomaly = _norm360(134.963 + 13.064993 * days);
  final argumentOfLatitude = _norm360(93.272 + 13.229350 * days);
  return _Ecliptic(
    _norm360(meanLongitude + 6.289 * _sinDeg(meanAnomaly)),
    5.128 * _sinDeg(argumentOfLatitude),
  );
}

/// 달의 밝은 면 비율(0 = 삭, 1 = 보름).
double moonIllumination(DateTime time) {
  final days = _daysSinceJ2000(time);
  final moon = _moonEcliptic(days);
  final elongationCos =
      _cosDeg(moon.latitude) * _cosDeg(moon.longitude - _sunLongitude(days));
  return ((1 - elongationCos) / 2).clamp(0.0, 1.0);
}

/// 관측지에서 본 달의 고도(도). 음수면 지평선 아래다.
double moonAltitudeDeg(
  DateTime time, {
  required double lat,
  required double lon,
}) {
  final days = _daysSinceJ2000(time);
  final moon = _moonEcliptic(days);
  final obliquity = 23.4393 - 3.563e-7 * days;

  final sinDeclination =
      _sinDeg(moon.latitude) * _cosDeg(obliquity) +
      _cosDeg(moon.latitude) * _sinDeg(obliquity) * _sinDeg(moon.longitude);
  final declination = math.asin(sinDeclination.clamp(-1.0, 1.0)) * _radToDeg;

  final rightAscension = _norm360(
    math.atan2(
          _sinDeg(moon.longitude) * _cosDeg(obliquity) -
              math.tan(moon.latitude * _degToRad) * _sinDeg(obliquity),
          _cosDeg(moon.longitude),
        ) *
        _radToDeg,
  );

  final siderealTime = _norm360(280.46061837 + 360.98564736629 * days);
  final hourAngle = _norm360(siderealTime + lon - rightAscension);

  final sinAltitude =
      _sinDeg(lat) * _sinDeg(declination) +
      _cosDeg(lat) * _cosDeg(declination) * _cosDeg(hourAngle);
  return math.asin(sinAltitude.clamp(-1.0, 1.0)) * _radToDeg;
}

/// 밤 시간대에 달빛이 별을 방해하는 정도(0 = 완전히 어두움, 1 = 보름달이 내내 떠 있음).
///
/// 위상만으로는 부족하다. 보름달이어도 그 시간에 지평선 아래면 하늘은 어둡다.
/// 그래서 밝기 × 떠 있는 시간 비율로 계산한다.
double moonInterference({
  required DateTime nightStartUtc,
  required double lat,
  required double lon,
  int windowHours = 4,
}) {
  var illuminationSum = 0.0;
  var aboveHorizon = 0;
  var samples = 0;
  for (var step = 0; step <= windowHours * 2; step++) {
    final time = nightStartUtc.add(Duration(minutes: 30 * step));
    illuminationSum += moonIllumination(time);
    if (moonAltitudeDeg(time, lat: lat, lon: lon) > 0) aboveHorizon++;
    samples++;
  }
  return (illuminationSum / samples) * (aboveHorizon / samples);
}

/// 그날 밤(KST 21시 시작)의 달빛 방해 정도.
double moonInterferenceForNight(
  DateTime nightDate, {
  required double lat,
  required double lon,
}) => moonInterference(
  nightStartUtc: kstToUtc(
    DateTime(nightDate.year, nightDate.month, nightDate.day, 21),
  ),
  lat: lat,
  lon: lon,
);

/// [from]이 속한 해에 남아 있는 "달 없는 토요일 밤"의 수.
///
/// 날씨 예보는 약 2주치뿐이라 1년 단위 희소성을 날씨로 말할 수 없다.
/// 달의 운행은 1년 뒤까지 정확히 계산되므로, 희소성은 달만으로 센다.
int darkSaturdayNightsLeftInYear(
  DateTime from, {
  required double lat,
  required double lon,
  double threshold = 0.2,
}) {
  var day = DateTime(from.year, from.month, from.day);
  var count = 0;
  while (day.year == from.year) {
    if (day.weekday == DateTime.saturday &&
        moonInterferenceForNight(day, lat: lat, lon: lon) < threshold) {
      count++;
    }
    day = day.add(const Duration(days: 1));
  }
  return count;
}
