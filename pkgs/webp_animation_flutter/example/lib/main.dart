import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webp_animation_flutter/webp_animation_flutter.dart';

void main() {
  runApp(const WebpAnimationExampleApp());
}

class WebpAnimationExampleApp extends StatelessWidget {
  const WebpAnimationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebP Animation Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const animationAsset = '../assets/animated-webp-supported.webp';
  static const animationCount = 60;
  static const singleAnimationSize = Size(200, 200);
  static const batchAnimationSize = Size(50, 50);

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebP Animation Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Single animation view
          _buildSingleAnimationView(),
          // Batch animation view
          _buildBatchAnimationView(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.looks_one),
            label: 'Single Animation',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: 'Batch ($animationCount Animations)',
          ),
        ],
      ),
    );
  }

  Widget _buildSingleAnimationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Single Animation',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          WebpAnimation(
            asset: animationAsset,
            width: singleAnimationSize.width,
            height: singleAnimationSize.height,
            autoPlay: true,
            loop: true,
            respectFrameDelays: true,
          ),
          const SizedBox(height: 20),
          Text(
            'Individual WebpAnimation widget\nSeparate draw call per animation',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBatchAnimationView() {
    // Calculate grid dimensions for square-ish layout
    final gridSize = math.sqrt(animationCount).ceil();
    final totalWidth = gridSize * batchAnimationSize.width;
    final totalHeight = gridSize * batchAnimationSize.height;

    // Create animation items in grid layout
    final animationItems = <WebpAnimationItem>[];
    for (int i = 0; i < animationCount; i++) {
      final row = i ~/ gridSize;
      final col = i % gridSize;
      animationItems.add(
        WebpAnimationItem(
          asset: animationAsset,
          position: Offset(
            col * batchAnimationSize.width,
            row * batchAnimationSize.height,
          ),
          size: batchAnimationSize,
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Batch Animation Layer',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            '$animationCount animations',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: totalWidth,
            height: totalHeight,
            child: WebpAnimationLayer(
              animations: animationItems,
              autoPlay: true,
              loop: true,
              respectFrameDelays: true,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Single WebpAnimationLayer widget\nOne draw call for all animations\nPerfect synchronization',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
