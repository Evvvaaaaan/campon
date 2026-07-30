import 'package:flutter_test/flutter_test.dart';
import 'package:campon/main.dart';

Map<String, dynamic> _item(int id) => <String, dynamic>{
  'campsiteId': id,
  'name': '캠핑장 $id',
  'lat': 37.4,
  'lon': 128.5,
};

void main() {
  test('hasNext가 true인 일반 페이지는 항목과 hasNext를 그대로 담는다', () {
    final page = parseCampsitePage(<String, dynamic>{
      'items': [_item(1), _item(2), _item(3)],
      'hasNext': true,
    });

    expect(page.hasNext, isTrue);
    expect(page.items.map((site) => site.id), [1, 2, 3]);
    expect(page.items.first.name, '캠핑장 1');
  });

  test('hasNext가 false면 마지막 페이지로 파싱한다', () {
    final page = parseCampsitePage(<String, dynamic>{
      'items': [_item(1)],
      'hasNext': false,
    });

    expect(page.hasNext, isFalse);
    expect(page.items, hasLength(1));
  });

  test('hasNext가 없거나 불리언이 아니면 false로 처리한다', () {
    final missing = parseCampsitePage(<String, dynamic>{
      'items': [_item(1)],
    });
    expect(missing.hasNext, isFalse);
    expect(missing.items, hasLength(1));

    final notBoolean = parseCampsitePage(<String, dynamic>{
      'items': [_item(1)],
      'hasNext': 'true',
    });
    expect(notBoolean.hasNext, isFalse);
    expect(notBoolean.items, hasLength(1));
  });

  test('items가 없거나 리스트가 아니면 빈 페이지를 반환한다', () {
    final missing = parseCampsitePage(<String, dynamic>{'hasNext': true});
    expect(missing.items, isEmpty);
    expect(missing.hasNext, isFalse);

    final malformed = parseCampsitePage(<String, dynamic>{
      'items': <String, dynamic>{'campsiteId': 1},
      'hasNext': true,
    });
    expect(malformed.items, isEmpty);
    expect(malformed.hasNext, isFalse);
  });

  test('리스트 안의 맵이 아닌 항목은 건너뛴다', () {
    final page = parseCampsitePage(<String, dynamic>{
      'items': [_item(1), 'not-a-map', null, _item(2)],
      'hasNext': true,
    });

    expect(page.items.map((site) => site.id), [1, 2]);
    expect(page.hasNext, isTrue);
  });
}
