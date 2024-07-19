import 'dart:typed_data';
import 'package:face_grouping/models/sendable_rect.dart';
import 'package:flutter/material.dart';
import '../../controllers/face_detection_controller.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class FacesTab extends StatelessWidget {
  final FaceDetectionController controller;

  const FacesTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final faceRectsAndPaths = controller.images.expand((image) {
      return image.sendableFaceRects
          .map((rect) => {
                'path': image.path,
                'rect': rect,
              })
          .toList();
    }).toList();

    return Center(
      child: controller.isProcessing
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
                      child: FaceImageWidget(
                        imagePath: faceInfo['path'] as String,
                        rect: faceInfo['rect'] as SendableRect,
                      ),
                    );
                  },
                ),
    );
  }
}

class FaceImageWidget extends StatefulWidget {
  final String imagePath;
  final SendableRect rect;

  const FaceImageWidget({
    super.key,
    required this.imagePath,
    required this.rect,
  });

  @override
  _FaceImageWidgetState createState() => _FaceImageWidgetState();
}

class _FaceImageWidgetState extends State<FaceImageWidget> {
  late final ValueNotifier<Uint8List?> _imageNotifier;
  late final ValueNotifier<String?> _errorNotifier;

  @override
  void initState() {
    super.initState();
    _imageNotifier = ValueNotifier<Uint8List?>(null);
    _errorNotifier = ValueNotifier<String?>(null);
    _loadFaceImage();
  }

  Future<void> _loadFaceImage() async {
    try {
      final encodedFace = await _encodeFaceImage(widget.imagePath, widget.rect);
      _imageNotifier.value = encodedFace;
    } catch (e) {
      _errorNotifier.value = e.toString();
    }
  }

  Future<Uint8List> _encodeFaceImage(
      String imagePath, SendableRect rect) async {
    try {
      final img = await cv.imreadAsync(imagePath, flags: cv.IMREAD_COLOR);
      final face = await img.regionAsync(rect.toRect());
      final (_, encodedFace) = await cv.imencodeAsync('.jpg', face);
      return encodedFace;
    } catch (e) {
      throw Exception('Failed to load face image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: _imageNotifier,
      builder: (context, imageData, child) {
        if (imageData != null) {
          return Image.memory(imageData);
        }
        return ValueListenableBuilder<String?>(
          valueListenable: _errorNotifier,
          builder: (context, error, child) {
            if (error != null) {
              return _buildErrorWidget(error);
            }
            return const CircularProgressIndicator();
          },
        );
      },
    );
  }

  Widget _buildErrorWidget(String error) {
    return Container(
      color: Colors.red[100],
      child: Center(
        child: Text(
          'Error: $error',
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _imageNotifier.dispose();
    _errorNotifier.dispose();
    super.dispose();
  }
}
