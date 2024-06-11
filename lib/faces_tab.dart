import 'package:flutter/material.dart';
import 'image_service.dart';

class FacesTab extends StatelessWidget {
  final List<ImageData> images;
  final bool isProcessing;

  const FacesTab({super.key, required this.images, required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    final faceImages = images.expand((image) => image.faceImages).toList();

    return Center(
      child: isProcessing
          ? const CircularProgressIndicator()
          : faceImages.isEmpty
              ? const Text('No faces detected')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: faceImages.length,
                  itemBuilder: (context, index) {
                    return Image.memory(faceImages[index]);
                  },
                ),
    );
  }
}
