import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('체크리스트에서 체크한 장비는 부족한 장비에서 사라진다', (tester) async {
    await tester.pumpWidget(
      _checklist(checkedItems: {'TENT'}),
    );

    expect(find.textContaining('텐트가 없으면'), findsNothing);
  });

  testWidgets('체크를 해제한 장비는 부족한 장비에 다시 나타난다', (tester) async {
    await tester.pumpWidget(
      _checklist(checkedItems: {'LANTERN'}),
    );

    expect(find.textContaining('텐트가 없으면'), findsOneWidget);
  });

  testWidgets('진행률은 체크된 항목만 센다', (tester) async {
    await tester.pumpWidget(
      _checklist(checkedItems: {'TENT', 'LANTERN'}),
    );

    final total =
        CampData.equipmentOptions.length + CampData.fixedChecklist.length;
    expect(find.text('2 / $total'), findsOneWidget);
  });
}

Widget _checklist({required Set<String> checkedItems}) {
  return MaterialApp(
    home: Scaffold(
      body: ChecklistScreen(
        selectedSite: null,
        checkedItems: checkedItems,
        onToggle: (_) {},
        onReset: () {},
      ),
    ),
  );
}
