import 'package:flutter_test/flutter_test.dart';
import 'package:campon/main.dart';

void main() {
  test('nearbyQuery는 좌표와 반경을 서버가 읽는 문자열로 만든다', () {
    final query = CampOnApi.nearbyQuery(
      lat: 37.5665,
      lon: 126.978,
      radius: 20000,
      page: 2,
      size: 100,
    );

    expect(query, <String, String>{
      'lat': '37.5665',
      'lon': '126.978',
      'radius': '20000',
      'size': '100',
      'page': '2',
    });
  });
}
