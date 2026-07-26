import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 실서버(campon.seohamin.com)를 상대로 개발 계정 로그인 → 홈 진입을 검증한다.
///
/// 실행: flutter test integration_test -d [simulator_id]
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dev login reaches the home screen against the real server', (
    tester,
  ) async {
    await tester.pumpWidget(const CampOnApp());
    await tester.pumpAndSettle();

    expect(find.text('캠핑을 시작할\n계정을 선택해주세요'), findsOneWidget);

    final devLoginButton = find.text('개발 계정으로 시작');
    expect(devLoginButton, findsOneWidget);

    await tester.ensureVisible(devLoginButton);
    await tester.tap(devLoginButton);

    // 실서버 왕복(dev user 생성 + JWT 발급)을 기다린다.
    var reachedHome = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('오늘의 캠핑을\n정리해볼까요?').evaluate().isNotEmpty) {
        reachedHome = true;
        break;
      }
    }

    expect(reachedHome, isTrue, reason: '로그인 후 홈 화면으로 이동해야 합니다.');
  });
}
