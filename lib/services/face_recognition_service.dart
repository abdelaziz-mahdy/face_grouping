import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:face_grouping/models/image_data.dart';
import 'package:face_grouping/models/sendable_rect.dart';
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
    int numberOfIsolates = 7;

    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    final totalFaces = images.fold<int>(
        0, (sum, image) => sum + image.sendableFaceRects.length);
    var batchSize = (totalFaces / numberOfIsolates).ceil();
    final faceFeatures = <Uint8List, List<double>>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};
    final progressMap = List.filled(numberOfIsolates, 0.0);
    final processedFacesMap = List.filled(numberOfIsolates, 0);
    int overallProcessedFaces = 0;
    int completedIsolates = 0;

    final List<Map<String, dynamic>> allRects = images.expand((image) {
      return image.sendableFaceRects.map((rect) => {
            'imagePath': image.path,
            'rect': rect,
          });
    }).toList();
    if (totalFaces <= numberOfIsolates) {
      numberOfIsolates = 1;
      batchSize = totalFaces;
    }
    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * batchSize;
      final end =
          (i + 1) * batchSize > totalFaces ? totalFaces : (i + 1) * batchSize;
      final batch = allRects.sublist(start, end);

      if (batch.isEmpty) continue;

      Isolate.spawn(
        _extractFeaturesIsolate,
        _ProcessFacesParams(
          batch,
          receivePort.sendPort,
          tmpModelPath,
          i,
        ),
      );
    }

    receivePort.listen((message) {
      if (message is ProgressMessage) {
        progressMap[message.isolateIndex] = message.progress;
        processedFacesMap[message.isolateIndex] = message.processed;

        final overallProgress =
            progressMap.reduce((a, b) => a + b) / numberOfIsolates;
        overallProcessedFaces = processedFacesMap.reduce((a, b) => a + b);

        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / overallProgress);
        final remainingTime = estimatedTotalTime - elapsed;

        progressCallback(
          overallProgress,
          "Stage 1 out of 2, Extracting faces features",
          overallProcessedFaces,
          totalFaces,
          remainingTime,
        );
      } else if (message is ExtractionCompleteMessage) {
        faceFeatures.addAll(message.faceFeatures);
        faceInfoMap.addAll(message.faceInfoMap);
        completedIsolates++;

        if (completedIsolates == numberOfIsolates) {
          // All feature extraction is complete, now perform the grouping in an isolate
          Isolate.spawn(
            _groupFacesIsolate,
            _GroupFacesParams(
              tmpModelPath,
              faceFeatures,
              faceInfoMap,
              receivePort.sendPort,
              totalFaces,
            ),
          );
        }
      } else if (message is GroupingProgressMessage) {
        final progress = message.progress;
        final processed = message.processed;

        final overallProgress = progress;
        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / overallProgress);
        final remainingTime = estimatedTotalTime - elapsed;

        progressCallback(
          overallProgress,
          "Stage 2 out of 2, Grouping",
          processed,
          totalFaces,
          remainingTime,
        );
      } else if (message is GroupingCompleteMessage) {
        completionCallback(message.faceGroups);
        completer.complete();
      }
    });

    return completer.future;
  }

  static Future<void> _extractFeaturesIsolate(
      _ProcessFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(
      params.modelPath,
      "",
      // backendId: cv.DNN_BACKEND_VKCOM,
      // targetId: cv.DNN_TARGET_VULKAN,
    );

    final faceFeatures = <Uint8List, List<double>>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};

    final totalFaces = params.imagePaths.length;

    int processedFaces = 0;

    for (var image in params.imagePaths) {
      final imagePath = image['imagePath'];
      final rect = image['rect'] as SendableRect;
      final mat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);

      final faceBox = cv.Mat.fromList(
          1, rect.rawDetection.length, cv.MatType.CV_32FC1, rect.rawDetection);
      final alignedFace = recognizer.alignCrop(mat, faceBox);
      final feature = recognizer.feature(alignedFace);
      final (_, encodedFace) = cv.imencode('.jpg', alignedFace);
      faceFeatures[encodedFace] =
          List.generate(feature.width, (index) => feature.at<double>(0, index));

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

    recognizer.dispose();
    params.sendPort.send(ExtractionCompleteMessage(
      params.isolateIndex,
      faceFeatures,
      faceInfoMap,
    ));
  }

  static Future<void> _groupFacesIsolate(_GroupFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(
      params.modelPath,
      "",
      // backendId: cv.DNN_BACKEND_VKCOM,
      // targetId: cv.DNN_TARGET_VULKAN,
    );

    final faceGroups = <List<FaceGroup>>[];
    int processedFaces = 0;

    final sortedFaceFeatures = params.faceFeatures.entries.toList()
      ..sort((a, b) => _compareFeatures(a.value, b.value));

    for (var entry in sortedFaceFeatures) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      List<FaceGroup>? closestGroup;
      double closestDistance = double.infinity;

      for (var group in faceGroups) {
        final averageFeature = _computeAverageFeature(
            group.map((face) => params.faceFeatures[face.faceImage]!).toList());
        final distance = _distance(faceFeature, averageFeature);

        if (distance < closestDistance) {
          closestDistance = distance;
          closestGroup = group;
        }
      }

      if (closestGroup != null &&
          _isFeatureSimilar(recognizer, faceFeature, closestGroup, params)) {
        closestGroup.add(FaceGroup(
          faceImage: faceImage,
          originalImagePath:
              params.faceInfoMap[faceImage]!['originalImagePath'],
          rect: params.faceInfoMap[faceImage]!['rect'],
        ));
      } else {
        faceGroups.add([
          FaceGroup(
            faceImage: faceImage,
            originalImagePath:
                params.faceInfoMap[faceImage]!['originalImagePath'],
            rect: params.faceInfoMap[faceImage]!['rect'],
          ),
        ]);
      }

      processedFaces++;
      params.sendPort.send(GroupingProgressMessage(
        processedFaces / params.totalFaces,
        processedFaces,
      ));
    }

    recognizer.dispose();
    // Sort faceGroups to have the group with the highest count first
    faceGroups.sort((a, b) => b.length.compareTo(a.length));

    params.sendPort.send(GroupingCompleteMessage(faceGroups));
  }

  static bool _isFeatureSimilar(
      cv.FaceRecognizerSF recognizer,
      List<double> faceFeature,
      List<FaceGroup> group,
      _GroupFacesParams params) {
    double totalMatchScoreCosine = 0;
    double totalMatchScoreNormL2 = 0;

    for (var existingFace in group) {
      final existingFeature = cv.Mat.fromList(
          1,
          params.faceFeatures[existingFace.faceImage]!.length,
          cv.MatType.CV_32FC1,
          params.faceFeatures[existingFace.faceImage]!);
      totalMatchScoreCosine += recognizer.match(
        cv.Mat.fromList(
            1, faceFeature.length, cv.MatType.CV_32FC1, faceFeature),
        existingFeature,
        disType: cv.FaceRecognizerSF.FR_COSINE,
      );
      totalMatchScoreNormL2 += recognizer.match(
        cv.Mat.fromList(
            1, faceFeature.length, cv.MatType.CV_32FC1, faceFeature),
        existingFeature,
        disType: cv.FaceRecognizerSF.FR_NORM_L2,
      );
    }

    final averageMatchScoreCosine = totalMatchScoreCosine / group.length;
    final averageMatchScoreNormL2 = totalMatchScoreNormL2 / group.length;

    return averageMatchScoreCosine >= 0.38 && averageMatchScoreNormL2 <= 1.12;
  }

  static int _compareFeatures(List<double> a, List<double> b) {
    final aSum = a.reduce((value, element) => value + element);
    final bSum = b.reduce((value, element) => value + element);
    return aSum.compareTo(bSum);
  }

  static List<double> _computeAverageFeature(List<List<double>> features) {
    final avgFeature = List<double>.filled(features[0].length, 0.0);
    for (var feature in features) {
      for (var i = 0; i < feature.length; i++) {
        avgFeature[i] += feature[i];
      }
    }
    return avgFeature.map((value) => value / features.length).toList();
  }

  static double _distance(List<double> a, List<double> b) {
    double sum = 0;
    for (var i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]) * (a[i] - b[i]);
    }
    return sum;
  }
}

