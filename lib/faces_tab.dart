import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Required for compute function
import 'image_service.dart';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class FacesTab extends StatelessWidget {
  final List<ImageData> images;
  final bool isProcessing;
  final bool useCompute; // Configuration to use compute or not

  const FacesTab({
    super.key,
    required this.images,
    required this.isProcessing,
    this.useCompute = false, // Default to using compute for better performance
  });

  @override
  Widget build(BuildContext context) {
    // Collect all face rectangles and their corresponding image paths
    final faceRectsAndPaths = images.expand((image) {
      return image.sendableFaceRects
          .map((rect) => {
                'path': image.path,
                'rect': rect,
              })
          .toList();
    }).toList();

    return Center(
      child: isProcessing
          ? const CircularProgressIndicator()
          : faceRectsAndPaths.isEmpty
              ? const Text('No faces detected')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 50),
                  itemCount: faceRectsAndPaths.length,
                  itemBuilder: (context, index) {
                    final faceInfo = faceRectsAndPaths[index];
                    return Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _buildFaceImage(faceInfo['path'] as String,
                          faceInfo['rect'] as SendableRect),
                    );
                  },
                ),
    );
  }

  Widget _buildFaceImage(String imagePath, SendableRect rect) {
    if (useCompute) {
      return FutureBuilder<Uint8List>(
        future:
            compute(_encodeFaceImageIsolate, {'path': imagePath, 'rect': rect}),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              return Image.memory(snapshot.data!);
            } else if (snapshot.hasError) {
              return _buildErrorWidget(snapshot.error.toString());
            }
          }
          return const CircularProgressIndicator();
        },
      );
    } else {
      return FutureBuilder<Uint8List>(
        future: _encodeFaceImage(imagePath, rect),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              return Image.memory(snapshot.data!);
            } else if (snapshot.hasError) {
              return _buildErrorWidget(snapshot.error.toString());
            }
          }
          return const CircularProgressIndicator();
        },
      );
    }
  }

  static Future<Uint8List> _encodeFaceImage(
      String imagePath, SendableRect rect) async {
    try {
      final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
      final face = img.region(rect.toRect());
      final encodedFace = cv.imencode('.jpg', face);
      return encodedFace;
    } catch (e) {
      // Re-throw the error to be caught by FutureBuilder
      throw Exception('Failed to load face image: $e');
    }
  }

  static Future<Uint8List> _encodeFaceImageIsolate(
      Map<String, dynamic> params) async {
    final imagePath = params['path'] as String;
    final rect = params['rect'] as SendableRect;
    return _encodeFaceImage(imagePath, rect);
  }

  Widget _buildErrorWidget(String error) {
    return Container(
      color: Colors.red[100],
      child: Center(
        child: Text(
          'Error: $error',
          style: TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
