import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:face_grouping/models/image_data.dart';
import 'package:face_grouping/models/sendable_rect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import '../models/face_group.dart';

class FaceRecognitionService {
  FaceRecognitionService._privateConstructor();

  static final FaceRecognitionService instance =
      FaceRecognitionService._privateConstructor();

  factory FaceRecognitionService() => instance;

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
    final numberOfIsolates = _calculateOptimalIsolates(images);

    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");
    final allRects = _prepareAllRects(images);
    final batchSize = (allRects.length / numberOfIsolates).ceil();

    final extractionManager =
        _ExtractionManager(numberOfIsolates, allRects.length);
    final groupingManager = _GroupingManager(numberOfIsolates);

    _spawnExtractionIsolates(allRects, batchSize, tmpModelPath,
        receivePort.sendPort, numberOfIsolates);

    receivePort.listen((message) async {
      if (message is ProgressMessage) {
        _handleProgressMessage(message, extractionManager, groupingManager,
            startTime, progressCallback);
      } else if (message is ExtractionCompleteMessage) {
        await _handleExtractionComplete(message, extractionManager,
            groupingManager, tmpModelPath, receivePort.sendPort);
      } else if (message is GroupingCompleteMessage) {
        _handleGroupingComplete(
            message, groupingManager, tmpModelPath, receivePort.sendPort);
      } else if (message is FinalGroupingCompleteMessage) {
        _handleFinalGroupingComplete(
            message, completionCallback, completer, receivePort);
      }
    });

