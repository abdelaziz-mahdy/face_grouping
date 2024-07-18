import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:face_grouping/models/image_data.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import '../models/face_group.dart';

class FaceRecognitionService {
  FaceRecognitionService._privateConstructor();

  static final FaceRecognitionService instance =
      FaceRecognitionService._privateConstructor();

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
    void Function(List<List<FaceGroup>>) completionCallback,
  ) async {
    final completer = Completer<void>();
    final receivePort = ReceivePort();
    final startTime = DateTime.now();
    const int numberOfIsolates = 6;

    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    final totalImages = images.length;
    final batchSize = (totalImages / numberOfIsolates).ceil();
    final faceGroups = <List<FaceGroup>>[];
    final progressMap = List.filled(numberOfIsolates, 0.0);
    final processedImagesMap = List.filled(numberOfIsolates, 0);
    int overallProcessedImages = 0;
    int totalProcessedFaces = 0;

    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * batchSize;
      final end =
          (i + 1) * batchSize > totalImages ? totalImages : (i + 1) * batchSize;
      final batch = images.sublist(start, end);

      if (batch.isEmpty) continue;

      Isolate.spawn(
        _groupSimilarFacesIsolate,
        _ProcessFacesParams(
          batch,
          receivePort.sendPort,
          tmpModelPath,
          i,
          totalImages,
        ),
      );
    }

    receivePort.listen((message) {
      if (message is ProgressMessage) {
        progressMap[message.isolateIndex] = message.progress;
        processedImagesMap[message.isolateIndex] = message.processed;

        final overallProgress =
            progressMap.reduce((a, b) => a + b) / numberOfIsolates;
        overallProcessedImages = processedImagesMap.reduce((a, b) => a + b);

        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / overallProgress);
        final remainingTime = estimatedTotalTime - elapsed;

        progressCallback(
          overallProgress,
          "Processing",
          overallProcessedImages,
          totalImages,
          remainingTime,
        );
      } else if (message is List<List<Map<String, dynamic>>>) {
        final groups = message
            .map((group) => group.map((map) => FaceGroup.fromMap(map)).toList())
            .toList();
        faceGroups.addAll(groups);
        totalProcessedFaces +=
            groups.fold(0, (sum, group) => sum + group.length);

        if (totalProcessedFaces ==
            images.fold<int>(0, (sum, image) => sum + image.faceCount)) {
          completionCallback(faceGroups);
          completer.complete();
          receivePort.close();
        }
      }
    });

    return completer.future;
  }

  static Future<void> _groupSimilarFacesIsolate(
      _ProcessFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(
      params.modelPath,
      "",
      backendId: cv.DNN_BACKEND_OPENCV,
      targetId: cv.DNN_TARGET_OPENCL,
    );

    final faceFeatures = <Uint8List, cv.Mat>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};
    final totalFaces = params.imagePaths
        .fold<int>(0, (sum, image) => sum + image.sendableFaceRects.length);

    int processedFaces = 0;

    for (var image in params.imagePaths) {
      final imagePath = image.path;
      for (var i = 0; i < image.sendableFaceRects.length; i++) {
        final rect = image.sendableFaceRects[i];
        final mat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);

        final faceBox = cv.Mat.fromList(1, rect.rawDetection.length,
            cv.MatType.CV_32FC1, rect.rawDetection);
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
        params.sendPort.send(ProgressMessage(
          processedFaces / totalFaces,
          processedFaces,
          totalFaces,
          params.isolateIndex,
        ));
      }
    }

    final faceGroups = <List<FaceGroup>>[];
    processedFaces = 0;

    for (var entry in faceFeatures.entries) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      bool added = false;

      for (var group in faceGroups) {
        double totalMatchScoreCosine = 0;
        double totalMatchScoreNormL2 = 0;

        for (var existingFace in group) {
          final existingFeature = faceFeatures[existingFace.faceImage]!;
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

        if (averageMatchScoreCosine >= 0.38 &&
            averageMatchScoreNormL2 <= 1.12) {
          group.add(FaceGroup(
            faceImage: faceImage,
            originalImagePath: faceInfoMap[faceImage]!['originalImagePath'],
            rect: faceInfoMap[faceImage]!['rect'],
          ));
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([
          FaceGroup(
            faceImage: faceImage,
            originalImagePath: faceInfoMap[faceImage]!['originalImagePath'],
            rect: faceInfoMap[faceImage]!['rect'],
          ),
        ]);
      }

      processedFaces++;
      params.sendPort.send(ProgressMessage(
        processedFaces / totalFaces,
        processedFaces,
        totalFaces,
        params.isolateIndex,
      ));
    }

    recognizer.dispose();
    params.sendPort.send(faceGroups
        .map((group) => group.map((face) => face.toMap()).toList())
        .toList());
  }
}

class _ProcessFacesParams {
  final List<ImageData> imagePaths;
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex;
  final int total;

  _ProcessFacesParams(
    this.imagePaths,
    this.sendPort,
    this.modelPath,
    this.isolateIndex,
    this.total,
  );
}

class ProgressMessage {
  final double progress;
  final int processed;
  final int total;
  final int isolateIndex;

  ProgressMessage(this.progress, this.processed, this.total, this.isolateIndex);
}
