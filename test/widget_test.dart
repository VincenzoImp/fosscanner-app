import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:fosscanner/main.dart';
import 'package:fosscanner/models/scanned_page.dart';
import 'package:fosscanner/screens/corner_adjust_screen.dart';
import 'package:fosscanner/screens/scanner_home_page.dart';

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform({
    this.cameraSupported = true,
    LostDataResponse? lostData,
    this.image,
  }) : lostData = lostData ?? LostDataResponse.empty();

  final bool cameraSupported;
  final LostDataResponse lostData;
  final XFile? image;
  var lostDataCalls = 0;
  var imageCalls = 0;

  @override
  bool supportsImageSource(ImageSource source) =>
      source != ImageSource.camera || cameraSupported;

  @override
  Future<LostDataResponse> getLostData() async {
    lostDataCalls++;
    return lostData;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    imageCalls++;
    return image;
  }
}

class _CameraUnavailablePlatform extends ImagePickerPlatform {
  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    throw PlatformException(code: 'camera-unavailable');
  }
}

class _FakeSharePlatform implements SharePlatform {
  ShareParams? lastParams;

  @override
  Future<ShareResult> share(ShareParams params) async {
    lastParams = params;
    return ShareResult.unavailable;
  }
}

class _TrackingXFile extends XFile {
  _TrackingXFile(super.path);

  var lengthCalls = 0;
  var openReadCalls = 0;

  @override
  Future<int> length() {
    lengthCalls++;
    return super.length();
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    openReadCalls++;
    return super.openRead(start, end);
  }
}

class _ThrowingXFile extends XFile {
  _ThrowingXFile(super.path);

  var readCalls = 0;

  @override
  Future<int> length() {
    readCalls++;
    return Future.error(Exception('read failed'));
  }

  @override
  Future<Uint8List> readAsBytes() {
    readCalls++;
    return Future.error(Exception('read failed'));
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    readCalls++;
    return Stream.error(Exception('read failed'));
  }
}

