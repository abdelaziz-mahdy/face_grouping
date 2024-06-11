import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'face_recognition_service.dart';
import 'image_service.dart';

class SimilarFacesTab extends StatefulWidget {
  final List<ImageData> images;

  const SimilarFacesTab({super.key, required this.images});

  @override
  _SimilarFacesTabState createState() => _SimilarFacesTabState();
}

class _SimilarFacesTabState extends State<SimilarFacesTab> {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _stage = "Starting...";
  List<List<Uint8List>> _faceGroups = [];

  @override
  void initState() {
    super.initState();
    _processSimilarFaces();
  }

  void _processSimilarFaces() {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _stage = "Initializing...";
    });

    FaceRecognitionService.instance.groupSimilarFaces(
      widget.images,
      (progress, stage) {
        setState(() {
          _progress = progress;
          _stage = stage;
        });
      },
      (faceGroups) {
        setState(() {
          _faceGroups = faceGroups;
          _isProcessing = false;
        });
      },
    );
  }

  Widget _buildFaceImage(Uint8List faceImageData) {
    return FutureBuilder<Uint8List>(
      future: _decodeFaceImage(faceImageData),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return Image.memory(snapshot.data!);
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }

  Future<Uint8List> _decodeFaceImage(Uint8List encodedFaceImage) async {
    // Decode the face image as needed
    // Since we are dynamically rendering, we may not need to do any heavy operations here
    // This placeholder can be expanded based on specific requirements
    return encodedFaceImage;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _isProcessing
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text('$_stage: ${(_progress * 100).toStringAsFixed(2)}%'),
              ],
            )
          : _faceGroups.isEmpty
              ? const Text('No similar faces detected')
              : ListView.builder(
                  itemCount: _faceGroups.length,
                  itemBuilder: (context, index) {
                    final group = _faceGroups[index];
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Group ${index + 1}: ${group.length} faces'),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: group.length,
                              itemBuilder: (context, faceIndex) {
                                return Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: _buildFaceImage(group[faceIndex]),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
