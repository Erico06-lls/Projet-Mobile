import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'object_detector.dart';

class UploadImageScreen extends StatefulWidget{
  const UploadImageScreen({super.key});

  @override
  State<UploadImageScreen> createState() => _UplaodImageScreenState();
}

class _UplaodImageScreenState extends State<UploadImageScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  List<Map<String, dynamic>> _detections = [];
  final ObjectDetector _detector = ObjectDetector();
  bool _isProcessing = false;
  String _status = 'Pret';

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    setState(() {
      _status = 'Chargement du modele...';
      _isProcessing = true;
    });

    try {
      await _detector.loadModel(context);
      setState(() {
        _status = 'Modele charge';
      });
    } catch (e) {
      setState(() {
        _status = 'Erreur: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
      _detections.clear();
      _isProcessing = true;
      _status = 'Analyse en cours...';
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        setState(() {
          _status = 'Erreur: Image non valide';
        });
        return;
      }

      final results = _detector.detectObjects(decoded);

      if (!mounted) return;

      setState(() {
        _detections = results;
        _status = '${results.length} objet(s) detecte(s)';
      });
    } catch (e) {
      setState(() {
        _status = 'Erreur: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection d\' objets MobileNet SSD'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          //Section status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _getStatusColor(),
            child: Text(
              _status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Section image avec detections
          if (_selectedImage != null)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image de fond
                  Container(
                    color: Colors.grey[100],
                    child: Center(
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // Overlay de detection
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DetectionPainter(_detections),
                    ),
                  ),

                  // Indicateur de chargement
                  if (_isProcessing)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Analyse en cours...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            // Placeholder
            Expanded(
              child: Container(
                color: Colors.grey[50],
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Aucune image selectionnee',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Section controlle en bas
          _buildControlSection(),
        ],
      ),
    );
  }
  Color _getStatusColor() {
    if (_status.contains('Erreur')) return Colors.red;
    if (_status.contains('✓') || _status.contains('detecte')) return Colors.green;
    if(_status.contains('en cours')) return Colors.orange;
    return Colors.blue;
  }

  Widget _buildControlSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: 
          [BoxShadow(
            color: const Color(0x1A000000),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Boutton principal
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _pickImage,
            icon: const Icon(Icons.photo_library),
            label: const Text(
              'CHOISIR UNE IMAGE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[900],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Resultats
          if (_detections.isNotEmpty) _buildResultsSection(),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '${_detections.length} OBJET(S) DETECTE(S)',
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _detections.map((detection) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${detection['label']} (${(detection['score'] * 100).toInt()}%)',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;

  DetectionPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final textSpan = TextSpan(style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    for (var detection in detections) {
      final box = detection['box'];
      final score = detection['score'];
      final label = detection['label'];

      // Couleur basee sur la score
      final color = Color.lerp(Colors.red, Colors.green, score)!;

      // Dessiner la bounding box
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      
      final rect = Rect.fromLTRB(
        box[1],
        box[0],
        box[3],
        box[2],
      );

      canvas.drawRect(rect, paint);

      // Dessiner le fond du label
      final text = '$label (${(score * 100).toStringAsFixed(0)}%)';
      textPainter.text = TextSpan(
        text: text,
        style: textStyle,
      );

      textPainter.layout();

      final textBackground = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      final backgroundPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

        canvas.drawRect(textBackground, backgroundPaint);

        // Dessiner le texte
        textPainter.paint(
          canvas,
          Offset(rect.left + 4, rect.top - textPainter.height - 2)
        );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Redessiner toujours quand les détections changent
  }
}

