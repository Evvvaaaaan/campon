import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../main.dart' show Campsite;

/// 지도를 움직이는 동안 조회한 캠핑장을 세션 메모리에 누적한다.
///
/// 지도 위젯은 WebView라 위젯 테스트로 돌릴 수 없다. 그래서 "다시 조회할지",
/// "무엇을 마커로 그릴지" 같은 판단은 전부 이 클래스에 모아 테스트 가능하게 둔다.
class NearbyCampsiteCache extends ChangeNotifier {
  /// 조회 반경(20km)의 절반. 두 중심이 이보다 가까우면 조회 영역이 대부분 겹친다.
  static const refetchThresholdMeters = 10000.0;

  final _byId = <int, Campsite>{};
  final _fetchedCenters = <({double lat, double lon})>[];

  /// 처음 담긴 순서를 유지한 누적분.
  List<Campsite> get sites => List.unmodifiable(_byId.values);

  /// 이미 조회한 중심에서 [refetchThresholdMeters] 이내면 건너뛴다.
  bool shouldFetchAt(double lat, double lon) {
    for (final center in _fetchedCenters) {
      if (_distanceMeters(center.lat, center.lon, lat, lon) <
          refetchThresholdMeters) {
        return false;
      }
    }
    return true;
  }

  void markFetched(double lat, double lon) {
    _fetchedCenters.add((lat: lat, lon: lon));
  }

  /// 조회에 실패한 중심을 되돌려, 사용자가 그 자리로 다시 오면 재시도하게 한다.
  void forgetFetched(double lat, double lon) {
    _fetchedCenters.removeWhere(
      (center) => center.lat == lat && center.lon == lon,
    );
  }

  /// 지역을 바꾸면 이전 지역에서 쌓은 마커가 남지 않게 통째로 비운다.
  void clear() {
    if (_byId.isEmpty && _fetchedCenters.isEmpty) return;
    _byId.clear();
    _fetchedCenters.clear();
    notifyListeners();
  }

  /// 지역 조회 결과를 심는다. 카카오맵은 최초 렌더 직후에도 idle을 발화하므로,
  /// 그 중심을 조회한 것으로 기록해 두지 않으면 지도를 열 때마다 같은 영역을 다시 부른다.
  void seed({
    required Iterable<Campsite> sites,
    required double lat,
    required double lon,
  }) {
    addAll(sites);
    if (shouldFetchAt(lat, lon)) {
      markFetched(lat, lon);
    }
  }

  void addAll(Iterable<Campsite> found) {
    final before = _byId.length;
    for (final site in found) {
      _byId.putIfAbsent(site.id, () => site);
    }
    // 마커는 리빌드마다 통째로 다시 주입되므로, 새로 담긴 게 없으면 알리지 않는다.
    if (_byId.length != before) {
      notifyListeners();
    }
  }
}

const _earthRadiusMeters = 6371000.0;

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return _earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;
