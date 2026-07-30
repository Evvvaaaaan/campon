import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// 현재 위치를 얻지 못한 이유. 사용자에게 보여줄 안내와 이동할 설정 화면이 달라진다.
enum LocationBlockReason {
  /// 기기 자체의 위치 서비스가 꺼져 있다.
  serviceDisabled,

  /// 앱 위치 권한이 거부됐다. 다시 요청할 수 있다.
  denied,

  /// 앱 위치 권한이 영구 거부됐다. 설정 화면에서만 바꿀 수 있다.
  deniedForever,

  /// 권한은 있으나 좌표 획득에 실패했다(타임아웃 등).
  failed,
}

class LocationPoint {
  const LocationPoint({required this.lat, required this.lon});

  final double lat;
  final double lon;
}

class LocationBlockedException implements Exception {
  const LocationBlockedException(this.reason, this.message);

  final LocationBlockReason reason;
  final String message;

  @override
  String toString() => message;
}

abstract interface class LocationProvider {
  /// 권한을 확인·요청한 뒤 현재 좌표를 돌려준다.
  /// 실패하면 [LocationBlockedException]을 던진다.
  Future<LocationPoint> current();

  /// [reason]에 맞는 설정 화면을 연다.
  Future<void> openSettings(LocationBlockReason reason);
}

class GeolocatorLocationProvider implements LocationProvider {
  const GeolocatorLocationProvider();

  static const _timeout = Duration(seconds: 10);

  @override
  Future<LocationPoint> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationBlockedException(
        LocationBlockReason.serviceDisabled,
        '기기 위치 서비스가 꺼져 있어요.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationBlockedException(
        LocationBlockReason.deniedForever,
        '설정에서 위치 권한을 허용해주세요.',
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationBlockedException(
        LocationBlockReason.denied,
        '현재 위치를 쓰려면 위치 권한이 필요해요.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _timeout,
        ),
      );
      return LocationPoint(lat: position.latitude, lon: position.longitude);
    } on TimeoutException {
      throw const LocationBlockedException(
        LocationBlockReason.failed,
        '현재 위치를 확인하지 못했어요.',
      );
    } catch (error) {
      throw LocationBlockedException(
        LocationBlockReason.failed,
        '현재 위치를 확인하지 못했어요. ($error)',
      );
    }
  }

  @override
  Future<void> openSettings(LocationBlockReason reason) async {
    if (reason == LocationBlockReason.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }
}
