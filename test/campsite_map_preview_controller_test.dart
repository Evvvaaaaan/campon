import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/campsite_map_view.dart';
import 'package:campon/main.dart';

Campsite _site() => Campsite.fromJson(<String, dynamic>{
  'campsiteId': 1,
  'name': '테스트 캠핑장',
  'lat': 37.4,
  'lon': 128.5,
});

void main() {
  test('select()는 미리보기 대상을 설정하고 clear()는 비운다', () {
    final controller = MapPreviewController();
    expect(controller.value, isNull);

    final site = _site();
    controller.select(site);
    expect(controller.value, site);

    controller.clear();
    expect(controller.value, isNull);
  });
}