void main() {
  late ImagePickerPlatform originalPlatform;

  setUp(() {
    originalPlatform = ImagePickerPlatform.instance;
  });

  tearDown(() {
    ImagePickerPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows the empty state and capture button on launch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FOSScannerApp());

    expect(find.text('FOSScanner'), findsOneWidget);
    expect(find.text('Ready to Scan'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsWidgets);

    // No captured pages yet, so there's nothing to clear or export.
    expect(find.byIcon(Icons.clear_all), findsNothing);
    expect(find.text('Save as PDF'), findsNothing);
  });

  testWidgets(
    'does not offer camera capture when the platform has no camera picker',
    (tester) async {
      ImagePickerPlatform.instance = _FakeImagePickerPlatform(
        cameraSupported: false,
      );

      await tester.pumpWidget(const MaterialApp(home: ScannerHomePage()));

      expect(find.byTooltip('Capture Image'), findsNothing);
      expect(find.textContaining('Import from your gallery'), findsOneWidget);
    },
  );

  testWidgets('reports an Android image-picker recovery failure at startup', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final platform = _FakeImagePickerPlatform(
      lostData: LostDataResponse(
        exception: PlatformException(code: 'lost-data-error'),
      ),
    );
    ImagePickerPlatform.instance = platform;

    await tester.pumpWidget(const MaterialApp(home: ScannerHomePage()));
    await tester.pump();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;

    expect(platform.lostDataCalls, 1);
    expect(
      find.text('Could not recover the interrupted image selection.'),
      findsOneWidget,
    );
  });

  testWidgets('continues Android recovery after one unreadable image', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final directory = Directory.systemTemp.createTempSync(
      'fosscanner-recovery-',
    );
    final unreadableFile = File('${directory.path}/unreadable.jpg')
      ..writeAsBytesSync(const [1, 2, 3]);
    final validFile = File('${directory.path}/valid.png')
      ..writeAsBytesSync(File('assets/icon/icon.png').readAsBytesSync());
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final unreadable = _ThrowingXFile(unreadableFile.path);
    final valid = _TrackingXFile(validFile.path);
    final platform = _FakeImagePickerPlatform(
      lostData: LostDataResponse(files: [unreadable, valid]),
    );
    ImagePickerPlatform.instance = platform;

    await tester.pumpWidget(const MaterialApp(home: ScannerHomePage()));
    for (
      var i = 0;
      i < 20 && find.byType(CornerAdjustScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    debugDefaultTargetPlatformOverride = null;

    expect(platform.lostDataCalls, 1);
    expect(unreadable.readCalls, 1);
    expect(valid.lengthCalls, 1);
    expect(valid.openReadCalls, 1);
    expect(find.byType(CornerAdjustScreen), findsOneWidget);
    expect(unreadableFile.existsSync(), isFalse);
    expect(validFile.existsSync(), isFalse);
  });

  testWidgets(
    'hides camera UI after the Android picker definitively reports no camera',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _CameraUnavailablePlatform();
      expect(platform.supportsImageSource(ImageSource.camera), isTrue);
      ImagePickerPlatform.instance = platform;

      await tester.pumpWidget(const MaterialApp(home: ScannerHomePage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Capture Image'));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;

      expect(find.text('Could not open the camera.'), findsOneWidget);
      expect(find.byTooltip('Capture Image'), findsNothing);
      expect(find.textContaining('Import from your gallery'), findsOneWidget);
    },
  );

  testWidgets('deletes an app-owned camera file when reading it fails', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'fosscanner-camera-cleanup-',
    );
    final file = File('${directory.path}/capture.jpg')
      ..writeAsBytesSync(const [1, 2, 3]);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final image = _ThrowingXFile(file.path);
    final platform = _FakeImagePickerPlatform(image: image);
    ImagePickerPlatform.instance = platform;

    await tester.pumpWidget(const MaterialApp(home: ScannerHomePage()));
    await tester.pump();
    await tester.tap(find.byTooltip('Capture Image'));
    for (var i = 0; i < 20 && file.existsSync(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(platform.imageCalls, 1);
    expect(image.readCalls, 1);
    expect(image.path, file.path);
    expect(file.existsSync(), isFalse);
  });

  testWidgets('shares PDFs with the requested attachment filename', (
    tester,
  ) async {
    final imageBytes = File('assets/icon/icon.png').readAsBytesSync();
    final sharePlatform = _FakeSharePlatform();
    final page = ScannedPage(
      originalBytes: imageBytes,
      corners: const [],
      processedBytes: imageBytes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerHomePage(
          initialPages: [page],
          sharePlus: SharePlus.custom(sharePlatform),
        ),
      ),
    );
    await tester.tap(find.text('Save as PDF (1 pages)'));
    await tester.pumpAndSettle();

    final params = sharePlatform.lastParams;
    expect(params, isNotNull);
    expect(params!.fileNameOverrides, hasLength(1));
    expect(
      params.fileNameOverrides!.single,
      matches(RegExp(r'^FOSScanner_\d+\.pdf$')),
    );
  });

  test('iOS declares every image_picker privacy usage description', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<key>NSCameraUsageDescription</key>'));
    expect(plist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
  });

  test('sandboxed macOS builds can read files selected by the user', () {
    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final entitlements = File(path).readAsStringSync();
      expect(
        entitlements,
        contains('<key>com.apple.security.files.user-selected.read-only</key>'),
        reason: path,
      );
    }
  });

  test('gallery-only Android devices are allowed to install the app', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        'android:name="android.hardware.camera" android:required="false"',
      ),
    );
  });

  test(
    'native platforms do not ship with placeholder application identifiers',
    () {
      for (final path in [
        'ios/Runner.xcodeproj/project.pbxproj',
        'macos/Runner.xcodeproj/project.pbxproj',
        'macos/Runner/Configs/AppInfo.xcconfig',
        'linux/CMakeLists.txt',
        'windows/runner/Runner.rc',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('com.example')),
          reason: path,
        );
      }
    },
  );
}
