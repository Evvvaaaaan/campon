import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공개 URL이 없더라도 앱 안의 전문으로 이동할 수 있어야 한다.
/// URL이 설정된 릴리스 빌드에서는 같은 링크가 공개 문서를 연다.
void main() {
  Future<void> pumpRow(WidgetTester tester) {
    return tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LegalLinkRow())),
    );
  }

  testWidgets('두 법적 문서를 항상 링크로 보여준다', (tester) async {
    await pumpRow(tester);

    expect(find.text('이용약관'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
  });

  testWidgets('두 문서를 가운뎃점으로 구분한다', (tester) async {
    await pumpRow(tester);

    expect(find.text('·'), findsOneWidget);
  });
}
