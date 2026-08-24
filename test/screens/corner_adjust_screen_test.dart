import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fosscanner/screens/corner_adjust_screen.dart';
import 'package:fosscanner/widgets/corner_overlay.dart';

void main() {
  testWidgets('shows a loading state while the photo is being decoded', (
    tester,
  ) async {
    // Genuinely-invalid bytes are intentional: this only exercises the
    // widget's build before/without the async _initialize() chain
    // resolving successfully. Real image decoding via
    // ui.instantiateImageCodec is known to hang forever under
    // flutter_test's fake-time test binding even though it works fine in
    // the real app (verified separately) — full pipeline correctness is
    // covered by the Phase 0 spike script and on-device testing instead.
    final bytes = Uint8List.fromList(const [0, 1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(home: CornerAdjustScreen(originalBytes: bytes)),
    );

    expect(find.text('Adjust corners'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'shows an error state (not an infinite spinner) when decoding fails',
    (tester) async {
      final bytes = Uint8List.fromList(const [0, 1, 2, 3]);

      await tester.pumpWidget(
        MaterialApp(home: CornerAdjustScreen(originalBytes: bytes)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not read this photo'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'corner handles stay on valid pixels and meet the minimum tap target',
    (tester) async {
      List<Offset>? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CornerOverlay(
                imageBytes: File('assets/icon/icon.png').readAsBytesSync(),
                imageSize: const Size(100, 100),
                corners: const [
                  Offset(10, 10),
                  Offset(90, 10),
                  Offset(90, 90),
                  Offset(10, 90),
                ],
                onChanged: (corners) => changed = corners,
              ),
            ),
          ),
        ),
      );

      final firstHandle = find.byType(GestureDetector).first;
      expect(tester.getSize(firstHandle), const Size.square(48));

      await tester.drag(firstHandle, const Offset(400, 400));
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed!.first, const Offset(99, 99));
    },
  );

  testWidgets('a cancelled corner drag restores the committed position', (
    tester,
  ) async {
    List<Offset>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: CornerOverlay(
            imageBytes: File('assets/icon/icon.png').readAsBytesSync(),
            imageSize: const Size(100, 100),
            corners: const [
              Offset(10, 10),
              Offset(90, 10),
              Offset(90, 90),
              Offset(10, 90),
            ],
            onChanged: (corners) => changed = corners,
          ),
        ),
      ),
    );

    final firstHandle = find.byType(GestureDetector).first;
    final originalCenter = tester.getCenter(firstHandle);
    final gesture = await tester.startGesture(originalCenter);
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    expect(tester.getCenter(firstHandle), isNot(originalCenter));

    await gesture.cancel();
    await tester.pump();

    expect(changed, isNull);
    expect(tester.getCenter(firstHandle), originalCenter);
  });

  testWidgets('all boundary corners retain full 48 pixel hit regions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: CornerOverlay(
              imageBytes: File('assets/icon/icon.png').readAsBytesSync(),
              imageSize: const Size(100, 100),
              corners: const [
                Offset.zero,
                Offset(99, 0),
                Offset(99, 99),
                Offset(0, 99),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final overlayRect = tester.getRect(find.byType(CornerOverlay));
    for (final handle in find.byType(GestureDetector).evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == handle));
      expect(rect.size, const Size.square(48));
      expect(rect.left, greaterThanOrEqualTo(overlayRect.left));
      expect(rect.top, greaterThanOrEqualTo(overlayRect.top));
      expect(rect.right, lessThanOrEqualTo(overlayRect.right));
      expect(rect.bottom, lessThanOrEqualTo(overlayRect.bottom));
    }
  });

  testWidgets('corner handles expose operable accessibility actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    List<Offset>? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: CornerOverlay(
            imageBytes: File('assets/icon/icon.png').readAsBytesSync(),
            imageSize: const Size(100, 100),
            corners: const [
              Offset(10, 10),
              Offset(90, 10),
              Offset(90, 90),
              Offset(10, 90),
            ],
            onChanged: (corners) => changed = corners,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Top-left corner'), findsOneWidget);
    expect(find.bySemanticsLabel('Top-right corner'), findsOneWidget);
    expect(find.bySemanticsLabel('Bottom-right corner'), findsOneWidget);
    expect(find.bySemanticsLabel('Bottom-left corner'), findsOneWidget);

    final topLeft = tester.getSemantics(
      find.bySemanticsLabel('Top-left corner'),
    );
    expect(topLeft.getSemanticsData().customSemanticsActionIds, hasLength(4));
    expect(
      topLeft.getSemanticsData().hasAction(SemanticsAction.customAction),
      isTrue,
    );

    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      topLeft.id,
      SemanticsAction.customAction,
      topLeft.getSemanticsData().customSemanticsActionIds!.first,
    );
    await tester.pump();
    expect(changed, isNotNull);
    expect(changed!.first, isNot(const Offset(10, 10)));
    semantics.dispose();
  });
}
