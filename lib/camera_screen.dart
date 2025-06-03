import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'results_screen.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras; // Add cameras parameter

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
    ); // Use widget.cameras
    controller
        ?.initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
        })
        .catchError((e) {
          print('Error initializing camera: $e');
        });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndProcessImage() async {
    if (isProcessing || controller == null || !controller!.value.isInitialized)
      return;

    setState(() => isProcessing = true);

    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final XFile imageFile = await controller!.takePicture();
      await imageFile.saveTo(path);

      final inputImage = InputImage.fromFilePath(path);
      final barcodeScanner = BarcodeScanner();
      final List<Barcode> barcodes = await barcodeScanner.processImage(
        inputImage,
      );
      List<String> detectedItems = [];

      for (Barcode barcode in barcodes) {
        detectedItems.add(barcode.displayValue ?? 'Unknown');
      }

      if (barcodes.isEmpty) {
        final textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );
        if (recognizedText.text.isNotEmpty) {
          detectedItems.add(recognizedText.text);
        }
        await textRecognizer.close();
      }

      await barcodeScanner.close();

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultsScreen(detectedItems: detectedItems),
          ),
        );
      }
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Products')),
      body: Stack(
        children: [
          CameraPreview(controller!),
          if (isProcessing) const Center(child: CircularProgressIndicator()),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: FloatingActionButton(
                onPressed: _captureAndProcessImage,
                child: const Icon(Icons.camera),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
