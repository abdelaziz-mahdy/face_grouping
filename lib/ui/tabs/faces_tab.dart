import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../controllers/face_detection_controller.dart';
import '../../services/image_service.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class FacesTab extends StatelessWidget {
  final FaceDetectionController controller;

  const FacesTab({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final faceRectsAndPaths = controller.images.expand((image) {
      return image.sendableFaceRects.map((rect) => {
        'path': image.path,
        'rect': rect,
      }).toList();
    }).toList();

    return Center(
      child: controller.isProcessing
          ? const CircularProgressIndicator()
          : faceRectsAndPaths.isEmpty
              ? const Text('No faces detected')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 50),
                  itemCount: faceRectsAndPaths.length,
                  itemBuilder: (context, index) {
                    final faceInfo = faceRectsAndPaths[index];
                    return Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _buildFaceImage(faceInfo['path'] as String, faceInfo['rect'] as SendableRect),
                    );
                  },
                ),
    );
  }

  Widget _buildFaceImage(String imagePath, SendableRect rect) {
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

  Future<Uint8List> _encodeFaceImage(String imagePath, SendableRect rect) async {
    try {
      final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
      final face = img.region(rect.toRect());
      final encodedFace = cv.imencode('.jpg', face);
      return encodedFace;
    } catch (e) {
      throw Exception('Failed to load face image: $e');
    }
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
