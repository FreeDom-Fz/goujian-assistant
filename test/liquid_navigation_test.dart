import 'package:goujian_assistant/ui/app_navigation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> render(
    WidgetTester tester, {
    bool rtl = false,
    double scale = 1,
    bool reduceMotion = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduceMotion,
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: Text('page-$selected'),
                bottomNavigationBar: AppNavigation(
                  selectedIndex: selected,
                  onSelected: (index) => setState(() => selected = index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tap and drag commit navigation; cancelled drag preserves page', (
    tester,
  ) async {
    await render(tester);
    await tester.tap(find.byKey(const ValueKey('navigation-1')));
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    final start = tester.getCenter(find.byKey(const ValueKey('navigation-0')));
    final end = tester.getCenter(find.byKey(const ValueKey('navigation-1')));
    var gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    expect(find.text('page-1'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    gesture = await tester.startGesture(end);
    await gesture.moveTo(start);
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL drag and large text fit a narrow screen', (tester) async {
    await render(tester, rtl: true, scale: 2);
    final start = tester.getCenter(find.byKey(const ValueKey('navigation-0')));
    final end = tester.getCenter(find.byKey(const ValueKey('navigation-1')));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('animated selection settles on the requested tab', (
    tester,
  ) async {
    await render(tester, reduceMotion: false);
    await tester.tap(find.byKey(const ValueKey('navigation-1')));
    await tester.pumpAndSettle();
    final lens = tester.getCenter(find.byKey(const Key('navigation-lens')));
    final tab = tester.getCenter(find.byKey(const ValueKey('navigation-1')));
    expect(lens.dx, closeTo(tab.dx, 1));
    expect(find.text('page-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'press previews the touched tab without switching; cancellation rolls back',
    (tester) async {
      await render(tester, reduceMotion: false);
      final target = tester.getCenter(
        find.byKey(const ValueKey('navigation-1')),
      );
      final gesture = await tester.startGesture(target);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('page-0'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('navigation-lens'))).dx,
        closeTo(target.dx, 1),
      );
      final transform = tester.widget<Transform>(
        find.byKey(const Key('navigation-lens-transform')),
      );
      expect(transform.transform.storage[0], lessThan(1.10));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.text('page-0'), findsOneWidget);
      final original = tester.getCenter(
        find.byKey(const ValueKey('navigation-0')),
      );
      expect(
        tester.getCenter(find.byKey(const Key('navigation-lens'))).dx,
        closeTo(original.dx, 1),
      );
    },
  );

  testWidgets(
    'mouse hover never changes tabs and keyboard activation still works',
    (tester) async {
      await render(tester, reduceMotion: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('navigation-1'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('page-0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('page-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
