import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:collection';

import 'package:face_grouping/models/image_data.dart';
import 'package:face_grouping/models/sendable_rect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import '../models/face_group.dart';

enum ProcessingPhase { featureExtraction, grouping, merging }

// Messages for Isolate Communication
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
  final Map<Uint8List, FaceInfo> faceInfoMap; // Use FaceInfo instead of Map

  ExtractionCompleteMessage(
      this.isolateIndex, this.faceFeatures, this.faceInfoMap);
}

class GroupingProgressMessage extends ProgressMessage {
  GroupingProgressMessage(double progress, int processed, int isolateIndex)
      : super(progress, processed, 0, isolateIndex, ProcessingPhase.grouping);
}

class GroupingProgress {
  final double progress;
  final String message;
  final int processed;
  final int total;

  GroupingProgress(this.progress, this.message, this.processed, this.total);
}

class GroupingCompleteMessage {
  final List<List<FaceGroup>> faceGroups;

  GroupingCompleteMessage(this.faceGroups);
}

class FinalGroupingCompleteMessage {
  final List<List<FaceGroup>> mergedFaceGroups;

  FinalGroupingCompleteMessage(this.mergedFaceGroups);
}

// Input parameters for Isolates

class _ProcessFacesParams {
  final List<FaceRectInfo> faceRectInfos; // Optimized data structure
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex;

  _ProcessFacesParams(
      this.faceRectInfos, this.sendPort, this.modelPath, this.isolateIndex);
}

class _GroupFacesParams {
  final String tmpModelPath;
  final Map<Uint8List, List<double>> faceFeatures;
  final Map<Uint8List, FaceInfo> faceInfoMap; // Use FaceInfo
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
  final SendPort progressSendPort; // Port for sending progress

  _MergeGroupsParams(this.groupedFaceGroups, this.tmpModelPath, this.sendPort,
      this.progressSendPort);
}

class FaceInfo {
  final String originalImagePath;
  final SendableRect rect;

  FaceInfo({required this.originalImagePath, required this.rect});
}

// Optimized data structure
class FaceRectInfo {
  final String imagePath;
  final SendableRect rect;

