import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:face_grouping/models/image_data.dart';
import 'package:face_grouping/models/sendable_rect.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

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
    int numberOfIsolates = 7,
  }) async {
    final completer = Completer<List<ImageData>>();
    final receivePort = ReceivePort();
    final startTime = DateTime.now();
    var numberOfIsolates0 = numberOfIsolates;

    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_detection_yunet_2023mar.onnx");

    final dir = Directory(directoryPath);
    final entities = await dir.list(recursive: true).toList();
    final imageFiles = entities
        .where((entity) => entity is File && _isImageFile(entity.path))
        .toList();

    final totalImages = imageFiles.length;

    var batchSize = (totalImages / numberOfIsolates0).ceil();
    final results = <ImageData>[];
    final progressMap = List.filled(numberOfIsolates0, 0.0);
    final processedImagesMap = List.filled(numberOfIsolates0, 0);
    int overallProcessedImages = 0;
    if (totalImages <= numberOfIsolates0) {
      numberOfIsolates0 = 1;
      batchSize = totalImages;
    }
    for (var i = 0; i < numberOfIsolates0; i++) {
      final start = i * batchSize;
      final end =
          (i + 1) * batchSize > totalImages ? totalImages : (i + 1) * batchSize;
      final batch = imageFiles.sublist(start, end);

      if (batch.isEmpty) continue;

      Isolate.spawn(
        _processDirectoryIsolate,
        _ProcessDirectoryParams(
          batch.map((file) => file.path).toList(),
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
            progressMap.reduce((a, b) => a + b) / numberOfIsolates0;
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
    final faceDetector = cv.FaceDetectorYN.fromBuffer(
      "onnx",
      buf,
      Uint8List(0),
      (320, 320),
      // backendId: cv.DNN_BACKEND_VKCOM,
      // targetId: cv.DNN_TARGET_VULKAN,
    );

    final totalImages = params.imagePaths.length;

    for (var i = 0; i < totalImages; i++) {
      final imagePath = params.imagePaths[i];
      final sendableRects = _detectFaces(imagePath, faceDetector);

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
        params.isolateIndex,
      ));
    }

    params.sendPort.send(images);
    faceDetector.dispose();
  }

  static bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }

  static List<SendableRect> _detectFaces(
      String imagePath, cv.FaceDetectorYN detector) {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    detector.setInputSize((img.width, img.height));
    final faces = detector.detect(img);
    final returnValue = List.generate(faces.rows, (i) {
      final x = faces.at<double>(i, 0).toInt();
      final y = faces.at<double>(i, 1).toInt();
      final width = faces.at<double>(i, 2).toInt();
      final height = faces.at<double>(i, 3).toInt();
      final correctedWidth = (x + width) > img.width ? img.width - x : width;
      final correctedHeight =
          (y + height) > img.height ? img.height - y : height;
      final rawDetection =
          List.generate(faces.width, (index) => faces.at<double>(i, index));

      return SendableRect(
        x: x,
        y: y,
        width: correctedWidth,
        height: correctedHeight,
        rawDetection: rawDetection,
        originalImagePath: imagePath,
      );
    });

    return returnValue;
  }
}

class _ProcessDirectoryParams {
  final List<String> imagePaths;
  final SendPort sendPort;
  final String modelPath;
  final int isolateIndex;
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
  final int isolateIndex;

  ProgressMessage(this.progress, this.processed, this.total, this.isolateIndex);
}
