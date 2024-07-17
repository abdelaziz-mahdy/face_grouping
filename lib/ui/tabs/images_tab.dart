import 'package:flutter/material.dart';
import '../../controllers/face_detection_controller.dart';

class ImagesTab extends StatelessWidget {
  final FaceDetectionController controller;

  const ImagesTab({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          controller.isProcessing
              ? Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text('Processing: ${(controller.progress * 100).toStringAsFixed(2)}%'),
                    const SizedBox(height: 10),
                    Text('Estimated time remaining: ${controller.timeRemaining.inSeconds} seconds'),
                    const SizedBox(height: 10),
                    Text('Images processed: ${controller.processedImages} out of ${controller.totalImages}'),
                  ],
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: controller.images.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(controller.images[index].path),
                        subtitle: Text('Faces detected: ${controller.images[index].faceCount}'),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
