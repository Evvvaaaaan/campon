import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show Campsite;

/// 하트를 누른 캠핑장을 보관한다.
///
/// 서버에 즐겨찾기 API도, 캠핑장 단건 조회 API도 없다. id만 저장하면 목록을
/// 다시 그릴 수 없어서 캠핑장 정보를 통째로 저장한다. 기기 로컬에만 남으므로
/// 다른 기기로 옮기거나 앱을 지웠다 깔면 목록은 비어 있는 상태로 시작한다.
abstract class FavoritesStore {
  Future<List<Campsite>> read();

  Future<void> write(Iterable<Campsite> sites);
}

class SharedPrefsFavoritesStore implements FavoritesStore {
  const SharedPrefsFavoritesStore();

  static const _key = 'favorite_campsites';

  @override
  Future<List<Campsite>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored == null) return <Campsite>[];

    // 저장 뒤 형식이 바뀌거나 값이 깨져도 즐겨찾기 때문에 앱이 죽으면 안 된다.
    // 읽을 수 없는 항목은 조용히 버린다.
    final sites = <Campsite>[];
    for (final entry in stored) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          sites.add(Campsite.fromJson(decoded));
        }
      } on FormatException {
        continue;
      }
    }
    return sites;
  }

  @override
  Future<void> write(Iterable<Campsite> sites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      sites.map((site) => jsonEncode(site.toJson())).toList(growable: false),
    );
  }
}

/// 테스트와 미리보기에서 쓰는 메모리 구현.
class InMemoryFavoritesStore implements FavoritesStore {
  InMemoryFavoritesStore([Iterable<Campsite>? initial])
    : _sites = <Campsite>[...?initial];

  final List<Campsite> _sites;

  @override
  Future<List<Campsite>> read() async => <Campsite>[..._sites];

  @override
  Future<void> write(Iterable<Campsite> sites) async {
    _sites
      ..clear()
      ..addAll(sites);
  }
}
