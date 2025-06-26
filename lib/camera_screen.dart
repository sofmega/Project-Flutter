import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  late TextRecognizer _textRecognizer;
  bool _canProcess = true;
  bool _isBusy = false;
  bool _isAnalyzing = false;

  RecognizedText? _recognizedText;
  Size? _imageSize;

  Map<String, dynamic>? _lastScannedProduct;

  final String _geminiApiKey = "mettre_clé_api_gemini_ici";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeDetector();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showWelcomeDialog();
      }
    });
  }

  @override
  void dispose() {
    _canProcess = false;
    _textRecognizer.close();
    _controller?.dispose();
    super.dispose();
  }

  void _showWelcomeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 10),
            // --- CORRECTION APPLIQUÉE ICI ---
            // On enveloppe le texte dans un widget Flexible pour éviter le débordement
            Flexible(child: Text("Comment ça marche ?")),
          ],
        ),
        content: const SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text("1. Pointez la caméra vers l'étiquette d'un produit."),
              SizedBox(height: 10),
              Text(
                  "2. Appuyez sur 'Analyser Produit 1' pour l'identifier. Vous pourrez corriger le texte si besoin."),
              SizedBox(height: 10),
              Text(
                  "3. Ensuite, scannez un deuxième produit et appuyez sur 'Analyser et Comparer' pour vérifier les dangers du mélange."),
              SizedBox(height: 10),
              Text(
                  "Pour recommencer, cliquez sur la croix (x) sur le produit en mémoire."),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Compris !'),
          ),
        ],
      ),
    );
  }

  void _initializeCamera() {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(widget.cameras[0], ResolutionPreset.high,
        enableAudio: false);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      // On met à jour l'état seulement après l'initialisation complète
      setState(() {});
      _startLiveFeed();
    }).catchError((e) {
      if (kDebugMode) {
        print('Erreur lors de l\'initialisation de la caméra: $e');
      }
    });
  }

  void _initializeDetector() {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  void _startLiveFeed() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controller!.startImageStream((image) {
      if (!_canProcess || _isBusy) return;
      _isBusy = true;
      processImage(image);
    });
  }

  Future<void> processImage(CameraImage cameraImage) async {
    final inputImage = _inputImageFromCameraImage(cameraImage);
    if (inputImage == null) {
      _isBusy = false;
      return;
    }
    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (mounted) {
        setState(() {
          _recognizedText = recognizedText;
          _imageSize = Size(
            _controller!.description.sensorOrientation == 90 ||
                    _controller!.description.sensorOrientation == 270
                ? cameraImage.height.toDouble()
                : cameraImage.width.toDouble(),
            _controller!.description.sensorOrientation == 90 ||
                    _controller!.description.sensorOrientation == 270
                ? cameraImage.width.toDouble()
                : cameraImage.height.toDouble(),
          );
        });
      }
    } catch (e) {
      debugPrint('Erreur lors de la reconnaissance de texte: $e');
    }
    _isBusy = false;
  }

  String? _findMostRelevantText(RecognizedText? recognizedText) {
    if (recognizedText == null || recognizedText.blocks.isEmpty) {
      return null;
    }

    TextBlock? largestBlock;
    double maxHeight = 0.0;

    for (final block in recognizedText.blocks) {
      if (block.boundingBox.height > maxHeight) {
        maxHeight = block.boundingBox.height;
        largestBlock = block;
      }
    }

    return largestBlock?.text.replaceAll('\n', ' ');
  }

  Future<void> _analyzeCapturedText() async {
    if (_geminiApiKey == "VOTRE_CLÉ_API_GEMINI_ICI") {
      _showResultDialog("Clé API Manquante",
          "Veuillez remplacer 'VOTRE_CLÉ_API_GEMINI_ICI' dans le code par votre propre clé API Gemini.");
      return;
    }

    final String? relevantText = _findMostRelevantText(_recognizedText);

    if (relevantText == null || relevantText.trim().isEmpty) {
      _showResultDialog("Aucun texte pertinent détecté",
          "Impossible d'isoler un nom de produit. Veuillez essayer de mieux cadrer l'étiquette.");
      return;
    }

    _showCorrectionDialog(relevantText);
  }

  void _showCorrectionDialog(String detectedText) {
    final textController = TextEditingController(text: detectedText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Corriger le texte détecté"),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            labelText: "Texte à analyser",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performAnalysis(textController.text);
            },
            child: const Text("Analyser"),
          )
        ],
      ),
    );
  }

  Future<void> _performAnalysis(String textToAnalyze) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      final newProductInfo = await _extractProductInfo(textToAnalyze);

      if (_lastScannedProduct == null) {
        final description = await _getProductDescription(newProductInfo);
        _showResultDialog("Analyse du Produit", description,
            scannedText: textToAnalyze);
        setState(() {
          _lastScannedProduct = newProductInfo;
        });
      } else {
        final mixtureAnalysis =
            await _analyzeMixture(_lastScannedProduct!, newProductInfo);
        _showResultDialog("Analyse du Mélange", mixtureAnalysis,
            scannedText: textToAnalyze);
        setState(() {
          _lastScannedProduct = null;
        });
      }
    } catch (e) {
      _showResultDialog("Analyse échouée",
          "Une erreur est survenue lors de l'identification du produit:\n\n$e");
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _extractProductInfo(String text) async {
    final prompt =
        "Extrait le nom principal du produit et ses composants chimiques clés du texte suivant. Réponds UNIQUEMENT avec un objet JSON valide contenant les clés \"nom\" et \"composants\". Si tu ne trouves pas de composants, retourne un tableau vide. Texte: \"$text\"";

    final generationConfig = {
      "response_mime_type": "application/json",
      "response_schema": {
        "type": "OBJECT",
        "properties": {
          "nom": {"type": "STRING"},
          "composants": {
            "type": "ARRAY",
            "items": {"type": "STRING"}
          }
        },
        "required": ["nom", "composants"]
      }
    };

    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': generationConfig,
        }),
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final jsonString =
            decodedResponse['candidates'][0]['content']['parts'][0]['text'];
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } else {
        throw Exception(
            "Erreur de l'API Gemini : ${response.statusCode}\n${response.body}");
      }
    } catch (e) {
      throw Exception(
          "Erreur lors de l'extraction des informations produit : $e");
    }
  }

  Future<String> _getProductDescription(
      Map<String, dynamic> productInfo) async {
    final prompt =
        "Le produit identifié est un(e) \"${productInfo['nom']}\". Décris ce type de produit en général, son usage principal, et les composants chimiques habituels qu'il contient. Liste ensuite les dangers potentiels généraux associés à ce type de produit. Réponds en français.";
    return await _callGeminiForText(prompt);
  }

  Future<String> _analyzeMixture(
      Map<String, dynamic> product1, Map<String, dynamic> product2) async {
    final prompt =
        "Analyse le danger potentiel si on mélange les deux produits suivants pour faire le ménage.\n"
        "Produit 1 (type général) : \"${product1['nom']}\".\n"
        "Produit 2 (type général) : \"${product2['nom']}\".\n"
        "Si le mélange est dangereux, explique pourquoi de manière claire et alerte l'utilisateur avec un titre en majuscules comme 'DANGER DE MÉLANGE'. Si le mélange est sans danger particulier, dis-le clairement. Réponds en français.";
    return await _callGeminiForText(prompt);
  }

  Future<String> _callGeminiForText(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ]
        }),
      );
      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        return decodedResponse['candidates'][0]['content']['parts'][0]['text'];
      }
      return "Erreur d'analyse : L'API a retourné le code ${response.statusCode}.";
    } catch (e) {
      return "Erreur de connexion : Impossible de contacter le service d'analyse. $e";
    }
  }

  void _showResultDialog(String title, String content, {String? scannedText}) {
    showDialog(
      context: context,
      builder: (context) {
        final cleanedContent = content.replaceAll(RegExp(r'\*+'), '');
        final contentLines = cleanedContent.split('\n');
        final List<Widget> formattedContentWidgets = [];

        for (final line in contentLines) {
          if (line.trim().isEmpty) continue;
          final isTitle = (line.trim().endsWith(':') && !line.contains('.')) ||
              (line.trim().toUpperCase() == line.trim() &&
                  line.trim().length > 5 &&
                  !line.contains('.'));
          formattedContentWidgets.add(Padding(
            padding: EdgeInsets.only(
                top: isTitle ? 16.0 : 0, bottom: isTitle ? 6.0 : 8.0),
            child: Text(
              line.trim(),
              style: TextStyle(
                fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
                fontSize: isTitle ? 16 : 14,
                color: isTitle
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.4,
              ),
            ),
          ));
        }

        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (scannedText != null && scannedText.isNotEmpty) ...[
                const Text("Texte analysé :",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('"$scannedText"',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.grey)),
                const Divider(height: 20, thickness: 1),
              ],
              if (formattedContentWidgets.isNotEmpty)
                ...formattedContentWidgets
              else
                Text(cleanedContent),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCameraReady = _controller?.value.isInitialized ?? false;

    if (!isCameraReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Analyse de Produits')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          if (_recognizedText != null)
            CustomPaint(
              painter: TextDetectorPainter(
                recognizedText: _recognizedText!,
                imageSize: _imageSize ?? Size.zero,
              ),
            ),
          if (_lastScannedProduct != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                child: Chip(
                  avatar: const Icon(Icons.memory, color: Colors.blue),
                  label: Text('En mémoire : ${_lastScannedProduct!['nom']}'),
                  onDeleted: () {
                    setState(() {
                      _lastScannedProduct = null;
                    });
                  },
                ),
              ),
            ),
          if (_isAnalyzing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Analyse en cours...",
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            ),
          if (!_isAnalyzing)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: ElevatedButton.icon(
                  onPressed: _analyzeCapturedText,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(_lastScannedProduct == null
                      ? 'Analyser Produit 1'
                      : 'Analyser et Comparer'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}

class TextDetectorPainter extends CustomPainter {
  final RecognizedText recognizedText;
  final Size imageSize;
  TextDetectorPainter({required this.recognizedText, required this.imageSize});
  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.greenAccent.withOpacity(0.8);
    for (final textBlock in recognizedText.blocks) {
      canvas.drawRect(
          Rect.fromLTRB(
              textBlock.boundingBox.left * scaleX,
              textBlock.boundingBox.top * scaleY,
              textBlock.boundingBox.right * scaleX,
              textBlock.boundingBox.bottom * scaleY),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

InputImage? _inputImageFromCameraImage(CameraImage image) {
  final sensorOrientation = 90;
  final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  if (rotation == null) return null;
  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;
  final bytes = WriteBuffer();
  for (final Plane plane in image.planes) {
    bytes.putUint8List(plane.bytes);
  }
  return InputImage.fromBytes(
    bytes: bytes.done().buffer.asUint8List(),
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    ),
  );
}
