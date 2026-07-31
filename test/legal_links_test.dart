import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 약관 링크는 URL이 `--dart-define`으로 들어왔을 때만 보여야 한다.
/// 그래서 define 없이 도는 기본 `flutter test`와, URL을 넣고 도는 제출 빌드 점검
/// 양쪽에서 같은 규칙을 검사한다.
void main() {
  Future<void> pumpRow(WidgetTester tester) {
    return tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LegalLinkRow())),
    );
  }

  testWidgets('URL이 설정된 문서만 링크로 보여준다', (tester) async {
    await pumpRow(tester);

    expect(
      find.text('이용약관'),
      LegalConfig.termsOfServiceUrl.isEmpty ? findsNothing : findsOneWidget,
    );
    expect(
      find.text('개인정보 처리방침'),
      LegalConfig.privacyPolicyUrl.isEmpty ? findsNothing : findsOneWidget,
    );
  });

  testWidgets('두 URL이 모두 있으면 가운뎃점으로 구분한다', (tester) async {
    await pumpRow(tester);

    final bothConfigured =
        LegalConfig.termsOfServiceUrl.isNotEmpty &&
        LegalConfig.privacyPolicyUrl.isNotEmpty;
    expect(find.text('·'), bothConfigured ? findsOneWidget : findsNothing);
  });

  test('hasLinks는 URL이 하나라도 있을 때만 참이다', () {
    expect(
      LegalConfig.hasLinks,
      LegalConfig.termsOfServiceUrl.isNotEmpty ||
          LegalConfig.privacyPolicyUrl.isNotEmpty,
    );
  });
}
