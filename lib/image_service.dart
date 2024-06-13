import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

class SendableRect {
  final int x, y, width, height;
  final List<double> rawDetection;

  SendableRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rawDetection,
  });

  cv.Rect toRect() {
    return cv.Rect(x, y, width, height);
  }

  static SendableRect fromRect(cv.Rect rect, List<double> rawDetection) {
    return SendableRect(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      rawDetection: rawDetection,
    );
  }
}

class ImageData {
  final String path;
  final int faceCount;
  final List<SendableRect> sendableFaceRects;

  ImageData({
    required this.path,
    required this.faceCount,
    required this.sendableFaceRects,
  });

  List<cv.Rect> get faceRects {
    return sendableFaceRects.map((r) => r.toRect()).toList();
  }
}

class ImageService {
  ImageService._privateConstructor();

  static final ImageService instance = ImageService._privateConstructor();

  factory ImageService() {
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

  Future<List<ImageData>> processDirectory(
    String directoryPath,
    void Function(double, Duration, int, int) progressCallback, {
    int? numberOfIsolates = 5, // Default to the number of CPU cores
  }) async {
    final completer = Completer<List<ImageData>>();
    final receivePort = ReceivePort();
    final startTime = DateTime.now();
    final _numberOfIsolates =
        numberOfIsolates ?? (Platform.numberOfProcessors - 2);
    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_detection_yunet_2023mar.onnx");

    final dir = Directory(directoryPath);
    final entities = await dir.list(recursive: true).toList();
    final imageFiles = entities
        .where((entity) => entity is File && _isImageFile(entity.path))
        .toList();

    final totalImages = imageFiles.length;
    final batchSize = (totalImages / _numberOfIsolates).ceil();
    final results = <ImageData>[];
    final progressMap =
        List.filled(_numberOfIsolates, 0.0); // Track progress of each isolate
    final processedImagesMap = List.filled(
        _numberOfIsolates, 0); // Track processed count for each isolate
    int overallProcessedImages =
        0; // Total processed images across all isolates

    for (var i = 0; i < _numberOfIsolates; i++) {
      final start = i * batchSize;
      final end =
          (i + 1) * batchSize > totalImages ? totalImages : (i + 1) * batchSize;
      final batch = imageFiles.sublist(start, end);

      if (batch.isEmpty) continue; // Skip empty batches

      Isolate.spawn(
        _processDirectoryIsolate,
        _ProcessDirectoryParams(
          batch.map((file) => file.path).toList(),
          receivePort.sendPort,
          tmpModelPath,
          i, // Isolate index
          totalImages,
        ),
      );
    }

    receivePort.listen((message) {
      print("GOT ${message}");
      if (message is ProgressMessage) {
        progressMap[message.isolateIndex] =
            message.progress; // Update progress for the specific isolate
        processedImagesMap[message.isolateIndex] = message
            .processed; // Update processed count for the specific isolate

        // Calculate overall progress
        final overallProgress =
            progressMap.reduce((a, b) => a + b) / _numberOfIsolates;

        // Calculate the total processed images across all isolates
        overallProcessedImages = processedImagesMap.reduce((a, b) => a + b);

        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / overallProgress);
        final remainingTime = estimatedTotalTime - elapsed;

        progressCallback(
          overallProgress,
          remainingTime,
          overallProcessedImages,
          totalImages,
        );
      } else if (message is List<ImageData>) {
        results.addAll(message);
        if (results.length == totalImages) {
          completer.complete(results);
          receivePort.close();
        }
      }
    });

    return completer.future;
  }

  static Future<void> _processDirectoryIsolate(
      _ProcessDirectoryParams params) async {
    final images = <ImageData>[];
    final modelFile = File(params.modelPath);
    final buf = await modelFile.readAsBytes();
    final faceDetector =
        cv.FaceDetectorYN.fromBuffer("onnx", buf, Uint8List(0), (320, 320));

    final totalImages = params.imagePaths.length;

    for (var i = 0; i < totalImages; i++) {
      final imagePath = params.imagePaths[i];
      final sendableRects = await _detectFaces(imagePath, faceDetector);

      images.add(ImageData(
        path: imagePath,
        faceCount: sendableRects.length,
        sendableFaceRects: sendableRects,
      ));

      final progress = (i + 1) / totalImages;
      params.sendPort.send(ProgressMessage(
        progress,
        i + 1,
        totalImages,
        params.isolateIndex, // Pass the isolate index for tracking
      ));
    }

    params.sendPort.send(images);
  }

  static bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }

  static Future<List<SendableRect>> _detectFaces(
      String imagePath, cv.FaceDetectorYN detector) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    detector.setInputSize((img.width, img.height));
    final faces = detector.detect(img);

    return List.generate(faces.rows, (i) {
      final x = faces.at<double>(i, 0).toInt();
      final y = faces.at<double>(i, 1).toInt();
      final width = faces.at<double>(i, 2).toInt();
      final height = faces.at<double>(i, 3).toInt();

      // Correct width if it exceeds image boundaries
      final correctedWidth = (x + width) > img.width ? img.width - x : width;

      // Correct height if it exceeds image boundaries
      final correctedHeight =
          (y + height) > img.height ? img.height - y : height;

      // Create the list of raw detection data
      final rawDetection = List.generate(
        faces.width,
        (index) => faces.at<double>(i, index),
      );

      return SendableRect(
        x: x,
        y: y,
        width: correctedWidth,
        height: correctedHeight,
        rawDetection: rawDetection,
      );
    });
  }
}

class _ProcessDirectoryParams {
  final List<String> imagePaths;
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex; // Index of the isolate
  final int total;

  _ProcessDirectoryParams(
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
  final int isolateIndex; // Index of the isolate

  ProgressMessage(this.progress, this.processed, this.total, this.isolateIndex);
}
