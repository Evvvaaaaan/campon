/// "오늘 밤 지수" 모델과 점수 계산.
///
/// 점수는 별을 보기 좋은 밤인지를 0~100으로 나타낸다. 네 가지가 섞인다.
/// 하늘이 맑은가(구름), 어두운가(달빛), 잔잔한가(바람), 견딜 만한가(기온).
library;

enum SkyGrade { milkyWay, great, decent, poor }

extension SkyGradeLabel on SkyGrade {
  String get headline => switch (this) {
    SkyGrade.milkyWay => '은하수까지 보이는 밤',
    SkyGrade.great => '별 보기 좋은 밤',
    SkyGrade.decent => '무난한 밤하늘',
    SkyGrade.poor => '하늘은 아쉬운 밤',
  };

  String get badge => switch (this) {
    SkyGrade.milkyWay => '은하수',
    SkyGrade.great => '별맑음',
    SkyGrade.decent => '보통',
    SkyGrade.poor => '흐림',
  };
}

class NightSky {
  const NightSky({
    required this.date,
    required this.score,
    required this.grade,
    required this.moonIlluminationPct,
    required this.moonInterferencePct,
    this.cloudPct,
    this.precipPct,
    this.windMs,
    this.nightLowC,
  });

  /// 밤이 시작되는 날짜(KST). 8월 2일 밤은 8월 2일 21시 ~ 8월 3일 1시를 뜻한다.
  final DateTime date;
  final int score;
  final SkyGrade grade;
  final int moonIlluminationPct;
  final int moonInterferencePct;

  /// 아래 네 값은 날씨 조회에 실패하면 null이다. 그때는 달 정보만 보여준다.
  final int? cloudPct;
  final int? precipPct;
  final double? windMs;
  final int? nightLowC;

  bool get hasWeather => cloudPct != null;

  /// 달이 사실상 없는 밤인지. 카피에서 "달 없음"이라고 쓸 수 있는 기준.
  bool get moonlessEnough => moonInterferencePct <= 15;
}

class TonightForecast {
  const TonightForecast({
    required this.best,
    required this.nights,
    required this.darkSaturdayNightsLeft,
    required this.live,
    this.destinationName,
    this.myTempC,
  });

  /// 가장 좋은 밤 하나. 카드의 주인공이다.
  final NightSky best;
  final List<NightSky> nights;

  /// 올해 남은 "달 없는 토요일 밤" 수. 희소성 문구에 쓴다.
  final int darkSaturdayNightsLeft;

  /// 날씨까지 반영했는지. false면 달 계산만으로 만든 결과다.
  final bool live;

  /// 그 지역에서 고른 캠핑장 이름. 못 가져오면 null이고 지역명을 쓴다.
  final String? destinationName;

  /// 지금 내 위치의 기온. 위치 권한이 이미 있을 때만 채워진다.
  final int? myTempC;

  TonightForecast copyWith({String? destinationName, int? myTempC}) =>
      TonightForecast(
        best: best,
        nights: nights,
        darkSaturdayNightsLeft: darkSaturdayNightsLeft,
        live: live,
        destinationName: destinationName ?? this.destinationName,
        myTempC: myTempC ?? this.myTempC,
      );
}

/// 점수가 가장 높은 밤. 다만 거의 비슷한 점수라면 주말 밤을 고른다.
/// 실제로 갈 수 있는 밤을 보여줘야 "가고 싶다"가 행동으로 이어진다.
NightSky pickBestNight(List<NightSky> nights, {int weekendTolerance = 8}) {
  final ranked = [...nights]..sort((a, b) => b.score.compareTo(a.score));
  final top = ranked.first;
  final nearTopWeekends =
      nights
          .where((n) => n.score >= top.score - weekendTolerance)
          .where(
            (n) =>
                n.date.weekday == DateTime.friday ||
                n.date.weekday == DateTime.saturday,
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  return nearTopWeekends.isEmpty ? top : nearTopWeekends.first;
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

/// 바람이 약할수록 100점. 2m/s 이하는 만점, 8m/s 이상은 0점.
double _calmness(double windMs) => _clamp01((8 - windMs) / 6) * 100;

/// 밤 최저기온이 8~20도면 만점. 벗어날수록 깎인다.
double _comfort(int nightLowC) {
  if (nightLowC >= 8 && nightLowC <= 20) return 100;
  final gap = nightLowC < 8 ? (8 - nightLowC) * 6.0 : (nightLowC - 20) * 5.0;
  return (100 - gap).clamp(0.0, 100.0);
}

SkyGrade gradeForScore(int score) {
  if (score >= 82) return SkyGrade.milkyWay;
  if (score >= 66) return SkyGrade.great;
  if (score >= 48) return SkyGrade.decent;
  return SkyGrade.poor;
}

/// 날씨와 달을 모두 아는 밤의 점수.
NightSky scoreNight({
  required DateTime date,
  required int cloudPct,
  required int precipPct,
  required double windMs,
  required int nightLowC,
  required double moonInterference,
  required double moonIllumination,
}) {
  final clearness = (100 - cloudPct).toDouble();
  final darkness = 100 - moonInterference * 100;
  var score =
      0.42 * clearness +
      0.30 * darkness +
      0.16 * _calmness(windMs) +
      0.12 * _comfort(nightLowC);

  // 비는 다른 조건이 아무리 좋아도 밤하늘을 덮는다. 가중치가 아니라 상한으로 다룬다.
  if (precipPct >= 60) {
    score = score < 25 ? score : 25;
  } else if (precipPct >= 30) {
    score *= 0.75;
  }

  final rounded = score.round().clamp(0, 100);
  return NightSky(
    date: date,
    score: rounded,
    grade: gradeForScore(rounded),
    moonIlluminationPct: (moonIllumination * 100).round(),
    moonInterferencePct: (moonInterference * 100).round(),
    cloudPct: cloudPct,
    precipPct: precipPct,
    windMs: windMs,
    nightLowC: nightLowC,
  );
}

/// 날씨를 못 받았을 때, 달만으로 만든 밤.
NightSky astronomyOnlyNight({
  required DateTime date,
  required double moonInterference,
  required double moonIllumination,
}) {
  final score = (100 - moonInterference * 100).round().clamp(0, 100);
  return NightSky(
    date: date,
    score: score,
    grade: gradeForScore(score),
    moonIlluminationPct: (moonIllumination * 100).round(),
    moonInterferencePct: (moonInterference * 100).round(),
  );
}