class _ProcessFacesParams {
  final List<Map<String, dynamic>> imagePaths;
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex;

  _ProcessFacesParams(
    this.imagePaths,
    this.sendPort,
    this.modelPath,
    this.isolateIndex,
  );
}

class _GroupFacesParams {
  final String modelPath;
  final Map<Uint8List, List<double>> faceFeatures;
  final Map<Uint8List, Map<String, dynamic>> faceInfoMap;
  final SendPort sendPort;
  final int totalFaces;

  _GroupFacesParams(
    this.modelPath,
    this.faceFeatures,
    this.faceInfoMap,
    this.sendPort,
    this.totalFaces,
  );
}

class ProgressMessage {
  final double progress;
  final int processed;
  final int total;
  final int isolateIndex;

  ProgressMessage(this.progress, this.processed, this.total, this.isolateIndex);
}

class ExtractionCompleteMessage {
  final int isolateIndex;
  final Map<Uint8List, List<double>> faceFeatures;
  final Map<Uint8List, Map<String, dynamic>> faceInfoMap;

  ExtractionCompleteMessage(
    this.isolateIndex,
    this.faceFeatures,
    this.faceInfoMap,
  );
}

class GroupingProgressMessage {
  final double progress;
  final int processed;

  GroupingProgressMessage(this.progress, this.processed);
}

class GroupingCompleteMessage {
  final List<List<FaceGroup>> faceGroups;

  GroupingCompleteMessage(this.faceGroups);
}
