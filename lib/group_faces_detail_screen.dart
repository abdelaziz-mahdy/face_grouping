import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'image_service.dart';

class GroupFacesDetailScreen extends StatelessWidget {
  final List<Map<String, dynamic>> faceGroup;
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
        title: Text('Group Faces Detail'),
      ),
      body: ListView.builder(
        itemCount: faceGroup.length,
        itemBuilder: (context, index) {
          final faceInfo = faceGroup[index];
          final faceImage = faceInfo['faceImage'];
          final originalImagePath = faceInfo['originalImagePath'];
          final rect = faceInfo['rect'];

          return Column(
            children: [
              Image.memory(faceImage),
              Text('Original Image: $originalImagePath'),
              // You can add more details about the original image here
            ],
          );
        },
      ),
    );
  }
}
