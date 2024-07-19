import 'dart:io';

import 'package:face_grouping/utils/human_readable_duration.dart';
import 'package:flutter/material.dart';
import '../../controllers/face_detection_controller.dart';

class ImagesTab extends StatelessWidget {
  final FaceDetectionController controller;

  const ImagesTab({super.key, required this.controller});

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
                    Text(
                        'Processing: ${(controller.progress * 100).toStringAsFixed(2)}%'),
                    const SizedBox(height: 10),
                    Text(
                        'Estimated time remaining: ${controller.timeRemaining.toHumanReadableString()}'),
                    const SizedBox(height: 10),
                    Text(
                        'Images processed: ${controller.processedImages} out of ${controller.totalImages}'),
                  ],
                )
              : Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150),
                    itemCount: controller.images.length,
                    itemBuilder: (context, index) {
                      final image = controller.images[index];
                      return Stack(
                        children: [
                          Image.file(
                            File(image.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4.0),
                              color: Colors.black54,
                              child: Text(
                                'Faces: ${image.faceCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
