/// "그날 밤 미리보기" 모델.
///
/// 오늘 밤 지수가 계산한 실제 수치(구름·바람·기온·달)를 그대로 받아,
/// 그 밤에 거기 있는 장면을 1인칭으로 쓴 글이다. 정보가 아니라 연출이다.
library;

class PreviewInput {
  const PreviewInput({
    required this.place,
    required this.date,
    required this.moonIlluminationPct,
    required this.moonInterferencePct,
    required this.score,
    required this.grade,
    this.people = 2,
    this.experience = '초보',
    this.cloudPct,
    this.precipPct,
    this.windMs,
    this.nightLowC,
    this.myTempC,
  });

  final String place;

  /// 밤이 시작되는 날짜(KST).
  final DateTime date;
  final int moonIlluminationPct;
  final int moonInterferencePct;
  final int score;
  final String grade;
  final int people;
  final String experience;
  final int? cloudPct;
  final int? precipPct;
  final double? windMs;
  final int? nightLowC;

  /// 지금 내가 있는 곳의 기온. 대비 문장을 만들 때만 쓴다.
  final int? myTempC;

  bool get moonlessEnough => moonInterferencePct <= 15;

  String get isoDate =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toRequestJson() => {
    'place': place,
    'date': isoDate,
    'people': people,
    'experience': experience,
    'weather': {
      'cloudPct': cloudPct,
      'precipPct': precipPct,
      'windMs': windMs,
      'nightLowC': nightLowC,
      'myTempC': myTempC,
    },
    'sky': {
      'moonIlluminationPct': moonIlluminationPct,
      'moonInterferencePct': moonInterferencePct,
      'score': score,
      'grade': grade,
    },
  };
}

class NightPreview {
  const NightPreview({
    required this.title,
    required this.lines,
    required this.closing,
  });

  final String title;
  final List<String> lines;
  final String closing;

  static NightPreview? fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final closing = json['closing'];
    final lines = json['lines'];
    if (title is! String || lines is! List) return null;
    final texts = lines
        .whereType<String>()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (title.trim().isEmpty || texts.length < 3) return null;
    return NightPreview(
      title: title.trim(),
      lines: texts,
      closing: closing is String && closing.trim().isNotEmpty
          ? closing.trim()
          : '이 밤은 아직 아무도 예약하지 않았다.',
    );
  }
}

/// 프록시가 없거나 실패했을 때 쓰는 결정론적 장면.
/// 수치에서 문장을 고르기 때문에 밤마다 내용이 달라지고, 사실과 어긋나지 않는다.
NightPreview buildLocalNightPreview(PreviewInput input) {
  final lines = <String>[
    _openingLine(input.nightLowC),
    _windLine(input.windMs),
    _skyLine(input),
    '장작이 한 번 크게 튀고 다시 조용해진다. 아무도 말하지 않아도 어색하지 않은 시간이다.',
    _sleepLine(input.nightLowC),
  ];
  return NightPreview(
    title: '${input.date.month}월 ${input.date.day}일 밤, ${input.place}',
    lines: lines,
    closing: '이 밤은 아직 아무도 예약하지 않았다.',
  );
}

String _openingLine(int? nightLowC) {
  if (nightLowC == null) {
    return '밤 9시. 도시에서는 들어본 적 없는 조용함이 먼저 도착한다.';
  }
  if (nightLowC >= 20) {
    return '밤 9시. 낮의 열기가 아직 땅에 남아 있다. 반팔 위에 얇은 셔츠 하나면 딱 좋은 온도다.';
  }
  if (nightLowC >= 12) {
    return '밤 9시. 공기가 한 겹 서늘해졌다. 낮에 벗어둔 겉옷을 다시 걸친다.';
  }
  return '밤 9시. 입김이 옅게 보인다. 침낭 속이 벌써 그리워지는 온도다.';
}

String _windLine(double? windMs) {
  if (windMs == null) {
    return '불을 붙이자 주변이 한 뼘씩 밝아진다.';
  }
  if (windMs <= 2) {
    return '바람이 거의 없다. 불꽃이 흔들리지 않고 똑바로 올라간다.';
  }
  if (windMs <= 5) {
    return '이따금 바람이 지나간다. 타프 자락이 한 번씩 살짝 부푼다.';
  }
  return '바람이 제법 분다. 팩을 한 번 더 확인하고 자리에 앉는다.';
}

String _skyLine(PreviewInput input) {
  final cloud = input.cloudPct;
  if (cloud != null && cloud > 60) {
    return '하늘은 두껍다. 오늘은 별 대신 불빛만 보기로 한다.';
  }
  if (cloud != null && cloud > 20) {
    return '구름이 천천히 지나간다. 사이가 벌어질 때마다 별이 몇 개씩 나타났다 사라진다.';
  }
  if (input.moonlessEnough) {
    return '고개를 들면 달이 없어서 별이 평소의 두 배쯤 많다. '
        '눈이 어둠에 익을수록 없던 별이 계속 생긴다.';
  }
  return '달이 ${input.moonIlluminationPct}% 차 있다. 밝은 별부터 차례로 눈에 들어온다.';
}

String _sleepLine(int? nightLowC) {
  if (nightLowC != null && nightLowC <= 8) {
    return '텐트에 들어가면 바닥부터 차다. 매트 한 장이 오늘의 승부다.';
  }
  return '텐트 지퍼를 반쯤 열어두고 눕는다. 풀벌레 소리가 천천히 볼륨을 낮춘다.';
}