    return completer.future;
  }

  int _calculateOptimalIsolates(List<ImageData> images) {
    final totalFaces = images.fold<int>(
        0, (sum, image) => sum + image.sendableFaceRects.length);
    return totalFaces < 7 ? 1 : 7;
  }

  List<Map<String, dynamic>> _prepareAllRects(List<ImageData> images) {
    return images
        .expand((image) => image.sendableFaceRects.map((rect) => {
              'imagePath': image.path,
              'rect': rect,
            }))
        .toList();
  }

  void _spawnExtractionIsolates(
      List<Map<String, dynamic>> allRects,
      int batchSize,
      String tmpModelPath,
      SendPort sendPort,
      int numberOfIsolates) {
    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * batchSize;
      final end = (i + 1) * batchSize > allRects.length
          ? allRects.length
          : (i + 1) * batchSize;
      final batch = allRects.sublist(start, end);

      if (batch.isEmpty) continue;

      Isolate.spawn(
        _extractFeaturesIsolate,
        _ProcessFacesParams(batch, sendPort, tmpModelPath, i),
      );
    }
  }

  void _handleProgressMessage(
    ProgressMessage message,
    _ExtractionManager extractionManager,
    _GroupingManager groupingManager,
    DateTime startTime,
    void Function(double, String, int, int, Duration) progressCallback,
  ) {
    if (message.phase == ProcessingPhase.featureExtraction) {
      extractionManager.updateProgress(message);
    } else {
      groupingManager.updateProgress(message);
    }

    final overallProgress = extractionManager.overallProgress * 0.5 +
        groupingManager.overallProgress * 0.5;
    final elapsed = DateTime.now().difference(startTime);
    final estimatedTotalTime = elapsed * (1 / overallProgress);
    final remainingTime = estimatedTotalTime - elapsed;

    progressCallback(
      overallProgress,
      "Processing faces",
      message.processed,
      message.total,
      remainingTime,
    );
  }

  Future<void> _handleExtractionComplete(
    ExtractionCompleteMessage message,
    _ExtractionManager extractionManager,
    _GroupingManager groupingManager,
    String tmpModelPath,
    SendPort sendPort,
  ) async {
    extractionManager.addFeatures(message.faceFeatures, message.faceInfoMap);

    if (extractionManager.isComplete) {
      await _startGrouping(
          extractionManager.faceFeatures,
          extractionManager.faceInfoMap,
          tmpModelPath,
          sendPort,
          groupingManager.numberOfIsolates);
    }
  }

  Future<void> _startGrouping(
    Map<Uint8List, List<double>> faceFeatures,
    Map<Uint8List, Map<String, dynamic>> faceInfoMap,
    String tmpModelPath,
    SendPort sendPort,
    int numberOfIsolates,
  ) async {
    final faceEntries = faceFeatures.entries.toList();
    final groupingBatchSize = (faceFeatures.length / numberOfIsolates).ceil();

    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * groupingBatchSize;
      final end = (i + 1) * groupingBatchSize > faceFeatures.length
          ? faceFeatures.length
          : (i + 1) * groupingBatchSize;
      final batch = faceEntries.sublist(start, end);

      if (batch.isEmpty) continue;

      final batchFeatures = Map<Uint8List, List<double>>.fromEntries(batch);
      final batchInfo = Map<Uint8List, Map<String, dynamic>>.fromEntries(
          batch.map((e) => MapEntry(e.key, faceInfoMap[e.key]!)));

      Isolate.spawn(
        _groupFacesIsolate,
        _GroupFacesParams(
          tmpModelPath: tmpModelPath,
          faceFeatures: batchFeatures,
          faceInfoMap: batchInfo,
          sendPort: sendPort,
          totalFaces: batchFeatures.length,
          isolateIndex: i,
        ),
      );
    }
  }

  void _handleGroupingComplete(
      GroupingCompleteMessage message,
      _GroupingManager groupingManager,
      String tmpModelPath,
      SendPort sendPort) {
    groupingManager.addGroups(message.faceGroups);

    if (groupingManager.isComplete) {
      _startMerging(groupingManager.groupedFaceGroups, tmpModelPath, sendPort);
    }
  }

  void _startMerging(List<List<FaceGroup>> groupedFaceGroups,
      String tmpModelPath, SendPort sendPort) {
    Isolate.spawn(
      _mergeGroupsIsolate,
      _MergeGroupsParams(groupedFaceGroups, tmpModelPath, sendPort),
    );
  }

  void _handleFinalGroupingComplete(
    FinalGroupingCompleteMessage message,
    void Function(List<List<FaceGroup>>) completionCallback,
    Completer<void> completer,
    ReceivePort receivePort,
  ) {
    completionCallback(message.mergedFaceGroups);
    completer.complete();
    receivePort.close();
  }

  static Future<void> _extractFeaturesIsolate(
      _ProcessFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(params.modelPath, "");
    final faceFeatures = <Uint8List, List<double>>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};

    for (var (index, image) in params.imagePaths.indexed) {
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
        'rect': rect
      };

      alignedFace.dispose();
      faceBox.dispose();

      params.sendPort.send(ProgressMessage(
        (index + 1) / params.imagePaths.length,
        index + 1,
        params.imagePaths.length,
        params.isolateIndex,
        ProcessingPhase.featureExtraction,
      ));
    }

    recognizer.dispose();
    params.sendPort.send(ExtractionCompleteMessage(
        params.isolateIndex, faceFeatures, faceInfoMap));
  }

  static Future<void> _groupFacesIsolate(_GroupFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(params.tmpModelPath, "");
    final faceGroups = <List<FaceGroup>>{};

    final sortedFaceFeatures = params.faceFeatures.entries.toList()
      ..sort((a, b) => _compareFeatures(a.value, b.value));

    for (var (index, entry) in sortedFaceFeatures.indexed) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      final closestGroup =
          _findClosestGroup(faceGroups, faceFeature, recognizer);

      if (closestGroup != null) {
        closestGroup.add(FaceGroup(
          faceImage: faceImage,
          originalImagePath:
              params.faceInfoMap[faceImage]!['originalImagePath'],
          rect: params.faceInfoMap[faceImage]!['rect'],
          faceFeature: faceFeature,
        ));
      } else {
        faceGroups.add([
          FaceGroup(
            faceImage: faceImage,
            originalImagePath:
                params.faceInfoMap[faceImage]!['originalImagePath'],
            rect: params.faceInfoMap[faceImage]!['rect'],
            faceFeature: faceFeature,
          ),
        ]);
      }

      params.sendPort.send(GroupingProgressMessage(
        (index + 1) / params.totalFaces,
        index + 1,
        params.isolateIndex,
      ));
    }

    recognizer.dispose();
    params.sendPort.send(GroupingCompleteMessage(faceGroups.toList()));
  }

  static List<FaceGroup>? _findClosestGroup(Set<List<FaceGroup>> faceGroups,
      List<double> faceFeature, cv.FaceRecognizerSF recognizer) {
    List<FaceGroup>? closestGroup;
    double closestDistanceCosine = double.infinity;
    double closestDistanceNormL2 = double.infinity;
    for (var group in faceGroups) {
      final averageFeature = _computeAverageFeature(
          group.map((face) => face.faceFeature).toList());

      double cosineDistance;
      double normL2Distance;
      (cosineDistance, normL2Distance) =
          _calculateDistance(faceFeature, averageFeature, recognizer);
      if (cosineDistance < closestDistanceCosine) {
        closestDistanceCosine = cosineDistance;
      }

      if (normL2Distance < closestDistanceNormL2) {
        closestDistanceNormL2 = normL2Distance;
      }

      if (closestDistanceCosine >= 0.38 && closestDistanceNormL2 <= 1.12) {
        closestGroup = group;
      }
    }

    return closestGroup;
  }

  static (double cosineDistance, double normL2Distance) _calculateDistance(
      List<double> feature1,
      List<double> feature2,
      cv.FaceRecognizerSF recognizer) {
    final mat1 =
        cv.Mat.fromList(1, feature1.length, cv.MatType.CV_32FC1, feature1);
    final mat2 =
        cv.Mat.fromList(1, feature2.length, cv.MatType.CV_32FC1, feature2);

    final cosineDistance =
        recognizer.match(mat1, mat2, disType: cv.FaceRecognizerSF.FR_COSINE);
    final normL2Distance =
        recognizer.match(mat1, mat2, disType: cv.FaceRecognizerSF.FR_NORM_L2);

    mat1.dispose();
    mat2.dispose();

    return (cosineDistance, normL2Distance);
  }

  static Future<void> _mergeGroupsIsolate(_MergeGroupsParams params) async {
    final mergedGroups =
        _mergeSimilarGroups(params.groupedFaceGroups, params.tmpModelPath);
    params.sendPort.send(FinalGroupingCompleteMessage(mergedGroups));
  }

  static List<List<FaceGroup>> _mergeSimilarGroups(
      List<List<FaceGroup>> groupedFaceGroups, String tmpModelPath) {
    final mergedGroups = <List<FaceGroup>>[];
    var groupsToProcess = groupedFaceGroups.toList();

    while (groupsToProcess.isNotEmpty) {
      var group = groupsToProcess.removeLast();
      var matchingGroup = _findClosestGroup(
        mergedGroups.toSet(),
        _computeAverageFeature(
          group.map((face) => face.faceFeature).toList(),
        ),
        cv.FaceRecognizerSF.fromFile(tmpModelPath, ""),
      );

      if (matchingGroup != null) {
        matchingGroup.addAll(group);
      } else {
        mergedGroups.add(group);
      }
    }

    return mergedGroups;
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
}

