import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'face_recognition_service.dart';
import 'image_service.dart';
import 'group_faces_detail_screen.dart';

class SimilarFacesTab extends StatefulWidget {
  final List<ImageData> images;
  final List<List<Map<String, dynamic>>> faceGroups;

  const SimilarFacesTab({super.key, required this.images, required this.faceGroups});

  @override
  _SimilarFacesTabState createState() => _SimilarFacesTabState();
}

class _SimilarFacesTabState extends State<SimilarFacesTab> {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _stage = "Starting...";
  Duration? _estimatedTimeRemaining;
  int _processedFaces = 0;
  int _totalFaces = 0;

  @override
  void initState() {
    super.initState();
    if (widget.faceGroups.isEmpty) {
      _processSimilarFaces();
    } else {
      setState(() {
        _isProcessing = false;
        _progress = 1.0;
      });
    }
  }

  void _processSimilarFaces() {
    if (mounted) {
      setState(() {
        _isProcessing = true;
        _progress = 0.0;
        _stage = "Initializing...";
        _estimatedTimeRemaining = null;
        _processedFaces = 0;
        _totalFaces = 0;
      });
    }

    FaceRecognitionService.instance.groupSimilarFaces(
      widget.images,
      (progress, stage, processedFaces, totalFaces, timeRemaining) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _stage = stage;
            _processedFaces = processedFaces;
            _totalFaces = totalFaces;
            _estimatedTimeRemaining = timeRemaining;
          });
        }
      },
      (faceGroups) {
        if (mounted) {
          setState(() {
            widget.faceGroups.addAll(faceGroups);
            _isProcessing = false;
            _estimatedTimeRemaining = null;
          });
        }
      },
    );
  }

  Widget _buildFaceImage(Uint8List faceImageData) {
    return FutureBuilder<Uint8List>(
      future: _decodeFaceImage(faceImageData),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
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
                if (_estimatedTimeRemaining != null)
                  Text('Estimated time remaining: ${_estimatedTimeRemaining!.inSeconds} seconds'),
                Text('Faces processed: $_processedFaces out of $_totalFaces'),
              ],
            )
          : widget.faceGroups.isEmpty
              ? const Text('No similar faces detected')
              : ListView.builder(
                  itemCount: widget.faceGroups.length,
                  itemBuilder: (context, index) {
                    final group = widget.faceGroups[index];
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GroupFacesDetailScreen(
                                    faceGroup: group,
                                    images: widget.images,
                                  ),
                                ),
                              );
                            },
                            child: Text('Group ${index + 1}: ${group.length} faces'),
                          ),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: group.length,
                              itemBuilder: (context, faceIndex) {
                                return Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: _buildFaceImage(group[faceIndex]['faceImage']),
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
