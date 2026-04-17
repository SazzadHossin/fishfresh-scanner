import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class ClassificationResult {
  final String label;
  final double confidence;
  ClassificationResult(this.label, this.confidence);
}

class TFLiteService {
  // Singleton pattern so the model is only loaded once in memory
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  final List<String> _labels = ['Fresh Rui', 'Fresh Tilapia', 'Stale Rui', 'Stale Tilapia'];

  bool get isInitialized => _interpreter != null;

  // Initialize model (Called during the Splash Screen)
  Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/fish_eye_efficientnetb0_best.tflite', options: options);
      print("AI Model Loaded Successfully.");
    } catch (e) {
      print("Error loading model: $e");
      throw Exception("Failed to load AI Model.");
    }
  }

  // Process image and run inference
  Future<ClassificationResult> classifyImage(File imageFile) async {
    if (_interpreter == null) throw Exception("Model not initialized.");

    final imageBytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception("Could not decode image.");

    img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

    var input = List.generate(1, (i) =>
        List.generate(224, (j) =>
            List.generate(224, (k) => List.filled(3, 0.0))
        )
    );

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        input[0][y][x][0] = pixel.r.toDouble();
        input[0][y][x][1] = pixel.g.toDouble();
        input[0][y][x][2] = pixel.b.toDouble();
      }
    }

    var output = List.generate(1, (i) => List.filled(4, 0.0));
    _interpreter!.run(input, output);

    List<double> probabilities = output[0];
    int maxIndex = 0;
    double maxProb = probabilities[0];

    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxIndex = i;
      }
    }

    return ClassificationResult(_labels[maxIndex], maxProb);
  }
}