import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legal links open the built-in terms when no public URL is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: LegalLinkRow())),
      ),
    );

    await tester.tap(find.text('이용약관'));
    await tester.pumpAndSettle();

    expect(find.textContaining('제1조 (목적)'), findsOneWidget);
    expect(find.textContaining('AI 생성 결과'), findsOneWidget);
  });

  testWidgets('privacy document discloses location and AI processors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentScreen(document: LegalDocument.privacy),
      ),
    );

    expect(find.textContaining('현재 위치'), findsWidgets);
    expect(find.textContaining('Google Gemini API'), findsOneWidget);
  });
}
