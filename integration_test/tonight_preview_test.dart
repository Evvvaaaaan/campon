import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 실제 기기에서 "오늘 밤 지수" 카드와 "그날 밤 미리보기"를 끝까지 열어 보고
/// 스크린샷을 남긴다. Open-Meteo와 AI 프록시를 실제로 호출한다.
///
/// 실행:
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/tonight_preview_test.dart -d [simulator_id]
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, {int ticks = 12}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// 실제 네트워크 왕복을 기다린다. 나타나면 true.
  Future<bool> waitFor(WidgetTester tester, Finder finder, {int ticks = 60}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  testWidgets('오늘 밤 카드가 실데이터로 뜨고 밤 미리보기까지 이어진다', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    await tester.pumpWidget(const CampOnApp());
    await settle(tester);

    // 이전 실행의 세션이 기기에 남아 있으면 로그인 화면을 건너뛰고 홈으로 바로 간다.
    final devLogin = find.text('개발 계정으로 시작');
    if (devLogin.evaluate().isNotEmpty) {
      await tester.tap(devLogin);
    }
    final reachedHome = await waitFor(
      tester,
      find.text('오늘의 캠핑을\n정리해볼까요?'),
    );
    expect(reachedHome, isTrue, reason: '로그인 후 홈으로 가야 합니다.');

    // Open-Meteo 응답이 오면 점수가 찍힌다.
    final cardLoaded = await waitFor(tester, find.textContaining('/ 100'));
    expect(cardLoaded, isTrue, reason: '오늘 밤 카드가 점수를 표시해야 합니다.');
    expect(find.textContaining('올해 남은 달 없는 토요일 밤'), findsOneWidget);
    await settle(tester);
    await binding.takeScreenshot('tonight_card');

    await tester.tap(find.text('이 밤 미리 보기'));
    final previewOpened = await waitFor(tester, find.textContaining('밤,'));
    expect(previewOpened, isTrue, reason: '밤 미리보기 화면이 열려야 합니다.');

    // 장면은 한 줄씩 나타난다. 위젯은 처음부터 트리에 있고 투명도만 올라가므로
    // finder로는 연출이 끝났는지 알 수 없다. 시간으로 기다린다.
    await settle(tester, ticks: 60);
    expect(find.textContaining('아직 아무도 예약하지 않았다'), findsOneWidget);
    await binding.takeScreenshot('night_preview');
  });
}
