// lib/face_recognition_service.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'image_service.dart';
import 'dart:convert';
import 'isolate_utils.dart';

class FaceRecognitionService {
  FaceRecognitionService._privateConstructor();

  static final FaceRecognitionService instance = FaceRecognitionService._privateConstructor();

  factory FaceRecognitionService() {
    return instance;
  }

  Future<String> _copyAssetFileToTmp(String assetPath) async {
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = '${tmpDir.path}/${assetPath.split('/').last}';
    final byteData = await rootBundle.load(assetPath);
    final file = File(tmpPath);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return tmpPath;
  }

  Future<void> groupSimilarFaces(
    List<ImageData> images,
    void Function(double, String, int, int, Duration) progressCallback,
    void Function(List<List<Map<String, dynamic>>>) completionCallback,
  ) async {
    final tmpModelPath = await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    IsolateUtils.runIsolate<ImageData, List<Map<String, dynamic>>>(
      data: images,
      numberOfIsolates: 6,
      isolateEntryPoint: (data, sendPort) => _groupSimilarFacesIsolate(data, sendPort, tmpModelPath),
      progressCallback: (progress, processed, total, remaining) => progressCallback(progress, "Processing", processed, total, remaining),
      completionCallback: completionCallback,
    );
  }

  static Future<void> _groupSimilarFacesIsolate(
    List<ImageData> images,
    SendPort sendPort,
    String modelPath,
  ) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(
      modelPath,
      "",
      backendId: cv.DNN_BACKEND_OPENCV,
      targetId: cv.DNN_TARGET_OPENCL,
    );
    final faceFeatures = <Uint8List, cv.Mat>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};
    final totalFaces = images.fold<int>(0, (sum, image) => sum + image.sendableFaceRects.length);

    int processedFaces = 0;

    for (var image in images) {
      final imagePath = image.path;
      for (var i = 0; i < image.sendableFaceRects.length; i++) {
        final rect = image.sendableFaceRects[i];
        final mat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);

        final faceBox = cv.Mat.fromList(1, rect.rawDetection.length, cv.MatType.CV_32FC1, rect.rawDetection);
        final alignedFace = recognizer.alignCrop(mat, faceBox);
        final feature = recognizer.feature(alignedFace);
        final encodedFace = cv.imencode('.jpg', alignedFace);

        faceFeatures[encodedFace] = feature.clone();
        faceInfoMap[encodedFace] = {
          'originalImagePath': rect.originalImagePath,
          'rect': rect,
        };

        alignedFace.dispose();
        faceBox.dispose();
        processedFaces++;
        sendPort.send(_ProgressMessage(processedFaces / totalFaces, processedFaces));
      }
    }

    final faceGroups = <List<Map<String, dynamic>>>[];
    processedFaces = 0;

    for (var entry in faceFeatures.entries) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      bool added = false;

      for (var group in faceGroups) {
        double totalMatchScoreCosine = 0;
        double totalMatchScoreNormL2 = 0;

        for (var existingFace in group) {
          final existingFeature = faceFeatures[existingFace['faceImage']]!;
          totalMatchScoreCosine += recognizer.match(
            faceFeature,
            existingFeature,
            disType: cv.FaceRecognizerSF.FR_COSINE,
          );
          totalMatchScoreNormL2 += recognizer.match(
            faceFeature,
            existingFeature,
            disType: cv.FaceRecognizerSF.FR_NORM_L2,
          );
        }

        final averageMatchScoreCosine = totalMatchScoreCosine / group.length;
        final averageMatchScoreNormL2 = totalMatchScoreNormL2 / group.length;

        if (averageMatchScoreCosine >= 0.38 && averageMatchScoreNormL2 <= 1.12) {
          group.add({
            'faceImage': faceImage,
            'originalImagePath': faceInfoMap[faceImage]!['originalImagePath'],
            'rect': faceInfoMap[faceImage]!['rect'],
          });
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([
          {
            'faceImage': faceImage,
            'originalImagePath': faceInfoMap[faceImage]!['originalImagePath'],
            'rect': faceInfoMap[faceImage]!['rect'],
          }
        ]);
      }

      processedFaces++;
      sendPort.send(_ProgressMessage(processedFaces / totalFaces, processedFaces));
    }

    recognizer.dispose();
    sendPort.send(faceGroups);
  }
}

class _ProgressMessage {
  final double progress;
  final int processed;

  _ProgressMessage(this.progress, this.processed);
}
