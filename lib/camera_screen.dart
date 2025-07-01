import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:projet_mobile/object_detector.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Timer? _timer;
  bool _isDetecting = false;
  CameraImage? _latestImage;

  final Logger _logger = Logger('CameraScreen');
  final ObjectDetector _detector = ObjectDetector();
  List<Map<String, dynamic>> _detections = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (!mounted) return;

    _controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    if (!mounted) return;

    await _detector.loadModel(context); // chargement modèle
    if (!mounted) return;

    await _controller!.startImageStream(_onNewCameraImage);

    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      if (_isDetecting || _latestImage == null) return;
      _isDetecting = true;

      try {
        final converted = await _convertCameraImage(_latestImage!);
        final results = _detector.detectObjects(converted);
        if (!mounted) return;
        setState(() {
          _detections = results;
        });
      } catch (e) {
        _logger.severe('Erreur de détection : $e');
      } finally {
        _isDetecting = false;
      }
    });

    if (!mounted) return;
    setState(() {});
  }

  void _onNewCameraImage(CameraImage image) {
    _latestImage = image;
  }

  Future<img.Image> _convertCameraImage(CameraImage cameraImage) async {
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final imgData = img.Image(width: width, height: height);

    final planeY = cameraImage.planes[0].bytes;
    final planeU = cameraImage.planes[1].bytes;
    final planeV = cameraImage.planes[2].bytes;

    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final yIndex = y * width + x;

        final Y = planeY[yIndex];
        final U = planeU[uvIndex];
        final V = planeV[uvIndex];

        final R = (Y + 1.403 * (V - 128)).clamp(0, 255).toInt();
        final G = (Y - 0.344 * (U - 128) - 0.714 * (V - 128)).clamp(0, 255).toInt();
        final B = (Y + 1.770 * (U - 128)).clamp(0, 255).toInt();

        imgData.setPixel(x, y, img.ColorRgb8(R, G, B));
      }
    }

    return imgData;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détection en temps réel')),
      body: _controller != null && _controller!.value.isInitialized
          ? Stack(
              children: [
                CameraPreview(_controller!),
                _buildDetectionOverlay(),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildDetectionOverlay() {
    return Positioned.fill(
      child: CustomPaint(
        painter: DetectionPainter(_detections),
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;

  DetectionPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    for (var detection in detections) {
      final box = detection['box'];
      final label = detection['label'];
      final score = detection['score'];

      final rect = Rect.fromLTWH(
        box[1] * size.width,
        box[0] * size.height,
        (box[3] - box[1]) * size.width,
        (box[2] - box[0]) * size.height,
      );

      canvas.drawRect(rect, paint);

      final textSpan = TextSpan(
        text: '$label ${(score * 100).toStringAsFixed(1)}%',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      );
      textPainter.text = textSpan;
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
