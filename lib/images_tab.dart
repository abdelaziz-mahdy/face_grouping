import 'package:flutter/material.dart';
import 'image_service.dart';

class ImagesTab extends StatelessWidget {
  final bool isProcessing;
  final double progress;
  final Duration timeRemaining;
  final int processedImages;
  final int totalImages;
  final List<ImageData> images;

  const ImagesTab({
    super.key,
    required this.isProcessing,
    required this.progress,
    required this.timeRemaining,
    required this.processedImages,
    required this.totalImages,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          isProcessing
              ? Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text('Processing: ${(progress * 100).toStringAsFixed(2)}%'),
                    const SizedBox(height: 10),
                    Text('Estimated time remaining: ${timeRemaining.inSeconds} seconds'),
                    const SizedBox(height: 10),
                    Text('Images processed: $processedImages out of $totalImages'),
                  ],
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(images[index].path),
                        subtitle: Text('Faces detected: ${images[index].faceCount}'),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
