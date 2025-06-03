import 'package:flutter/material.dart';

class ResultsScreen extends StatelessWidget {
  final List<String> detectedItems;

  const ResultsScreen({super.key, required this.detectedItems});

  final List<List<String>> dangerousCombinations = const [
    ['bleach', 'ammonia'],
    ['bleach', 'vinegar'],
    ['hydrogen peroxide', 'vinegar'],
  ];

  bool _isDangerousCombination() {
    final normalizedItems = detectedItems.map((item) => item.toLowerCase()).toList();

    for (var combo in dangerousCombinations) {
      final normalizedCombo = combo.map((item) => item.toLowerCase()).toList();
      bool allPresent = normalizedCombo.every((item) => normalizedItems.any((detected) => detected.contains(item)));
      if (allPresent && normalizedCombo.length <= normalizedItems.length) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDangerous = _isDangerousCombination();

    return Scaffold(
      appBar: AppBar(title: const Text('Detection Results')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detected Items:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            for (var item in detectedItems) Text('• $item'),
            const SizedBox(height: 20),
            if (isDangerous)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.redAccent,
                child: const Text(
                  'WARNING: Dangerous combination detected! Do not mix these products.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            else
              const Text(
                'No dangerous combinations detected.',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}