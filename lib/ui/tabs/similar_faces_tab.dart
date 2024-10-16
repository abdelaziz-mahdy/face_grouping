import 'dart:typed_data';
import 'package:face_grouping/utils/human_readable_duration.dart';
import 'package:flutter/material.dart';
import '../../controllers/face_grouping_controller.dart';
import '../group_faces_detail_screen.dart';

class SimilarFacesTab extends StatelessWidget {
  final FaceGroupingController controller;

  const SimilarFacesTab({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: controller.isProcessing
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                    '${controller.stage}: ${(controller.progress * 100).toStringAsFixed(2)}%'),
                Text(
                    'Estimated time remaining: ${controller.timeRemaining.toHumanReadableString()}'),
                Text(
                    'Faces processed: ${controller.processedImages} out of ${controller.totalImages}'),
              ],
            )
          : controller.faceGroups.isEmpty
              ? const Text('No similar faces detected')
              : ListView.builder(
                  itemCount: controller.faceGroups.length,
                  itemBuilder: (context, index) {
                    final group = controller.faceGroups[index];
                    return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupFacesDetailScreen(
                                faceGroup: group,
                                images: controller.images,
                              ),
                            ),
                          );
                        },
                        child: Padding(
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
                                      child: _buildFaceImage(
                                          group[faceIndex].faceImage),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ));
                  },
                ),
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
    return encodedFaceImage;
  }
}