  FaceRectInfo({required this.imagePath, required this.rect});
}

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

  int _calculateOptimalIsolates(List<ImageData> images) {
    final totalFaces = images.fold<int>(
        0, (sum, image) => sum + image.sendableFaceRects.length);
    return totalFaces < 7 ? 1 : 7;
  }

  List<FaceRectInfo> _prepareAllRects(List<ImageData> images) {
    // Return List<FaceRectInfo>
    return images
        .expand((image) => image.sendableFaceRects
            .map((rect) => FaceRectInfo(imagePath: image.path, rect: rect)))
        .toList();
  }

  Future<void> groupSimilarFaces(
    List<ImageData> images,
    void Function(double, String, int, int, Duration) progressCallback,
    void Function(List<List<FaceGroup>>) completionCallback,
  ) async {
    final startTime = DateTime.now();

    // Prepare data and isolates
    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");
    final allRects = _prepareAllRects(images);
    final numberOfIsolates = _calculateOptimalIsolates(images);
    final batchSize = (allRects.length / numberOfIsolates).ceil();

    // Managers for tracking progress
    final extractionManager =
        _ExtractionManager(numberOfIsolates, allRects.length);
    final groupingManager = _GroupingManager(numberOfIsolates);

    final receivePort = ReceivePort();
    final completer = Completer<void>();

    // Spawn Feature Extraction Isolates
    _spawnExtractionIsolates(allRects, batchSize, tmpModelPath,
        receivePort.sendPort, numberOfIsolates);

    receivePort.listen((message) async {
      if (message is ProgressMessage) {
        _handleProgressMessage(message, extractionManager, groupingManager,
            startTime, progressCallback);
      } else if (message is ExtractionCompleteMessage) {
        await _handleExtractionComplete(message, extractionManager,
            groupingManager, tmpModelPath, receivePort.sendPort);
      } else if (message is GroupingProgressMessage) {
        _handleGroupingProgressMessage(
          message,
          groupingManager,
          startTime,
          progressCallback,
        ); // New function for handling grouping progress
      } else if (message is GroupingCompleteMessage) {
        _handleGroupingComplete(
            message,
            groupingManager,
            tmpModelPath,
            receivePort.sendPort,
            startTime,
            progressCallback); // Modified to include progress callback
      } else if (message is FinalGroupingCompleteMessage) {
        _handleFinalGroupingComplete(
            message, completionCallback, completer, receivePort);
      }
    });

    return completer.future;
  }

  void _spawnExtractionIsolates(
      List<FaceRectInfo> allRects, // Use FaceRectInfo
      int batchSize,
      String tmpModelPath,
      SendPort sendPort,
      int numberOfIsolates) {
    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize,
          allRects.length); // Use min to avoid exceeding bounds
      final batch = allRects.sublist(start, end);

      if (batch.isNotEmpty) {
        // Check if batch is not empty
        Isolate.spawn(
          _extractFeaturesIsolate,
          _ProcessFacesParams(batch, sendPort, tmpModelPath, i),
        );
      }
    }
  }

  void _handleProgressMessage(
      //handles extraction progress messages
      ProgressMessage message,
      _ExtractionManager extractionManager,
      _GroupingManager groupingManager,
      DateTime startTime,
      void Function(double, String, int, int, Duration) progressCallback) {
    if (message.phase == ProcessingPhase.featureExtraction) {
      extractionManager.updateProgress(message);
    } else {
      // Grouping or Merging
      groupingManager.updateProgress(message);
    }

    final overallProgress =
        (extractionManager.overallProgress + groupingManager.overallProgress) /
            2;
    final elapsed = DateTime.now().difference(startTime);
    final estimatedTotalTime = elapsed * (1 / overallProgress);
    final remainingTime = estimatedTotalTime - elapsed;

    progressCallback(
        overallProgress,
        message.phase == ProcessingPhase.featureExtraction
            ? "Extracting features"
            : message.phase == ProcessingPhase.grouping
                ? "Grouping faces"
                : "Merging groups",
        message.processed,
        message.total,
        remainingTime);
  }

  Future<void> _handleExtractionComplete(
      ExtractionCompleteMessage message,
      _ExtractionManager extractionManager,
      _GroupingManager groupingManager,
      String tmpModelPath,
      SendPort sendPort) async {
    extractionManager.addFeatures(message.faceFeatures, message.faceInfoMap);

    if (extractionManager.isComplete) {
      await _startGrouping(
          extractionManager.faceFeatures,
          extractionManager.faceInfoMap, // Pass faceInfoMap
          tmpModelPath,
          sendPort,
          groupingManager.numberOfIsolates);
    }
  }

  Future<void> _startGrouping(
      Map<Uint8List, List<double>> faceFeatures,
      Map<Uint8List, FaceInfo> faceInfoMap, // Use FaceInfo
      String tmpModelPath,
      SendPort sendPort,
      int numberOfIsolates) async {
    final faceEntries = faceFeatures.entries.toList();
    final groupingBatchSize = (faceFeatures.length / numberOfIsolates).ceil();

    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * groupingBatchSize;
      final end =
          min((i + 1) * groupingBatchSize, faceFeatures.length); // Use min
      final batch = faceEntries.sublist(start, end);

      if (batch.isNotEmpty) {
        // Check for empty batch
        final batchFeatures = Map<Uint8List, List<double>>.fromEntries(batch);
        final batchInfo = Map<Uint8List, FaceInfo>.fromEntries(
            batch.map((e) => MapEntry(e.key, faceInfoMap[e.key]!)));

        Isolate.spawn(
            _groupFacesIsolate,
            _GroupFacesParams(
              tmpModelPath: tmpModelPath,
              faceFeatures: batchFeatures,
              faceInfoMap: batchInfo, // Pass batchInfo
              sendPort: sendPort,
              totalFaces: batchFeatures.length,
              isolateIndex: i,
            ));
      }
    }
  }

  void _handleGroupingProgressMessage(
    // handles grouping progress from isolates
    GroupingProgressMessage message,
    _GroupingManager groupingManager,
    DateTime startTime,
    void Function(double, String, int, int, Duration) progressCallback,
  ) {
    groupingManager.updateProgress(message);

    final overallProgress = 0.5 +
        groupingManager.overallProgress *
            0.5; // Assuming feature extraction is complete
    final elapsed = DateTime.now().difference(startTime);
    final estimatedTotalTime = elapsed * (1 / overallProgress);
    final remainingTime = estimatedTotalTime - elapsed;

    progressCallback(
        overallProgress,
        "Grouping faces in isolate ${message.isolateIndex}",
        message.processed,
        message
            .total, // Total is not relevant here, you could pass the total number of faces being processed by this isolate
        remainingTime);
  }

  void _handleGroupingComplete(
      GroupingCompleteMessage message,
      _GroupingManager groupingManager,
      String tmpModelPath,
      SendPort sendPort,
      DateTime startTime,
      void Function(double, String, int, int, Duration) progressCallback) {
    groupingManager.addGroups(message.faceGroups);

    if (groupingManager.isComplete) {
      _startMerging(groupingManager.groupedFaceGroups, tmpModelPath, sendPort,
          startTime, progressCallback);
    }
  }

  void _startMerging(
      List<List<FaceGroup>> groupedFaceGroups,
      String tmpModelPath,
      SendPort sendPort,
      DateTime startTime,
      void Function(double, String, int, int, Duration) progressCallback) {
    final progressReceivePort = ReceivePort(); // New receive port for progress

    Isolate.spawn(
      _mergeGroupsIsolate,
      _MergeGroupsParams(groupedFaceGroups, tmpModelPath, sendPort,
          progressReceivePort.sendPort),
    );

    progressReceivePort.listen((message) {
      if (message is GroupingProgress) {
        // Handle progress updates
        progressCallback(
            message.progress,
            message.message,
            message.processed,
            message.total,
            Duration.zero); // Or calculate approximate remaining time
      }
    });
  }

  void _handleFinalGroupingComplete(
      FinalGroupingCompleteMessage message,
      void Function(List<List<FaceGroup>>) completionCallback,
      Completer<void> completer,
      ReceivePort receivePort) {
    completionCallback(message.mergedFaceGroups);
    completer.complete();
    receivePort.close();
  }

  static Future<void> _extractFeaturesIsolate(
      _ProcessFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(params.modelPath, "");
    final faceFeatures = <Uint8List, List<double>>{};
    final faceInfoMap = <Uint8List, FaceInfo>{}; // Use FaceInfo

    for (var (index, faceRectInfo) in params.faceRectInfos.indexed) {
      // Iterate using indexed
      final mat = cv.imread(faceRectInfo.imagePath, flags: cv.IMREAD_COLOR);
      final rect = faceRectInfo.rect;

      final faceBox = cv.Mat.fromList(
          1, rect.rawDetection.length, cv.MatType.CV_32FC1, rect.rawDetection);

      try {
        // Handle potential exceptions during alignment and feature extraction
        final alignedFace = recognizer.alignCrop(mat, faceBox);
        final feature = recognizer.feature(alignedFace);
        final (_, encodedFace) = cv.imencode('.jpg', alignedFace);

        faceFeatures[encodedFace] = List<double>.generate(
            feature.width, (index) => feature.at<double>(0, index));
        faceInfoMap[encodedFace] =
            FaceInfo(originalImagePath: rect.originalImagePath, rect: rect);
        alignedFace.dispose();
      } catch (e) {
        print("Error processing face: $e"); // Log the error
      } finally {
        faceBox.dispose();
        mat.dispose();
      }

      params.sendPort.send(ProgressMessage(
          (index + 1) / params.faceRectInfos.length,
          index + 1,
          params.faceRectInfos.length,
          params.isolateIndex,
          ProcessingPhase.featureExtraction));
    }

    recognizer.dispose();
    params.sendPort.send(ExtractionCompleteMessage(
        params.isolateIndex, faceFeatures, faceInfoMap)); // Send faceInfoMap
  }

  static Future<void> _groupFacesIsolate(_GroupFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(params.tmpModelPath, "");
    final faceGroups = HashSet<List<FaceGroup>>(); // Use HashSet

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
          originalImagePath: params.faceInfoMap[faceImage]!.originalImagePath,
          rect: params.faceInfoMap[faceImage]!.rect,
          faceFeature: faceFeature,
        ));
      } else {
        faceGroups.add([
          FaceGroup(
            faceImage: faceImage,
            originalImagePath: params.faceInfoMap[faceImage]!.originalImagePath,
            rect: params.faceInfoMap[faceImage]!.rect,
            faceFeature: faceFeature,
          )
        ]);
      }

      params.sendPort.send(GroupingProgressMessage(
          (index + 1) / params.totalFaces, index + 1, params.isolateIndex));
    }

    recognizer.dispose();
    params.sendPort.send(GroupingCompleteMessage(faceGroups.toList()));
  }

  static List<FaceGroup>? _findClosestGroup(Set<List<FaceGroup>> faceGroups,
      List<double> faceFeature, cv.FaceRecognizerSF recognizer) {
    List<FaceGroup>? closestGroup;
    double minDistance = double.infinity;

    for (var group in faceGroups) {
      final averageFeature = _computeAverageFeature(
          group.map((face) => face.faceFeature).toList());
      final distance =
          _calculateDistance(faceFeature, averageFeature, recognizer);

      if (distance < minDistance) {
        minDistance = distance;
        closestGroup = group;
      }
    }

    // Adjust threshold as needed
    if (minDistance > 1.12) {
      // Example threshold - adjust as needed
      return null; // No close group found
    }

    return closestGroup;
  }

  static double _calculateDistance(List<double> feature1, List<double> feature2,
      cv.FaceRecognizerSF recognizer) {
    final mat1 =
        cv.Mat.fromList(1, feature1.length, cv.MatType.CV_32FC1, feature1);
    final mat2 =
        cv.Mat.fromList(1, feature2.length, cv.MatType.CV_32FC1, feature2);

    final normL2Distance =
        recognizer.match(mat1, mat2, disType: cv.FaceRecognizerSF.FR_NORM_L2);
    mat1.dispose();
    mat2.dispose();

    return normL2Distance;
  }

  static Future<void> _mergeGroupsIsolate(_MergeGroupsParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(params.tmpModelPath, "");
    final mergedGroups = <List<FaceGroup>>[];
    var numGroupsMerged = 0;

    for (var i = 0; i < params.groupedFaceGroups.length; i++) {
      var group1 = params.groupedFaceGroups[i];
      var merged = false;

      for (var j = 0; j < mergedGroups.length; j++) {
        var group2 = mergedGroups[j];

        final averageFeature1 = _computeAverageFeature(
            group1.map((face) => face.faceFeature).toList());
        final averageFeature2 = _computeAverageFeature(
            group2.map((face) => face.faceFeature).toList());

        final distance =
            _calculateDistance(averageFeature1, averageFeature2, recognizer);

        if (distance < 1.12) {
          // Example Threshold - Adjust as needed
          mergedGroups[j].addAll(group1);
          merged = true;
          numGroupsMerged++;
          break; // Exit inner loop after merging
        }
      }
      if (!merged) {
        mergedGroups.add(group1);
      }
      final progress = (i + 1) / params.groupedFaceGroups.length;
      params.progressSendPort.send(GroupingProgress(progress, "Merging Groups",
          i + 1, params.groupedFaceGroups.length)); // Send progress update
    }
    recognizer.dispose();
    params.sendPort.send(FinalGroupingCompleteMessage(mergedGroups));
  }

  static int _compareFeatures(List<double> a, List<double> b) {
    // Optimized comparison using sum of features
    final aSum = a.reduce((value, element) => value + element);
    final bSum = b.reduce((value, element) => value + element);
    return aSum.compareTo(bSum);
  }

  static List<double> _computeAverageFeature(List<List<double>> features) {
    // Optimized average feature calculation
    final featureLength = features[0].length;
    final avgFeature = List<double>.filled(featureLength, 0.0);
    for (var feature in features) {
      for (var i = 0; i < featureLength; i++) {
        avgFeature[i] += feature[i];
      }
    }
    for (var i = 0; i < featureLength; i++) {
      avgFeature[i] /= features.length;
    }
    return avgFeature;
  }
}

