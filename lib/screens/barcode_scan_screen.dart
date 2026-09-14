import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/transient_message.dart';

/// A live QR/barcode scanning mode, separate from the document-scan flow:
/// point the camera at a code and get the decoded value with quick actions
/// (copy, open link), rather than treating the code as a document page.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  String? _lastResult;
  String? _cameraError;
  int _cameraAttempt = 0;

  void _handleCameraCreated(Exception? error, int attempt) {
    if (!mounted || attempt != _cameraAttempt || error == null) return;
    final message = switch (error) {
      CameraException(code: 'CameraAccessDenied') ||
      CameraException(
        code: 'CameraAccessDeniedWithoutPrompt',
      ) => 'Allow camera access in your device settings, then retry.',
      CameraException(code: 'CameraAccessRestricted') =>
        'Camera access is restricted on this device. Check your device settings.',
      _ => 'Could not start the camera. Check camera access and retry.',
    };
    setState(() => _cameraError = message);
  }

  void _retryCamera() {
    setState(() {
      _cameraError = null;
      _cameraAttempt++;
    });
  }

  Widget _buildCameraError(String message) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'Camera unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(message, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retryCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );

  Uri? get _resultUri {
    final result = _lastResult;
    if (result == null) return null;
    final uri = Uri.tryParse(result);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return uri;
  }

  void _handleScan(Code code) {
    if (!mounted) return;
    final text = code.text;
    if (!code.isValid || text == null || text.isEmpty) return;
    if (text == _lastResult) return;
    setState(() => _lastResult = text);
  }

  void _dismissResult() {
    setState(() => _lastResult = null);
  }

  Future<void> _copyResult() async {
    final result = _lastResult;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _openResult() async {
    final uri = _resultUri;
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        showTransientMessage(context, 'Could not open the link.');
      }
    } catch (_) {
      if (mounted) showTransientMessage(context, 'Could not open the link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;
    final cameraError = _cameraError;
    final cameraAttempt = _cameraAttempt;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR / Barcode')),
      body: Stack(
        children: [
          // cropPercent must stay 0 here: ReaderWidget's crop-indicator square
          // only lines up with the region it actually decodes when the widget
          // is truly full-screen. This screen has an AppBar above it (so the
          // preview is letterboxed), which is exactly the case the flutter_zxing
          // maintainers flag as producing a crop guide that visually looks
          // centered on the code while the real decode window is offset
          // elsewhere — the code never gets read even though it's framed
          // correctly on screen. See khoren93/flutter_zxing#196.
          //
          // showScannerOverlay is also off: at cropPercent 0, flutter_zxing's
          // built-in overlay switches to a "tap the highlighted code" mode
          // instead of a plain guide, which reads as scanning requiring a
          // tap when it doesn't — onScan already fires as soon as a frame
          // decodes. The plain square below is a purely cosmetic aiming hint
          // with no effect on what actually gets decoded (the whole frame
          // always does), so it can't drift out of sync the way the built-in
          // one did.
          if (cameraError == null)
            ReaderWidget(
              key: ValueKey(cameraAttempt),
              onControllerCreated: (_, error) =>
                  _handleCameraCreated(error, cameraAttempt),
              onScan: _handleScan,
              showGallery: true,
              cropPercent: 0,
              showScannerOverlay: false,
              // 1D formats (EAN/UPC/Code128, common on physical product
              // packaging) carry far less redundancy than a QR code and are
              // much more sensitive to a slight skew/angle, so they need the
              // more exhaustive per-frame decode attempt this enables.
              tryHarder: true,
            ),
          if (result == null && cameraError == null)
            IgnorePointer(
              child: Center(
                child: Container(
                  width: MediaQuery.sizeOf(context).shortestSide * 0.6,
                  height: MediaQuery.sizeOf(context).shortestSide * 0.6,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          if (result != null && cameraError == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                result,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Dismiss and keep scanning',
                              onPressed: _dismissResult,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_resultUri != null) ...[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _openResult,
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _copyResult,
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (cameraError != null)
            Positioned.fill(child: _buildCameraError(cameraError)),
        ],
      ),
    );
  }
}
