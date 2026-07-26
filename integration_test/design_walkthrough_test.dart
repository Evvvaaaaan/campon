import 'dart:io';

import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 주요 화면을 순회하며 각 화면에서 마커 파일을 남긴다.
/// 호스트 스크립트가 마커를 감지해 simctl 스크린샷을 찍는다 (디자인 검수용).
///
/// 실행:
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/design_walkthrough_test.dart -d [simulator_id]
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final markerDir = Directory('${Directory.systemTemp.path}/markers');

  Future<void> settle(WidgetTester tester, {int ticks = 12}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settle(tester);
    markerDir.createSync(recursive: true);
    File('${markerDir.path}/$name').writeAsStringSync(name);
    // 호스트가 스크린샷을 찍을 시간을 준다.
    await settle(tester, ticks: 10);
  }

  testWidgets('walk through main screens and leave capture markers', (
    tester,
  ) async {
    await tester.pumpWidget(const CampOnApp());
    await capture(tester, '01_login');

    await tester.tap(find.text('개발 계정으로 시작'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('오늘의 캠핑을\n정리해볼까요?').evaluate().isNotEmpty) {
        break;
      }
    }
    await capture(tester, '02_home');

    await tester.tap(find.text('캠핑장'));
    await settle(tester);
    await capture(tester, '03_browse');

    await tester.tap(find.text('체크리스트'));
    await capture(tester, '04_checklist');

    await tester.tap(find.text('설정'));
    await capture(tester, '05_settings');

    // 온보딩에서는 탭바가 숨겨지므로 마지막에 진입한다.
    await tester.tap(find.text('추천'));
    await capture(tester, '06_onboarding_basics');
  });
}
