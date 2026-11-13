import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:citysim/rendering/parcel_world_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// The raw-image path ([decodeRgbaImage]) must only ever receive
/// binary alpha — 0 or 255.
///
/// The engines disagree on what partial alpha means for
/// [ui.ImageDescriptor.raw] with [ui.PixelFormat.rgba8888]: Skia
/// (flutter_tester, iOS, Android, desktop) reads the bytes as
/// PREMULTIPLIED, while CanvasKit (the web) reads them as STRAIGHT.
/// Observed directly — the bytes (128, 0, 0, 128) drawn over opaque
/// blue:
///
/// - Skia:      (128, 0, 127) — premultiplied compositing
/// - CanvasKit: (64, 0, 127)  — straight compositing
///
/// A gradient encoded in alpha therefore renders squared on the web
/// (each partial pixel's alpha is applied twice). Binary alpha means
/// the same thing in both conventions, so composed overlays — like
/// the shore band — must bake any gradient into their colour
/// channels (see [composeShoreBandPixels]). This test pins the
/// guarantee the fix relies on: binary-alpha pixels composite
/// exactly, on whichever engine runs the suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('binary-alpha raw overlays composite exactly', () async {
    // Left: opaque red. Right: fully transparent.
    final bytes = Uint8List.fromList([
      255, 0, 0, 255, //
      0, 0, 0, 0,
    ]);
    final image = await decodeRgbaImage(bytes, 2, 1);
    expect(image, isNotNull);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 1),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    );
    canvas.drawImageRect(
      image!,
      const ui.Rect.fromLTWH(0, 0, 2, 1),
      const ui.Rect.fromLTWH(0, 0, 2, 1),
      ui.Paint(),
    );
    final rasterized = await recorder.endRecording().toImage(2, 1);
    final out = await rasterized.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final pixels = out!.buffer.asUint8List(
      out.offsetInBytes,
      out.lengthInBytes,
    );

    expect(pixels.sublist(0, 4), [255, 0, 0, 255], reason: 'opaque wins');
    expect(pixels.sublist(4, 8), [0, 0, 255, 255], reason: 'transparent loses');
  });
}
