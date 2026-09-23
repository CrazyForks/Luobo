import 'package:flutter/material.dart';
import 'package:fluid_mesh_background/fluid_mesh_background.dart';

void main() => runApp(const ExampleApp());

/// Palette sources used by the demo grid.
const List<String> _demoImages = [
  'https://picsum.photos/seed/one/300',
  'https://picsum.photos/seed/two/300',
  'https://picsum.photos/seed/three/300',
  'https://picsum.photos/seed/four/300',
];

/// A two-column grid of fluid backgrounds, each with its own flow pattern.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fluid_mesh_background',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        appBar: AppBar(title: const Text('fluid_mesh_background')),
        // A scope lets all cards share a single clock (one ticker, not four).
        body: FluidBackgroundScope(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Extracted from an image'),
                const SizedBox(height: 8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    for (var i = 0; i < _demoImages.length; i++)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FluidBackground(
                          imageUrl: _demoImages[i],
                          // 45° apart: neighbouring cards must not share a pattern.
                          seed: FluidBackground.seedForIndex(i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Fixed colours, custom style, slower'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: FluidBackground(
                    colors: const [
                      Color(0xFFB3123C),
                      Color(0xFF2B1B6B),
                      Color(0xFF1E7A6B),
                      Color(0xFF120A1E),
                    ],
                    style: const FluidBackgroundStyle(
                      speed: 0.15,
                      warp: 4.0,
                      grain: 0.09,
                    ),
                    borderRadius: 16,
                    // Darkens the field so white text stays legible on top.
                    showScrim: true,
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Fallback path (no shader)'),
                const SizedBox(height: 8),
                const SizedBox(
                  height: 120,
                  child: FluidBackground(
                    colors: [
                      Color(0xFF3A1D6E),
                      Color(0xFF14466B),
                      Color(0xFF0E5C4A),
                      Color(0xFF120A1E),
                    ],
                    useShader: false,
                    borderRadius: 16,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
