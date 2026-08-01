import 'package:shared_preferences/shared_preferences.dart';

/// 하트를 누른 캠핑장 id를 보관한다.
///
/// 서버에 즐겨찾기 API가 없어 기기 로컬에만 남는다. 따라서 다른 기기로 옮기거나
/// 앱을 지웠다 깔면 목록은 비어 있는 상태로 시작한다.
abstract class FavoritesStore {
  Future<Set<int>> read();

  Future<void> write(Set<int> ids);
}

class SharedPrefsFavoritesStore implements FavoritesStore {
  const SharedPrefsFavoritesStore();

  static const _key = 'favorite_campsite_ids';

  @override
  Future<Set<int>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored == null) return <int>{};
    // 저장 뒤 형식이 바뀌거나 값이 깨져도 즐겨찾기 때문에 앱이 죽으면 안 된다.
    // 읽을 수 없는 항목은 조용히 버린다.
    return stored
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  @override
  Future<void> write(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      ids.map((id) => id.toString()).toList(growable: false),
    );
  }
}

/// 테스트와 미리보기에서 쓰는 메모리 구현.
class InMemoryFavoritesStore implements FavoritesStore {
  InMemoryFavoritesStore([Set<int>? initial])
    : _ids = <int>{...?initial};

  final Set<int> _ids;

  @override
  Future<Set<int>> read() async => <int>{..._ids};

  @override
  Future<void> write(Set<int> ids) async {
    _ids
      ..clear()
      ..addAll(ids);
  }
}