class _ExtractionManager {
  final int numberOfIsolates;
  final int totalFaces;
  final List<double> progressMap;
  final List<int> processedFacesMap;
  final Map<Uint8List, List<double>> faceFeatures = {};
  final Map<Uint8List, Map<String, dynamic>> faceInfoMap = {};
  int completedIsolates = 0;

  _ExtractionManager(this.numberOfIsolates, this.totalFaces)
      : progressMap = List.filled(numberOfIsolates, 0.0),
        processedFacesMap = List.filled(numberOfIsolates, 0);

  void updateProgress(ProgressMessage message) {
    progressMap[message.isolateIndex] = message.progress;
    processedFacesMap[message.isolateIndex] = message.processed;
  }

  void addFeatures(Map<Uint8List, List<double>> features,
      Map<Uint8List, Map<String, dynamic>> info) {
    faceFeatures.addAll(features);
    faceInfoMap.addAll(info);
    completedIsolates++;
  }

  bool get isComplete => completedIsolates == numberOfIsolates;

  double get overallProgress =>
      progressMap.reduce((a, b) => a + b) / numberOfIsolates;

  int get overallProcessedFaces => processedFacesMap.reduce((a, b) => a + b);
}

class _GroupingManager {
  final int numberOfIsolates;
  final List<double> progressMap;
  final List<int> processedFacesMap;
  final List<List<FaceGroup>> groupedFaceGroups = [];
  int completedIsolates = 0;
  SendPort? sendPort;

