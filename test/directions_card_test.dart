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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DirectionsCard(
          fetchDirections: fetchDirections,
          location: location,
          site: _site(),
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
}
