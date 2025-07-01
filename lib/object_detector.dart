import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logging/logging.dart';

class ObjectDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final Logger _logger = Logger('ObjectDetector');
  final int _inputSize = 300; // taille standard pour SSD MobileNet

  ObjectDetector([List<String>? labels]) : _labels = labels ?? [];

  /// Chargement du modèle et des labels
  Future<void> loadModel(BuildContext context) async {
    try {
      _interpreter = await Interpreter.fromAsset('mobilenet.tflite');

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

  /// Détection d'objets dans une image
  List<Map<String, dynamic>> detectObjects(img.Image image) {
    if (_interpreter == null) {
      _logger.warning('Le modèle n\'est pas chargé.');
      return [];
    }

    // Redimensionnement de l'image
    var resizedImage = img.copyResize(image, width: _inputSize, height: _inputSize);
    var input = _imageToByteListFloat32(resizedImage);

    // Initialisation des sorties
    var outputBoxes = List.generate(10, (_) => List.filled(4, 0.0)); // [ymin, xmin, ymax, xmax]
    var outputClasses = List.filled(10, 0.0); // classes détectées
    var outputScores = List.filled(10, 0.0); // scores
    var outputNum = List.filled(1, 0.0); // nombre de détections

    final output = {
    0: outputBoxes,
    1: outputClasses,
    2: outputScores,
    3: outputNum,
  };

  _interpreter!.runForMultipleInputs([input], output);

    // Traitement des résultats
    List<Map<String, dynamic>> results = [];
    int numDetections = outputNum[0].toInt();

    for (int i = 0; i < numDetections && i < 10; i++) {
      double score = outputScores[i];
      if (score > 0.5) {
        int classIndex = outputClasses[i].toInt();
        String label = classIndex < _labels.length ? _labels[classIndex] : 'unknown';

        results.add({
          'box': outputBoxes[i],
          'label': label,
          'score': score,
        });

        _logger.info('Détection: $label (score: ${score.toStringAsFixed(2)})');
      }
    }

    return results;
  }

  /// Préparation de l’image pour le modèle
  List<List<List<List<double>>>> _imageToByteListFloat32(img.Image image) {
    var convertedBytes = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (_) => List.generate(_inputSize, (_) => List.filled(3, 0.0)),
      ),
    );

    for (var i = 0; i < _inputSize; i++) {
      for (var j = 0; j < _inputSize; j++) {
        var pixel = image.getPixel(j, i);
        convertedBytes[0][i][j][0] = (pixel.r - 127.5) / 127.5;
        convertedBytes[0][i][j][1] = (pixel.g - 127.5) / 127.5;
        convertedBytes[0][i][j][2] = (pixel.b - 127.5) / 127.5;
      }
    }

    return convertedBytes;
  }

  /// Libération de l’interpréteur
  void close() {
    _interpreter?.close();
  }
}