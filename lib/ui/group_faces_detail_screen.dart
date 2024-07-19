import 'package:face_grouping/models/image_data.dart';
import 'package:flutter/material.dart';
import '../models/face_group.dart';

class GroupFacesDetailScreen extends StatelessWidget {
  final List<FaceGroup> faceGroup;
  final List<ImageData> images;

  const GroupFacesDetailScreen({
    super.key,
    required this.faceGroup,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Faces Detail'),
      ),
      body: ListView.builder(
        itemCount: faceGroup.length,
        itemBuilder: (context, index) {
          final faceInfo = faceGroup[index];
          final faceImage = faceInfo.faceImage;
          final originalImagePath = faceInfo.originalImagePath;
          final rect = faceInfo.rect;

          return Card(
            margin: EdgeInsets.all(10),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.memory(faceImage),
                  SizedBox(height: 10),
                  Text(
                    'Original Image: $originalImagePath',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 5),
                  Text('Rect: ${rect.toMap()}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
