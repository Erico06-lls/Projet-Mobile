import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logging/logging.dart';

class ObjectDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final Logger _logger = Logger('ObjectDetector');

  static const int _inputSize = 300;
  static const double _confidenceThreshold = 0.5;

  ObjectDetector([List<String>? labels]) : _labels = labels ?? [];

  /// Chargement du modèle
  Future<void> loadModel(BuildContext context) async {
    try {
      _logger.info('Chargement du modèle MobileNet SSD...');
      _interpreter = await Interpreter.fromAsset('assets/mobilenet.tflite');

      // Debug des informations du modèle
      _debugModelInfo();

      if (!context.mounted) return;

      _labels = (await DefaultAssetBundle.of(context)
              .loadString('assets/labels.txt'))
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.trim())
          .toList();

      _logger.info('Modèle chargé: ${_labels.length} labels');
    } catch (e) {
      _logger.severe('Erreur chargement modèle: $e');
      rethrow;
    }
  }

  /// Debug des informations du modèle
  void _debugModelInfo() {
    if (_interpreter == null) return;
    
    final inputTensor = _interpreter!.getInputTensor(0);
    debugPrint("🎯 FORMAT DU MODÈLE:");
    debugPrint("📊 INPUT: ${inputTensor.shape} ${inputTensor.type}");
    
    for (int i = 0; i < _interpreter!.getOutputTensors().length; i++) {
      final outputTensor = _interpreter!.getOutputTensor(i);
      debugPrint("📊 OUTPUT $i: ${outputTensor.shape} ${outputTensor.type}");
    }
  }

  /// DÉTECTION PRINCIPALE - VERSION CORRIGÉE
  List<Map<String, dynamic>> detectObjects(img.Image image) {
    if (_interpreter == null) {
      _logger.warning('Modèle non chargé');
      return [];
    }

    try {
      _logger.info('Début détection: ${image.width}x${image.height}');

      // 1. Redimensionner simplement
      final resized = img.copyResize(image, width: _inputSize, height: _inputSize);
      
      // 2. Préparer l'input Uint8List
      final input = _imageToUint8List(resized);
      
      // 3. CORRECTION: Préparer les outputs avec la BONNE FORME
      final outputLocations = List.generate(1, (_) => List.generate(10, (_) => List.filled(4, 0.0)));  // [1, 10, 4]
      final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));        // [1, 10]
      final outputScores = List.generate(1, (_) => List.filled(10, 0.0));         // [1, 10]
      final numDetections = List.filled(1, 0.0);                                 // [1]

      // 4. Exécuter l'inférence
      _logger.info('Exécution inference...');
      _interpreter!.runForMultipleInputs(
        [input],
        {
          0: outputLocations,
          1: outputClasses,
          2: outputScores,
          3: numDetections,
        },
      );

      // 🔍 DEBUG: Afficher les résultats bruts
      _debugOutputs(outputLocations, outputClasses, outputScores, numDetections[0]);

      // 5. Traiter les résultats
      final results = _processOutputs(
        outputLocations, 
        outputClasses, 
        outputScores, 
        numDetections[0],
        image.width,
        image.height,
      );

      _logger.info('Détection terminée: ${results.length} objets');
      return results;

    } catch (e) {
      _logger.severe('Erreur détection: $e');
      return [];
    }
  }

  /// Conversion image en Uint8List (valeurs brutes 0-255)
  Uint8List _imageToUint8List(img.Image image) {
    final input = Uint8List(_inputSize * _inputSize * 3);
    int pixelIndex = 0;

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        input[pixelIndex++] = pixel.r.toInt(); // R (0-255)
        input[pixelIndex++] = pixel.g.toInt(); // G (0-255)
        input[pixelIndex++] = pixel.b.toInt(); // B (0-255)
      }
    }

    return input;
  }

  /// Traitement des outputs MobileNet SSD - VERSION CORRIGÉE
  List<Map<String, dynamic>> _processOutputs(
    List<List<List<double>>> locations,
    List<List<double>> classes,
    List<List<double>> scores,
    double numDetections, 
    int originalWidth,
    int originalHeight,
  ) {
    List<Map<String, dynamic>> results = [];
    final num = numDetections.toInt();

    _logger.info('Nombre de détections brutes: $num');

    for (int i = 0; i < num && i < 10; i++) {
      final score = scores[0][i];  // CORRECTION: scores[0][i] au lieu de scores[i]
      
      if (score > _confidenceThreshold) {
        final classId = classes[0][i].toInt();  // CORRECTION: classes[0][i] au lieu de classes[i]
        final label = classId < _labels.length ? _labels[classId] : 'Classe $classId';

        // Extraire les coordonnées de la bounding box - CORRECTION: locations[0][i]
        final box = locations[0][i];  // [ymin, xmin, ymax, xmax]
        final ymin = box[0] * originalHeight;
        final xmin = box[1] * originalWidth;
        final ymax = box[2] * originalHeight;
        final xmax = box[3] * originalWidth;

        // Vérifier que la boîte est valide (coordonnées positives et dans l'image)
        if (xmin >= 0 && ymin >= 0 && xmax > xmin && ymax > ymin) {
          results.add({
            'box': [ymin, xmin, ymax, xmax],
            'label': label,
            'score': score,
            'classId': classId,
          });

          _logger.info('📦 Détection $i: $label (${(score * 100).toStringAsFixed(1)}%)');
          _logger.info('   Boîte: ${xmin.toInt()},${ymin.toInt()} - ${xmax.toInt()},${ymax.toInt()}');
        }
      }
    }

    return results;
  }

  /// 🔍 DEBUG des outputs bruts - VERSION CORRIGÉE
  void _debugOutputs(List<List<List<double>>> locations, List<List<double>> classes, List<List<double>> scores, double numDetections) {
    debugPrint("=== DEBUG OUTPUTS BRUTS ===");
    debugPrint("Num detections: $numDetections");
    
    final num = numDetections.toInt();
    for (int i = 0; i < num && i < 5; i++) {
      debugPrint("Détection $i:");
      debugPrint("  Classe: ${classes[0][i]} (${classes[0][i].toInt()})");
      debugPrint("  Score: ${scores[0][i]}");
      
      final box = locations[0][i];
      debugPrint("  Box: [${box[0]}, ${box[1]}, ${box[2]}, ${box[3]}]");
      
      // Afficher le nom de la classe si disponible
      final classId = classes[0][i].toInt();
      if (classId >= 0 && classId < _labels.length) {
        debugPrint("  Label: ${_labels[classId]}");
      }
    }
    
    // Afficher les statistiques des scores
    final validScores = scores[0].where((score) => score > 0.1).toList();
    debugPrint("Scores > 0.1: ${validScores.length}");
    if (validScores.isNotEmpty) {
      debugPrint("Score max: ${validScores.reduce((a, b) => a > b ? a : b)}");
    }
    debugPrint("============================");
  }

  /// Méthode de débogage
  void debugModel() {
    _debugModelInfo();
  }

  /// Libération des ressources
  void close() {
    _interpreter?.close();
    _logger.info('ObjectDetector fermé');
  }
}