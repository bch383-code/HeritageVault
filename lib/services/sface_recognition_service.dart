import 'dart:math' as math;
import 'dart:typed_data';

import 'package:face_detection_tflite/face_detection_tflite.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

class SFaceRecognitionService {
  static const modelAsset =
      'assets/models/face_recognition_sface_2021dec.onnx';
  static const inputSize = 112;

  static const _targetLandmarks = <_Point2>[
    _Point2(38.2946, 51.6963),
    _Point2(73.5318, 51.5014),
    _Point2(56.0252, 71.7366),
    _Point2(41.5493, 92.3655),
    _Point2(70.7299, 92.2041),
  ];

  final OnnxRuntime _runtime = OnnxRuntime();
  OrtSession? _session;

  Future<void> initialize() async {
    _session ??= await _runtime.createSessionFromAsset(modelAsset);
  }

  Future<void> dispose() async {
    final session = _session;
    _session = null;
    if (session != null) await session.close();
  }

  Future<List<double>> embeddingForFaceBytes(
    Uint8List imageBytes,
    Face face,
  ) async {
    await initialize();

    final mesh = face.mesh;
    if (mesh == null || mesh.points.length < 292) {
      throw StateError(
        'SFace requires FaceDetectionMode.standard or full.',
      );
    }

    final sourceImage = img.decodeImage(imageBytes);
    if (sourceImage == null) {
      throw StateError('Could not decode source image.');
    }

    final sourceLandmarks = <_Point2>[
      _midpoint(mesh[33], mesh[133]),
      _midpoint(mesh[362], mesh[263]),
      _Point2(mesh[1].x, mesh[1].y),
      _Point2(mesh[61].x, mesh[61].y),
      _Point2(mesh[291].x, mesh[291].y),
    ];

    final transform = _SimilarityTransform.fit(
      sourceLandmarks,
      _targetLandmarks,
    );

    final aligned = _warpTo112(sourceImage, transform);
    final input = _toRgbNchw(aligned);

    final session = _session!;
    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;

    final inputValue = await OrtValue.fromList(
      input,
      const [1, 3, inputSize, inputSize],
    );

    try {
      final outputs = await session.run({inputName: inputValue});
      final outputValue = outputs[outputName];
      if (outputValue == null) {
        throw StateError('SFace returned no output.');
      }

      try {
        final raw = await outputValue.asFlattenedList();
        return _l2Normalize(
          raw.map((value) => (value as num).toDouble()).toList(),
        );
      } finally {
        for (final value in outputs.values) {
          await value.dispose();
        }
      }
    } finally {
      await inputValue.dispose();
    }
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || a.length != b.length) return -1;
    var dot = 0.0, aa = 0.0, bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    if (aa <= 0 || bb <= 0) return -1;
    return dot / (math.sqrt(aa) * math.sqrt(bb));
  }

  static _Point2 _midpoint(Point a, Point b) =>
      _Point2((a.x + b.x) / 2, (a.y + b.y) / 2);

  static img.Image _warpTo112(
    img.Image source,
    _SimilarityTransform transform,
  ) {
    final output = img.Image(width: inputSize, height: inputSize);
    final inv = transform.inverse();

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final src = inv.apply(_Point2(x + 0.5, y + 0.5));
        final rgb = _bilinear(source, src.x - 0.5, src.y - 0.5);
        output.setPixelRgb(x, y, rgb.$1, rgb.$2, rgb.$3);
      }
    }
    return output;
  }

  static (int, int, int) _bilinear(img.Image image, double x, double y) {
    if (x < 0 || y < 0 || x > image.width - 1 || y > image.height - 1) {
      return (0, 0, 0);
    }

    final x0 = x.floor().clamp(0, image.width - 1);
    final y0 = y.floor().clamp(0, image.height - 1);
    final x1 = (x0 + 1).clamp(0, image.width - 1);
    final y1 = (y0 + 1).clamp(0, image.height - 1);
    final fx = x - x0;
    final fy = y - y0;

    final p00 = image.getPixel(x0, y0);
    final p10 = image.getPixel(x1, y0);
    final p01 = image.getPixel(x0, y1);
    final p11 = image.getPixel(x1, y1);

    int channel(num c00, num c10, num c01, num c11) {
      final top = c00 * (1 - fx) + c10 * fx;
      final bottom = c01 * (1 - fx) + c11 * fx;
      return (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
    }

    return (
      channel(p00.r, p10.r, p01.r, p11.r),
      channel(p00.g, p10.g, p01.g, p11.g),
      channel(p00.b, p10.b, p01.b, p11.b),
    );
  }

  static List<double> _toRgbNchw(img.Image image) {
    final plane = inputSize * inputSize;
    final data = List<double>.filled(plane * 3, 0);
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = image.getPixel(x, y);
        final i = y * inputSize + x;
        data[i] = p.r.toDouble();
        data[plane + i] = p.g.toDouble();
        data[plane * 2 + i] = p.b.toDouble();
      }
    }
    return data;
  }

  static List<double> _l2Normalize(List<double> values) {
    var ss = 0.0;
    for (final value in values) {
      ss += value * value;
    }
    if (ss <= 0) return values;
    final norm = math.sqrt(ss);
    return values.map((value) => value / norm).toList();
  }
}

class _Point2 {
  final double x;
  final double y;
  const _Point2(this.x, this.y);
}

class _SimilarityTransform {
  final double a;
  final double b;
  final double tx;
  final double ty;

  const _SimilarityTransform({
    required this.a,
    required this.b,
    required this.tx,
    required this.ty,
  });

  static _SimilarityTransform fit(
    List<_Point2> source,
    List<_Point2> destination,
  ) {
    var sxMean = 0.0, syMean = 0.0, dxMean = 0.0, dyMean = 0.0;
    for (var i = 0; i < source.length; i++) {
      sxMean += source[i].x;
      syMean += source[i].y;
      dxMean += destination[i].x;
      dyMean += destination[i].y;
    }
    final n = source.length.toDouble();
    sxMean /= n;
    syMean /= n;
    dxMean /= n;
    dyMean /= n;

    var real = 0.0, imag = 0.0, denom = 0.0;
    for (var i = 0; i < source.length; i++) {
      final sx = source[i].x - sxMean;
      final sy = source[i].y - syMean;
      final dx = destination[i].x - dxMean;
      final dy = destination[i].y - dyMean;
      real += dx * sx + dy * sy;
      imag += dy * sx - dx * sy;
      denom += sx * sx + sy * sy;
    }

    if (denom <= 1e-9) {
      throw StateError('Degenerate face landmarks.');
    }

    final a = real / denom;
    final b = imag / denom;
    return _SimilarityTransform(
      a: a,
      b: b,
      tx: dxMean - (a * sxMean - b * syMean),
      ty: dyMean - (b * sxMean + a * syMean),
    );
  }

  _Point2 apply(_Point2 p) =>
      _Point2(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty);

  _SimilarityTransform inverse() {
    final d = a * a + b * b;
    if (d <= 1e-12) throw StateError('Transform is not invertible.');
    final ia = a / d;
    final ib = -b / d;
    return _SimilarityTransform(
      a: ia,
      b: ib,
      tx: -(ia * tx - ib * ty),
      ty: -(ib * tx + ia * ty),
    );
  }
}