class _ExtractionManager {
  final int numberOfIsolates;
  final int totalFaces;
  final List<double> progressMap;
  final Map<Uint8List, List<double>> faceFeatures = {};
  final Map<Uint8List, FaceInfo> faceInfoMap = {}; // Use FaceInfo
  int completedIsolates = 0;

  _ExtractionManager(this.numberOfIsolates, this.totalFaces)
      : progressMap = List.filled(numberOfIsolates, 0.0);

  void updateProgress(ProgressMessage message) {
    progressMap[message.isolateIndex] = message.progress;
  }

  void addFeatures(
      Map<Uint8List, List<double>> features, Map<Uint8List, FaceInfo> info) {
    faceFeatures.addAll(features);
    faceInfoMap.addAll(info);
    completedIsolates++;
  }

  bool get isComplete => completedIsolates == numberOfIsolates;
  double get overallProgress =>
      progressMap.reduce((a, b) => a + b) / numberOfIsolates;
}

class _GroupingManager {
  final int numberOfIsolates;
  final List<double> progressMap;
  final List<List<FaceGroup>> groupedFaceGroups = [];
  int completedIsolates = 0;

  _GroupingManager(this.numberOfIsolates)
      : progressMap = List.filled(numberOfIsolates, 0.0);

  void updateProgress(ProgressMessage message) {
    progressMap[message.isolateIndex] = message.progress;
  }

  void addGroups(List<List<FaceGroup>> groups) {
    groupedFaceGroups.addAll(groups);
    completedIsolates++;
  }

  bool get isComplete => completedIsolates == numberOfIsolates;
  double get overallProgress =>
      progressMap.reduce((a, b) => a + b) / numberOfIsolates;
}
