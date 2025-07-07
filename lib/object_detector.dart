import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logging/logging.dart';

class ObjectDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final Logger _logger = Logger('ObjectDetector');
  final int _inputSize = 300;

  ObjectDetector([List<String>? labels]) : _labels = labels ?? [];

  /// Chargement du modèle TFLite et des étiquettes
  Future<void> loadModel(BuildContext context) async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilenet.tflite');

      if (!context.mounted) return;

      _labels = (await DefaultAssetBundle.of(context)
              .loadString('assets/labelmap.txt'))
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      _logger.info('Modèle MobileNet chargé avec ${_labels.length} labels.');
    } catch (e) {
      _logger.severe('Erreur lors du chargement du modèle : $e');
    }
  }

  /// Effectue la détection d’objets
  List<Map<String, dynamic>> detectObjects(img.Image image) {
    if (_interpreter == null) {
      _logger.warning('Le modèle n\'est pas chargé.');
      return [];
    }

    // Redimensionnement de l'image
    final resizedImage = img.copyResize(image, width: _inputSize, height: _inputSize);
    final input = _imageToByteListUnit8(resizedImage);

    // Initialisation des sorties [1, 10, ...]
    final outputBoxes = List.generate(1, (_) => List.generate(10, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(10, 0.0));
    final outputNum = List.filled(1, 0.0);

    final outputs = {
      0: outputBoxes,
      1: outputClasses,
      2: outputScores,
      3: outputNum,
    };

    // Exécution de l’inférence
    _interpreter!.runForMultipleInputs([input], outputs);

    final boxes = outputBoxes[0];
    final classes = outputClasses[0];
    final scores = outputScores[0];
    final numDetections = outputNum[0].toInt();

    List<Map<String, dynamic>> results = [];

    for (int i = 0; i < numDetections && i < 10; i++) {
      final score = scores[i];
      if (score > 0.5) {
        final classIndex = classes[i].toInt();
        final label = classIndex < _labels.length ? _labels[classIndex] : 'unknown';

        results.add({
          'box': boxes[i], // Format : [ymin, xmin, ymax, xmax] (valeurs entre 0 et 1)
          'label': label,
          'score': score,
        });

        _logger.info('Détection: $label (score: ${(score * 100).toStringAsFixed(1)}%)');
      }
    }

    return results;
  }

  /// Prépare l’image au format attendu par le modèle (normalisée entre 0 et 1)
  Uint8List _imageToByteListUnit8(img.Image image) {
    final convertedBytes = Uint8List(_inputSize * _inputSize * 3);
    int pixelIndex = 0;

    for(int y = 0; y < _inputSize; y++) {
      for(int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        convertedBytes[pixelIndex++] = pixel.r.toInt();
        convertedBytes[pixelIndex++] = pixel.g.toInt();
        convertedBytes[pixelIndex++] = pixel.b.toInt();
      }
    }

    return convertedBytes;
  }

  /// Libère les ressources
  void close() {
    _interpreter?.close();
  }
}