import 'package:flutter/material.dart';
import 'face_recognition_service.dart';
import 'image_service.dart';

class SimilarFacesTab extends StatelessWidget {
  final List<ImageData> images;

  const SimilarFacesTab({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final faceGroups = FaceRecognitionService.groupSimilarFaces(images);

    return faceGroups.isEmpty
        ? const Center(child: Text('No similar faces detected'))
        : ListView.builder(
            itemCount: faceGroups.length,
            itemBuilder: (context, index) {
              final group = faceGroups[index];
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
          );
  }
}
