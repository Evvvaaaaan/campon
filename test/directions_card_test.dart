import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/location/location_service.dart';
import 'package:campon/main.dart';

class _FakeLocationProvider implements LocationProvider {
  _FakeLocationProvider.success(LocationPoint point)
    : _point = point,
      _error = null;

  _FakeLocationProvider.blocked(LocationBlockedException error)
    : _point = null,
      _error = error;

  final LocationPoint? _point;
  final LocationBlockedException? _error;
  LocationBlockReason? openedFor;

  @override
  Future<LocationPoint> current() async {
    final error = _error;
    if (error != null) {
      throw error;
    }
    return _point!;
  }

  @override
  Future<void> openSettings(LocationBlockReason reason) async {
    openedFor = reason;
  }
}

Campsite _site() => Campsite.fromJson(<String, dynamic>{
  'campsiteId': 7,
  'name': '가리왕산 캠핑장',
  'lat': 37.4,
  'lon': 128.5,
});

Future<void> _pumpCard(
  WidgetTester tester, {
  required LocationProvider location,
  required DirectionsFetcher fetchDirections,
  bool hasCar = true,
  UrlOpener? openUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DirectionsCard(
          fetchDirections: fetchDirections,
          location: location,
          site: _site(),
          hasCar: hasCar,
          openUrl: openUrl,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('현재 위치 좌표를 출발지로 넘겨 거리와 예상 시간을 보여준다', (tester) async {
    double? sentOriginX;
    double? sentOriginY;
    await _pumpCard(
      tester,
      location: _FakeLocationProvider.success(
        const LocationPoint(lat: 37.5665, lon: 126.9780),
      ),
      fetchDirections:
          ({
            required double originX,
            required double originY,
            required double destX,
            required double destY,
          }) async {
            sentOriginX = originX;
            sentOriginY = originY;
            return const DirectionResult(
              distanceMeters: 132000,
              durationSeconds: 7200,
            );
          },
    );

    await tester.tap(find.text('경로 확인'));
    await tester.pumpAndSettle();

    expect(sentOriginX, 126.9780);
    expect(sentOriginY, 37.5665);
    expect(find.text('132km'), findsOneWidget);
    expect(find.text('2시간'), findsOneWidget);
  });

  testWidgets('권한이 영구 거부되면 설정 열기 버튼으로 안내한다', (tester) async {
    final location = _FakeLocationProvider.blocked(
      const LocationBlockedException(
        LocationBlockReason.deniedForever,
        '설정에서 위치 권한을 허용해주세요.',
      ),
    );
    await _pumpCard(
      tester,
      location: location,
      fetchDirections:
          ({
            required double originX,
            required double originY,
            required double destX,
            required double destY,
          }) async {
            fail('위치를 얻지 못하면 길찾기 API를 호출하지 않아야 한다.');
          },
    );

    await tester.tap(find.text('경로 확인'));
    await tester.pumpAndSettle();

    expect(find.text('설정에서 위치 권한을 허용해주세요.'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pump();

    expect(location.openedFor, LocationBlockReason.deniedForever);
  });

  testWidgets('기기 위치 서비스가 꺼져 있으면 위치 설정 열기로 안내한다', (tester) async {
    final location = _FakeLocationProvider.blocked(
      const LocationBlockedException(
        LocationBlockReason.serviceDisabled,
        '기기 위치 서비스가 꺼져 있어요.',
      ),
    );
    await _pumpCard(
      tester,
      location: location,
      fetchDirections:
          ({
            required double originX,
            required double originY,
            required double destX,
            required double destY,
          }) async {
            fail('위치를 얻지 못하면 길찾기 API를 호출하지 않아야 한다.');
          },
    );

    await tester.tap(find.text('경로 확인'));
    await tester.pumpAndSettle();

    expect(find.text('기기 위치 서비스가 꺼져 있어요.'), findsOneWidget);
    await tester.tap(find.text('위치 설정 열기'));
    await tester.pump();

    expect(location.openedFor, LocationBlockReason.serviceDisabled);
  });

  Future<void> loadResult(WidgetTester tester, {required bool hasCar, required UrlOpener openUrl}) async {
    await _pumpCard(
      tester,
      location: _FakeLocationProvider.success(
        const LocationPoint(lat: 37.5665, lon: 126.9780),
      ),
      fetchDirections:
          ({
            required double originX,
            required double originY,
            required double destX,
            required double destY,
          }) async => const DirectionResult(
            distanceMeters: 132000,
            durationSeconds: 7200,
          ),
      hasCar: hasCar,
      openUrl: openUrl,
    );
    await tester.tap(find.text('경로 확인'));
    await tester.pumpAndSettle();
  }

  testWidgets('경로 확인 후 카카오맵으로 이동을 누르면 출발지·도착지 좌표로 길찾기 URL을 연다', (
    tester,
  ) async {
    Uri? openedUri;
    await loadResult(
      tester,
      hasCar: true,
      openUrl: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    expect(find.text('카카오맵으로 이동'), findsOneWidget);
    await tester.tap(find.text('카카오맵으로 이동'));
    await tester.pump();

    expect(
      openedUri,
      Uri.parse(
        'http://m.map.kakao.com/scheme/route'
        '?sp=37.5665,126.978'
        '&ep=37.4,128.5'
        '&by=car',
      ),
    );
  });

  testWidgets('차량이 없으면 대중교통 경로로 카카오맵을 연다', (tester) async {
    Uri? openedUri;
    await loadResult(
      tester,
      hasCar: false,
      openUrl: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    await tester.tap(find.text('카카오맵으로 이동'));
    await tester.pump();

    expect(openedUri?.queryParameters['by'], 'publictransit');
  });

  testWidgets('카카오맵을 열지 못하면 안내 스낵바를 보여준다', (tester) async {
    await loadResult(tester, hasCar: true, openUrl: (uri) async => false);

    await tester.tap(find.text('카카오맵으로 이동'));
    await tester.pump();

    expect(find.text('링크를 열지 못했습니다.'), findsOneWidget);
  });
}
