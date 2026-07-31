import 'package:campon/tonight/sky_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// 널리 쓰이는 기준 삭(new moon): 2000-01-06 18:14 UTC.
final _newMoon2000 = DateTime.utc(2000, 1, 6, 18, 14);

/// 삭망월(달의 위상이 한 바퀴 도는 주기).
const _synodicMonth = Duration(minutes: 42524); // 29.53일

void main() {
  group('달의 위상', () {
    test('기준 삭에서 조도가 0에 가깝다', () {
      expect(moonIllumination(_newMoon2000), lessThan(0.01));
    });

    test('삭에서 반 주기 뒤는 보름이다', () {
      final full = _newMoon2000.add(_synodicMonth ~/ 2);
      expect(moonIllumination(full), greaterThan(0.97));
    });

    test('한 삭망월 뒤 다시 삭으로 돌아온다', () {
      expect(
        moonIllumination(_newMoon2000.add(_synodicMonth)),
        lessThan(0.01),
      );
    });

    test('상현 무렵은 절반쯤 찬다', () {
      final quarter = _newMoon2000.add(_synodicMonth ~/ 4);
      expect(moonIllumination(quarter), inInclusiveRange(0.35, 0.65));
    });
  });

  group('달의 고도', () {
    test('삭일 때 달은 밤에 지평선 아래에 있다', () {
      // 삭이면 달은 태양과 같은 방향이라 해와 함께 지고 밤에는 뜨지 않는다.
      for (final hour in [22, 0, 2]) {
        final at = kstToUtc(DateTime(2026, 8, 12, hour));
        expect(
          moonAltitudeDeg(at, lat: 37.82, lon: 128.16),
          lessThan(0),
          reason: 'KST $hour시',
        );
      }
    });

    test('고도는 -90도와 90도 사이다', () {
      for (var day = 0; day < 30; day++) {
        final at = kstToUtc(DateTime(2026, 3, 1 + day, 23));
        final altitude = moonAltitudeDeg(at, lat: 37.82, lon: 128.16);
        expect(altitude, inInclusiveRange(-90, 90));
      }
    });
  });

  group('달빛 방해도', () {
    test('삭인 밤은 방해도가 0에 가깝다', () {
      final interference = moonInterferenceForNight(
        DateTime(2026, 8, 12),
        lat: 37.82,
        lon: 128.16,
      );
      expect(interference, lessThan(0.05));
    });

    test('보름인 밤은 방해도가 높다', () {
      final interference = moonInterferenceForNight(
        DateTime(2026, 7, 29),
        lat: 37.82,
        lon: 128.16,
      );
      expect(interference, greaterThan(0.6));
    });

    test('항상 0과 1 사이다', () {
      for (var day = 0; day < 40; day++) {
        final interference = moonInterferenceForNight(
          DateTime(2026, 5, 1).add(Duration(days: day)),
          lat: 33.49,
          lon: 126.53,
        );
        expect(interference, inInclusiveRange(0, 1));
      }
    });
  });

  group('올해 남은 달 없는 토요일 밤', () {
    test('연초에 세면 연중에 셀 때보다 많다', () {
      const lat = 37.82;
      const lon = 128.16;
      final fromJanuary = darkSaturdayNightsLeftInYear(
        DateTime(2026, 1, 1),
        lat: lat,
        lon: lon,
      );
      final fromAugust = darkSaturdayNightsLeftInYear(
        DateTime(2026, 8, 1),
        lat: lat,
        lon: lon,
      );
      expect(fromJanuary, greaterThan(fromAugust));
    });

    test('1년에 있을 수 있는 토요일 수를 넘지 않는다', () {
      final count = darkSaturdayNightsLeftInYear(
        DateTime(2026, 1, 1),
        lat: 37.82,
        lon: 128.16,
      );
      expect(count, inInclusiveRange(1, 53));
    });

    test('12월 31일에 세면 0 또는 1이다', () {
      final count = darkSaturdayNightsLeftInYear(
        DateTime(2026, 12, 31),
        lat: 37.82,
        lon: 128.16,
      );
      expect(count, lessThanOrEqualTo(1));
    });
  });
}
