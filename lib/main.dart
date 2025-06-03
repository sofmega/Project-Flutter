import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'camera_screen.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras(); // Initialize cameras
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
    );
    final ThemeData darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: const Color(0xff6750a4),
      ),
    );

    return MaterialApp(
      title: 'Dangerous Mixture Detector',
      theme: lightTheme,
      darkTheme: darkTheme,
      routes: {
        '/': (_) => const HomePage(),
        '/camera': (_) => CameraScreen(cameras: cameras), // Pass cameras
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dangerous Mixture Detector')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pushNamed('/camera'),
          child: const Text('Open Camera for Detection'),
        ),
      ),
    );
  }
}