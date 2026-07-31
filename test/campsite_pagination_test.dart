import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/campsite_pagination.dart';

void main() {
  test('hasNext가 false가 될 때까지 페이지를 이어붙인다', () async {
    final calledPages = <int>[];
    Future<PageResult<int>> fetchPage(int page) async {
      calledPages.add(page);
      if (page == 0) return (items: [1, 2, 3], hasNext: true);
      if (page == 1) return (items: [4, 5], hasNext: true);
      return (items: [6], hasNext: false);
    }

    final result = await aggregateAllPages<int>(fetchPage);

    expect(result, [1, 2, 3, 4, 5, 6]);
    expect(calledPages, [0, 1, 2]);
  });

  test('hasNext가 처음부터 false면 첫 페이지만 호출한다', () async {
    var calls = 0;
    Future<PageResult<int>> fetchPage(int page) async {
      calls++;
      return (items: [1], hasNext: false);
    }

    final result = await aggregateAllPages<int>(fetchPage);

    expect(result, [1]);
    expect(calls, 1);
  });

  test('maxPages에 도달하면 hasNext가 true여도 멈춘다', () async {
    var calls = 0;
    Future<PageResult<int>> fetchPage(int page) async {
      calls++;
      return (items: [page], hasNext: true); // 항상 다음 페이지가 있다고 응답
    }

    final result = await aggregateAllPages<int>(fetchPage, maxPages: 3);

    expect(result, [0, 1, 2]);
    expect(calls, 3);
  });
}
