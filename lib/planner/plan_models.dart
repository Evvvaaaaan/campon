enum WeatherGrade { good, caution, risk }

WeatherGrade weatherGradeFrom(String? s) {
  switch (s) {
    case 'risk':
      return WeatherGrade.risk;
    case 'caution':
      return WeatherGrade.caution;
    default:
      return WeatherGrade.good;
  }
}

class PlanSummary {
  PlanSummary({required this.title, required this.mood, required this.oneLiner});
  final String title;
  final String mood;
  final String oneLiner;
}

class PlanWeather {
  PlanWeather({
    required this.grade,
    required this.nightLowC,
    required this.precipPct,
    required this.windMs,
    required this.diurnalRangeC,
    required this.advice,
  });
  final WeatherGrade grade;
  final int nightLowC;
  final int precipPct;
  final int diurnalRangeC;
  final double windMs;
  final String advice;
}

class PlanCampsite {
  PlanCampsite({required this.name, required this.reason});
  final String name;
  final String reason;
}

class PlanChecklistCategory {
  PlanChecklistCategory({required this.category, required this.items});
  final String category;
  final List<String> items;
}

class PlanTimelineItem {
  PlanTimelineItem({required this.time, required this.title, required this.detail});
  final String time;
  final String title;
  final String detail;
}

String _s(dynamic v, [String d = '']) => v is String && v.trim().isNotEmpty ? v : d;
int _i(dynamic v, [int d = 0]) => v is num ? v.round() : d;
double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : d;
List<String> _sl(dynamic v) =>
    v is List ? v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList() : <String>[];

class CampPlan {
  CampPlan({
    required this.summary,
    required this.weather,
    required this.campsites,
    required this.checklist,
    required this.timeline,
  });
  final PlanSummary summary;
  final PlanWeather weather;
  final List<PlanCampsite> campsites;
  final List<PlanChecklistCategory> checklist;
  final List<PlanTimelineItem> timeline;

  factory CampPlan.fromJson(Map<String, dynamic> j) {
    final w = (j['weather'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CampPlan(
      summary: PlanSummary(
        title: _s(s['title'], '캠핑 플랜'),
        mood: _s(s['mood']),
        oneLiner: _s(s['oneLiner']),
      ),
      weather: PlanWeather(
        grade: weatherGradeFrom(w['grade'] as String?),
        nightLowC: _i(w['nightLowC'], 12),
        precipPct: _i(w['precipPct'], 20),
        windMs: _d(w['windMs'], 3),
        diurnalRangeC: _i(w['diurnalRangeC'], 9),
        advice: _s(w['advice'], '날씨 정보를 확인하세요.'),
      ),
      campsites: (j['campsites'] as List? ?? const [])
          .map((e) => PlanCampsite(name: _s((e as Map)['name']), reason: _s(e['reason'])))
          .where((e) => e.name.isNotEmpty)
          .toList(),
      checklist: (j['checklist'] as List? ?? const [])
          .map((e) => PlanChecklistCategory(
              category: _s((e as Map)['category']), items: _sl(e['items'])))
          .where((e) => e.category.isNotEmpty && e.items.isNotEmpty)
          .toList(),
      timeline: (j['timeline'] as List? ?? const [])
          .map((e) => PlanTimelineItem(
              time: _s((e as Map)['time']),
              title: _s(e['title']),
              detail: _s(e['detail'])))
          .where((e) => e.time.isNotEmpty)
          .toList(),
    );
  }
}

class PlanCandidate {
  PlanCandidate({required this.name, required this.facility, required this.equipmentRental});
  final String name;
  final List<String> facility;
  final List<String> equipmentRental;
  Map<String, dynamic> toJson() =>
      {'name': name, 'facility': facility, 'equipmentRental': equipmentRental};
}

class PlanInput {
  PlanInput({
    required this.query,
    required this.date,
    required this.people,
    required this.hasCar,
    required this.experience,
    required this.region,
    required this.lat,
    required this.lon,
    required this.preferences,
    required this.equipment,
    required this.candidates,
  });
  final String query;
  final String date;
  final String experience;
  final String region;
  final int people;
  final bool hasCar;
  final double lat;
  final double lon;
  final List<String> preferences;
  final List<String> equipment;
  final List<PlanCandidate> candidates;

  Map<String, dynamic> toRequestJson() => {
        'query': query,
        'context': {
          'date': date,
          'people': people,
          'hasCar': hasCar,
          'experience': experience,
          'region': region,
          'preferences': preferences,
          'equipment': equipment,
        },
        'coords': {'lat': lat, 'lon': lon},
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };
}

CampPlan buildLocalFallbackPlan(PlanInput input) {
  final names = input.candidates.take(3).toList();
  return CampPlan(
    summary: PlanSummary(
      title: '${input.region} ${input.hasCar ? "오토" : ""}캠핑'.trim(),
      mood: input.experience.contains('초보') ? '편안하고 안전하게' : '자유롭게',
      oneLiner: '${input.date} ${input.people}명, ${input.region} 캠핑 플랜입니다.',
    ),
    weather: PlanWeather(
      grade: WeatherGrade.good,
      nightLowC: 14,
      precipPct: 15,
      windMs: 3,
      diurnalRangeC: 9,
      advice: '날씨가 안정적이에요. 편안한 캠핑이 예상됩니다.',
    ),
    campsites: names.isNotEmpty
        ? names
            .map((s) => PlanCampsite(name: s.name, reason: '${input.region} 지역, 접근성과 시설이 무난해요.'))
            .toList()
        : [PlanCampsite(name: '${input.region} 인근 캠핑장', reason: '지역 조건에 맞춘 추천입니다.')],
    checklist: [
      PlanChecklistCategory(category: '텐트·취침', items: ['텐트', '그라운드시트', '침낭', '매트']),
      PlanChecklistCategory(category: '취사', items: ['버너', '코펠', '식수', '아이스박스']),
      PlanChecklistCategory(category: '의류', items: ['여벌옷', '양말', '모자']),
      PlanChecklistCategory(category: '안전', items: ['구급킷', '헤드랜턴', '보조배터리', '비상 우비']),
    ],
    timeline: [
      PlanTimelineItem(time: '14:00', title: '도착·설치', detail: '입실 후 텐트와 타프를 설치해요.'),
      PlanTimelineItem(time: '17:00', title: '저녁 준비', detail: '해지기 전 취사와 식사를 마쳐요.'),
      PlanTimelineItem(time: '19:30', title: '캠프파이어', detail: '불멍과 휴식 시간.'),
      PlanTimelineItem(time: '22:00', title: '취침', detail: '보온에 유의해요.'),
      PlanTimelineItem(time: '10:00', title: '철수', detail: '장비를 말리고 정리 후 퇴실해요.'),
    ],
  );
}