  _GroupingManager(this.numberOfIsolates)
      : progressMap = List.filled(numberOfIsolates, 0.0),
        processedFacesMap = List.filled(numberOfIsolates, 0);

  void updateProgress(ProgressMessage message) {
    progressMap[message.isolateIndex] = message.progress;
    processedFacesMap[message.isolateIndex] = message.processed;
  }

  void addGroups(List<List<FaceGroup>> groups) {
    groupedFaceGroups.addAll(groups);
    completedIsolates++;
  }

  bool get isComplete => completedIsolates == numberOfIsolates;

  double get overallProgress =>
      progressMap.reduce((a, b) => a + b) / numberOfIsolates;

  int get overallProcessedFaces => processedFacesMap.reduce((a, b) => a + b);
}

enum ProcessingPhase { featureExtraction, grouping }

class _ProcessFacesParams {
  final List<Map<String, dynamic>> imagePaths;
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex;

  _ProcessFacesParams(
      this.imagePaths, this.sendPort, this.modelPath, this.isolateIndex);
}

class _GroupFacesParams {
  final String tmpModelPath;
  final Map<Uint8List, List<double>> faceFeatures;
  final Map<Uint8List, Map<String, dynamic>> faceInfoMap;
  final SendPort sendPort;
  final int totalFaces;
  final int isolateIndex;

  _GroupFacesParams({
    required this.tmpModelPath,
    required this.faceFeatures,
    required this.faceInfoMap,
    required this.sendPort,
    required this.totalFaces,
    required this.isolateIndex,
  });
}

class _MergeGroupsParams {
  final List<List<FaceGroup>> groupedFaceGroups;
  final String tmpModelPath;
  final SendPort sendPort;

  _MergeGroupsParams(this.groupedFaceGroups, this.tmpModelPath, this.sendPort);
}

class ProgressMessage {
  final double progress;
  final int processed;
  final int total;
  final int isolateIndex;
  final ProcessingPhase phase;

  ProgressMessage(
      this.progress, this.processed, this.total, this.isolateIndex, this.phase);
}

class ExtractionCompleteMessage {
  final int isolateIndex;
  final Map<Uint8List, List<double>> faceFeatures;
  final Map<Uint8List, Map<String, dynamic>> faceInfoMap;

  ExtractionCompleteMessage(
      this.isolateIndex, this.faceFeatures, this.faceInfoMap);
}

class GroupingProgressMessage {
  final double progress;
  final int processed;
  final int isolateIndex;

  GroupingProgressMessage(this.progress, this.processed, this.isolateIndex);
}

class GroupingCompleteMessage {
  final List<List<FaceGroup>> faceGroups;

  GroupingCompleteMessage(this.faceGroups);
}

class FinalGroupingCompleteMessage {
  final List<List<FaceGroup>> mergedFaceGroups;

  FinalGroupingCompleteMessage(this.mergedFaceGroups);
}
