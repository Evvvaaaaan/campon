import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/nearby_campsite_cache.dart';
import 'package:campon/main.dart';

Campsite _site(int id, {double lat = 37.5, double lon = 127.0}) =>
    Campsite.fromJson(<String, dynamic>{
      'campsiteId': id,
      'name': '캠핑장 $id',
      'lat': lat,
      'lon': lon,
    });

void main() {
  test('addAll은 여러 번 조회해도 같은 id를 한 번만 담는다', () {
    final cache = NearbyCampsiteCache();

    cache.addAll([_site(1), _site(2)]);
    cache.addAll([_site(2), _site(3)]);

    expect(cache.sites.map((s) => s.id).toList(), [1, 2, 3]);
  });

  test('새로 담긴 캠핑장이 있으면 리스너에 알린다', () {
    final cache = NearbyCampsiteCache();
    var notified = 0;
    cache.addListener(() => notified++);

    cache.addAll([_site(1)]);

    expect(notified, 1);
  });

  test('이미 담긴 캠핑장만 다시 들어오면 알리지 않는다', () {
    final cache = NearbyCampsiteCache();
    cache.addAll([_site(1)]);
    var notified = 0;
    cache.addListener(() => notified++);

    cache.addAll([_site(1)]);

    expect(notified, 0);
  });

  test('조회한 적 없는 지점은 조회 대상이다', () {
    final cache = NearbyCampsiteCache();

    expect(cache.shouldFetchAt(37.5, 127.0), isTrue);
  });

  test('조회한 중심에서 10km 이내면 다시 조회하지 않는다', () {
    final cache = NearbyCampsiteCache();
    cache.markFetched(37.5, 127.0);

    // 위도 0.05도는 약 5.6km라 조회 반경 20km가 거의 그대로 겹친다.
    expect(cache.shouldFetchAt(37.55, 127.0), isFalse);
  });

  test('조회한 중심에서 10km 넘게 벗어나면 다시 조회한다', () {
    final cache = NearbyCampsiteCache();
    cache.markFetched(37.5, 127.0);

    // 위도 0.15도는 약 16.7km라 새 영역이 생긴다.
    expect(cache.shouldFetchAt(37.65, 127.0), isTrue);
  });

  test('forgetFetched로 되돌린 중심은 다시 조회 대상이 된다', () {
    final cache = NearbyCampsiteCache();
    cache.markFetched(37.5, 127.0);

    cache.forgetFetched(37.5, 127.0);

    expect(cache.shouldFetchAt(37.5, 127.0), isTrue);
  });

  test('clear는 누적분과 조회 기록을 함께 비운다', () {
    final cache = NearbyCampsiteCache();
    cache.addAll([_site(1)]);
    cache.markFetched(37.5, 127.0);

    cache.clear();

    expect(cache.sites, isEmpty);
    expect(cache.shouldFetchAt(37.5, 127.0), isTrue);
  });

  test('seed한 지역 중심은 이미 조회한 것으로 쳐서 다시 부르지 않는다', () {
    final cache = NearbyCampsiteCache();

    cache.seed(sites: [_site(1)], lat: 37.5, lon: 127.0);

    expect(cache.sites.map((s) => s.id).toList(), [1]);
    expect(cache.shouldFetchAt(37.5, 127.0), isFalse);
  });
}
