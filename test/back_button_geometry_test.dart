import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 커뮤니티 화면의 뒤로가기 버튼은 캠핑장 상세 화면과 같은 자리·같은 크기여야 한다.
void main() {
  testWidgets('커뮤니티 뒤로가기 버튼이 상세 화면과 같은 위치와 크기를 갖는다', (tester) async {
    await tester.pumpWidget(_detailHost());
    await tester.pumpAndSettle();
    final detail = tester.getRect(find.byType(BackCircleButton));

    await tester.pumpWidget(_communityHost());
    await tester.pumpAndSettle();
    final community = tester.getRect(find.byType(BackCircleButton));

    expect(community, detail);
  });
}

Campsite _site() => Campsite.fromJson({
  'campsiteId': 1,
  'name': '캠핑장 1',
  'score': 90,
  'lat': 37.8,
  'lon': 128.1,
  'distance': 4000,
  'facility': <String>[],
  'equipmentRental': <String>[],
});

Widget _detailHost() {
  return MaterialApp(
    home: Scaffold(
      body: CampsiteDetailScreen(
        api: _StubApi(),
        site: _site(),
        region: CampData.regions.first,
        hasCar: true,
        onBack: () {},
        onCommunity: () {},
        onPrepare: () {},
        isFavorite: false,
        onToggleFavorite: () {},
      ),
    ),
  );
}

Widget _communityHost() {
  return MaterialApp(
    home: Scaffold(
      body: CommunityScreen(api: _StubApi(), site: _site(), onBack: () {}),
    ),
  );
}

class _StubApi extends CampOnApi {
  @override
  Future<List<CampPost>> fetchPosts({
    required int campsiteId,
    int page = 0,
    int size = 20,
  }) async => const <CampPost>[];

  @override
  Future<List<BlockedUser>> getBlockedUsers() async => const <BlockedUser>[];
}
