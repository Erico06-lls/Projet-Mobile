import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import './object_detector.dart';
import './camera_screen.dart';

class UploadImageScreen extends StatefulWidget {
  const UploadImageScreen({super.key});

  @override
  State<UploadImageScreen> createState() => _UploadImageScreenState();
}

class _UploadImageScreenState extends State<UploadImageScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  List<Map<String, dynamic>> _detections = [];
  final ObjectDetector _detector = ObjectDetector();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    await _detector.loadModel(context);
    if (!mounted) return;
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
      _detections.clear();
    });

    final bytes = await _selectedImage!.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;

    final results = _detector.detectObjects(decoded);
    if (!mounted) return;

    setState(() {
      _detections = results;
    });
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
        title: const Text('Analyse d’image - MobileNet SSD'),
      ),
      body: Column(
        children: [
          if (_selectedImage != null)
            Expanded(
              child: Stack(
                children: [
                  Image.file(_selectedImage!),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DetectionPainter(_detections),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo),
            label: const Text('Choisir une image'),
          ),
          const SizedBox(height: 10),
          if (_detections.isNotEmpty)
            Text('Objets détectés : ${_detections.length}'),
        ],
      ),
    );
  }
}
