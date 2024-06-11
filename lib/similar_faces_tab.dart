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
    });

    FaceRecognitionService.instance.groupSimilarFaces(
      widget.images,
      (progress) {
        setState(() {
          _progress = progress;
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _isProcessing
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                    'Grouping Similar Faces: ${(_progress * 100).toStringAsFixed(2)}%'),
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
                                  child: Image.memory(group[faceIndex]),
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
