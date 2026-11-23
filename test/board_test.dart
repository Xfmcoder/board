import 'package:board/models.dart';
import 'package:board/storage.dart';
import 'package:board/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('plan serialises and restores', () {
    final BoardPlan p = BoardPlan.empty('টেস্ট প্লেন');
    p.addStep(kind: NodeKind.start, title: 'শুরু');
    p.addStep(title: 'ধাপ ২', note: 'বিস্তারিত');
    final BoardPlan back = BoardPlan.fromJson(p.toJson());
    expect(back.name, 'টেস্ট প্লেন');
    expect(back.nodes.length, 2);
    expect(back.edges.length, 1);
    expect(back.edges.first.from, back.nodes.first.id);
    expect(back.nodes.last.note, 'বিস্তারিত');
  });

  test('steps link in order and progress counts done', () {
    final BoardPlan p = BoardPlan.empty('p');
    final PlanNode a = p.addStep(kind: NodeKind.start, title: 'a');
    final PlanNode b = p.addStep(title: 'b');
    expect(p.edges.single.to, b.id);
    expect(a.done, false);
    p.nodes.last.done = true;
    expect(p.doneCount, 1);
    expect(p.progress, 0.5);

    p.removeNode(a.id);
    expect(p.nodes.length, 1);
    expect(p.edges.isEmpty, true);
  });

  test('store round trip', () async {
    final PlanStore store = PlanStore();
    final BoardPlan p = BoardPlan.empty('সেভড');
    p.addStep(title: 'এক');
    await store.save(p);
    final List<BoardPlan> all = await store.loadAll();
    expect(all.length, 1);
    expect(all.first.name, 'সেভড');
    await store.delete(p.id);
    expect((await store.loadAll()).isEmpty, true);
  });

  testWidgets('home renders and creates a plan', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('বোর্ড'), findsOneWidget);
    expect(find.text('নতুন প্লেন'), findsOneWidget);

    await tester.tap(find.text('নতুন প্লেন'));
    await tester.pumpAndSettle();
    expect(find.text('তৈরি করো'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'অফিস কাজ');
    await tester.tap(find.text('তৈরি করো'));
    // The canvas runs a repeating connector animation, so never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // Lands on the canvas screen for the new plan.
    expect(find.text('অফিস কাজ'), findsWidgets);
  });
}
