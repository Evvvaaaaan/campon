import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 주요 화면을 순회하며 `screenshots/`에 캡처를 남긴다 (디자인 검수용).
///
/// 실행:
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/design_walkthrough_test.dart -d [simulator_id]
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, {int ticks = 12}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settle(tester);
    await binding.takeScreenshot(name);
  }

  Future<void> waitForHome(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('오늘의 캠핑을\n정리해볼까요?').evaluate().isNotEmpty) return;
    }
  }

  testWidgets('walk through main screens and capture screenshots', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();

    await tester.pumpWidget(const CampOnApp());
    await settle(tester);

    // 이전 실행의 세션이 기기에 남아 있으면 먼저 로그아웃해서 로그인 화면을 캡처한다.
    if (find.text('개발 계정으로 시작').evaluate().isEmpty) {
      await tester.tap(find.text('설정'));
      await settle(tester);
      final signOut = find.text('로그아웃');
      await tester.ensureVisible(signOut);
      await settle(tester);
      await tester.tap(signOut);
      await settle(tester, ticks: 24);
    }

    await capture(tester, '01_login');

    await tester.tap(find.text('개발 계정으로 시작'));
    await waitForHome(tester);
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
