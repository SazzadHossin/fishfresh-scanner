import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'; // NEW: ML Kit
import '../services/tflite_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _image;
  ClassificationResult? _result;
  String _statusMessage = 'Ready to scan.';

  final ImagePicker _picker = ImagePicker();
  bool _isAnalyzing = false;

  // Tracker for invalid/random images
  bool _isInvalidImage = false;

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = null;
        _isInvalidImage = false; // Reset invalid state
        _statusMessage = 'Image loaded. Ready to analyze.';
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage = "Verifying image contents...";
    });

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      // ==========================================
      // STEP 1: GOOGLE ML KIT PRE-CHECK
      // Strict Whitelist Logic
      // ==========================================
      final inputImage = InputImage.fromFile(_image!);
      final imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
      final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);

      bool isWhitelisted = false;

      for (ImageLabel label in labels) {
        final text = label.label.toLowerCase();

        // Whitelist ONLY: Only these specific keywords are allowed.
        // We include 'carp' (for Rui) and 'seafood'/'animal' as safety fallbacks.
        if (text.contains('fish') || text.contains('tilapia') || text.contains('rui') ||
            text.contains('carp') || text.contains('seafood') || text.contains('animal')) {
          isWhitelisted = true;
          break; // Stop checking, we found a valid tag!
        }
      }

      imageLabeler.close(); // Clean up memory

      // STRICT CHECK: If it is NOT in the whitelist, block it immediately.
      if (!isWhitelisted) {
        setState(() {
          _isInvalidImage = true;
          _result = null;
          _statusMessage = "Unrecognized Image.";
          _isAnalyzing = false;
        });
        return; // Stop right here, don't run the TFLite model!
      }

      // ==========================================
      // STEP 2: TFLITE FRESHNESS CLASSIFICATION
      // ==========================================
      setState(() {
        _statusMessage = "Analyzing freshness...";
      });

      final result = await TFLiteService().classifyImage(_image!);

      // We still keep the confidence threshold as a secondary backup
      double confidenceThreshold = 0.85;

      setState(() {
        if (result.confidence < confidenceThreshold) {
          _isInvalidImage = true;
          _result = null;
          _statusMessage = "Unrecognized Image.";
        } else {
          _isInvalidImage = false;
          _result = result;
          _statusMessage = "Analysis Complete";
        }
      });

    } catch (e) {
      setState(() {
        _statusMessage = "Error during analysis.";
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  // --------------------------------------------------------
  // UI WIDGETS
  // --------------------------------------------------------

  Widget _buildGuidanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.teal.shade800),
              const SizedBox(width: 10),
              Text(
                "Tips for Best Accuracy",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade800
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTipRow(Icons.camera_alt, "Take or select a picture of the FISH EYE only."),
          const SizedBox(height: 10),
          _buildTipRow(Icons.zoom_in, "Zoom in as much as possible on the eye."),
          const SizedBox(height: 10),
          _buildTipRow(Icons.set_meal, "Currently works best on Rui and Tilapia."),
        ],
      ),
    );
  }

  Widget _buildTipRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.teal.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.teal.shade900, fontSize: 15, height: 1.4),
          ),
        ),
      ],
    );
  }

  // Warning Card for non-fish images
  Widget _buildInvalidImageCard() {
    return Card(
      elevation: 4,
      shadowColor: Colors.orange.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.orange.shade50,
          border: Border.all(color: Colors.orange.shade300, width: 2),
        ),
        child: Column(
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.orange.shade800, size: 48),
            const SizedBox(height: 16),
            Text(
              "Image Not Recognized",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Please give or select a clear image of a valid fish (Rui or Tilapia) eye.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.orange.shade900, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    if (_result == null) return const SizedBox.shrink();

    bool isFresh = _result!.label.toLowerCase().contains('fresh');
    Color statusColor = isFresh ? Colors.green.shade600 : Colors.red.shade600;
    IconData statusIcon = isFresh ? Icons.check_circle_outline : Icons.warning_amber_rounded;

    return Card(
      elevation: 4,
      shadowColor: statusColor.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.white, statusColor.withOpacity(0.05)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, color: statusColor, size: 36),
                const SizedBox(width: 12),
                Text(
                  _result!.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "AI Confidence",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _result!.confidence,
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  "${(_result!.confidence * 100).toStringAsFixed(1)}%",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('FishFresh Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Guidance or Image Display Area
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _image == null
                      ? _buildGuidanceCard()
                      : Container(
                    width: double.infinity,
                    height: 320,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(_image!, fit: BoxFit.cover),
                    ),
                  ),

                  if (_image != null)
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: "btn_camera",
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.teal,
                            onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                            child: const Icon(Icons.camera_alt),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton.small(
                            heroTag: "btn_gallery",
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.teal,
                            onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                            child: const Icon(Icons.photo_library),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              if (_image == null) ...[
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                        onPressed: () => _pickImage(ImageSource.camera),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.teal.shade300, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                        onPressed: () => _pickImage(ImageSource.gallery),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.teal.shade300, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 32),

              // 2. Status Message or Analysis Button
              if (_image != null && _result == null && !_isInvalidImage)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    icon: _isAnalyzing
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Icon(Icons.analytics_outlined, size: 28),
                    label: Text(
                      _isAnalyzing ? 'Analyzing...' : 'Analyze Freshness',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    onPressed: _isAnalyzing ? null : _analyzeImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

              // 3. Invalid Image Warning Card
              if (_isInvalidImage) ...[
                _buildInvalidImageCard(),
                const SizedBox(height: 24),
              ],

              // 4. Results Card
              if (_result != null) ...[
                _buildResultCard(),
                const SizedBox(height: 24),
              ],

              // Re-scan button for both Invalid and Valid states
              if (_result != null || _isInvalidImage)
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Scan Another Image", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: Colors.teal.shade700),
                  onPressed: () {
                    setState(() {
                      _image = null;
                      _result = null;
                      _isInvalidImage = false;
                      _statusMessage = 'Ready to scan.';
                    });
                  },
                ),

              if (_result == null && !_isAnalyzing && !_isInvalidImage)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}