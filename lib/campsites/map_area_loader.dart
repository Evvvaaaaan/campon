import 'dart:async';

import '../main.dart' show Campsite;
import 'nearby_campsite_cache.dart';

typedef FetchArea = Future<List<Campsite>> Function(double lat, double lon);

/// 지도가 멎을 때마다 그 지점의 캠핑장을 받아 캐시에 쌓는다.
///
/// 지도 위젯은 WebView라 위젯 테스트로 못 돌리므로, 언제 조회할지 정하는 판단은
/// 전부 여기에 모아 순수 Dart로 검증한다.
class MapAreaLoader {
  MapAreaLoader({
    required this.cache,
    required this.fetchArea,
    this.debounce = const Duration(milliseconds: 500),
  });

  final NearbyCampsiteCache cache;
  final FetchArea fetchArea;
  final Duration debounce;

  Timer? _timer;

  void onCameraIdle(double lat, double lon) {
    _timer?.cancel();
    _timer = Timer(debounce, () => _load(lat, lon));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _load(double lat, double lon) async {
    if (!cache.shouldFetchAt(lat, lon)) return;
    // 먼저 기록해 두어야 응답을 기다리는 동안 같은 영역을 다시 요청하지 않는다.
    cache.markFetched(lat, lon);
    try {
      cache.addAll(await fetchArea(lat, lon));
    } catch (_) {
      // 지도를 쓰는 도중이라 오류를 띄우지 않는다. 대신 기록을 되돌려 재시도할 수 있게 둔다.
      cache.forgetFetched(lat, lon);
    }
  }
}
