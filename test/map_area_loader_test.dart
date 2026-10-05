import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/map_area_loader.dart';
import 'package:campon/campsites/nearby_campsite_cache.dart';
import 'package:campon/main.dart';

Campsite _site(int id) => Campsite.fromJson(<String, dynamic>{
  'campsiteId': id,
  'name': '캠핑장 $id',
});

void main() {
  test('디바운스 시간이 지나기 전에는 조회하지 않는다', () {
    fakeAsync((async) {
      final requested = <({double lat, double lon})>[];
      final loader = MapAreaLoader(
        cache: NearbyCampsiteCache(),
        debounce: const Duration(milliseconds: 500),
        fetchArea: (lat, lon) async {
          requested.add((lat: lat, lon: lon));
          return <Campsite>[_site(1)];
        },
      );

      loader.onCameraIdle(37.5, 127.0);
      async.elapse(const Duration(milliseconds: 400));

      expect(requested, isEmpty);
    });
  });

  test('연속으로 움직이면 마지막 지점만 한 번 조회한다', () {
    fakeAsync((async) {
      final requested = <({double lat, double lon})>[];
      final loader = MapAreaLoader(
        cache: NearbyCampsiteCache(),
        debounce: const Duration(milliseconds: 500),
        fetchArea: (lat, lon) async {
          requested.add((lat: lat, lon: lon));
          return <Campsite>[_site(1)];
        },
      );

      loader.onCameraIdle(37.5, 127.0);
      async.elapse(const Duration(milliseconds: 100));
      loader.onCameraIdle(38.0, 128.0);
      async.elapse(const Duration(seconds: 1));

      expect(requested, [(lat: 38.0, lon: 128.0)]);
    });
  });

  test('이미 조회한 영역 안에서 멎으면 요청하지 않는다', () {
    fakeAsync((async) {
      final cache = NearbyCampsiteCache()..markFetched(37.5, 127.0);
      var calls = 0;
      final loader = MapAreaLoader(
        cache: cache,
        debounce: const Duration(milliseconds: 500),
        fetchArea: (lat, lon) async {
          calls++;
          return <Campsite>[_site(1)];
        },
      );

      loader.onCameraIdle(37.55, 127.0); // 약 5.6km — 조회 반경 안
      async.elapse(const Duration(seconds: 1));

      expect(calls, 0);
    });
  });

  test('조회에 실패하면 그 지점을 되돌려 다시 조회할 수 있게 둔다', () {
    fakeAsync((async) {
      final cache = NearbyCampsiteCache();
      final loader = MapAreaLoader(
        cache: cache,
        debounce: const Duration(milliseconds: 500),
        fetchArea: (lat, lon) async => throw Exception('네트워크 실패'),
      );

      loader.onCameraIdle(37.5, 127.0);
      async.elapse(const Duration(seconds: 1));

      expect(cache.shouldFetchAt(37.5, 127.0), isTrue);
    });
  });

  test('dispose 뒤에는 예약된 조회가 발화하지 않는다', () {
    fakeAsync((async) {
      var calls = 0;
      final loader = MapAreaLoader(
        cache: NearbyCampsiteCache(),
        debounce: const Duration(milliseconds: 500),
        fetchArea: (lat, lon) async {
          calls++;
          return <Campsite>[_site(1)];
        },
      );

      loader.onCameraIdle(37.5, 127.0);
      loader.dispose();
      async.elapse(const Duration(seconds: 1));

      expect(calls, 0);
    });
  });
}
