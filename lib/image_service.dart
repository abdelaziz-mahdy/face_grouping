// lib/image_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'isolate_utils.dart';

class SendableRect {
  final int x, y, width, height;
  final List<double> rawDetection;
  final String originalImagePath;

  SendableRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rawDetection,
    required this.originalImagePath,
  });

  cv.Rect toRect() {
    return cv.Rect(x, y, width, height);
  }

  static SendableRect fromRect(cv.Rect rect, List<double> rawDetection, String originalImagePath) {
    return SendableRect(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      rawDetection: rawDetection,
      originalImagePath: originalImagePath,
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
    int numberOfIsolates = 6,
  }) async {
    final tmpModelPath = await _copyAssetFileToTmp("assets/face_detection_yunet_2023mar.onnx");
    final directory = Directory(directoryPath);
    final entities = await directory.list(recursive: true).toList();
    final imageFiles = entities.where((entity) => entity is File && _isImageFile(entity.path)).toList();
    final totalImages = imageFiles.length;

    final results = await IsolateUtils.runIsolate<String, ImageData>(
      data: imageFiles.map((e) => e.path).toList(),
      numberOfIsolates: numberOfIsolates,
      isolateEntryPoint: (data, sendPort) => _processDirectoryIsolate(data, sendPort, tmpModelPath),
      progressCallback: (progress, processed, total, remaining) => progressCallback(progress, remaining, processed, total),
      completionCallback: (results) {},
    );

    return results;
  }

  static Future<void> _processDirectoryIsolate(
    List<String> imagePaths,
    SendPort sendPort,
    String modelPath,
  ) async {
    final images = <ImageData>[];
    final modelFile = File(modelPath);
    final buf = await modelFile.readAsBytes();
    final faceDetector = cv.FaceDetectorYN.fromBuffer(
      "onnx",
      buf,
      Uint8List(0),
      (320, 320),
      backendId: cv.DNN_BACKEND_OPENCV,
      targetId: cv.DNN_TARGET_OPENCL,
    );

    final totalImages = imagePaths.length;

    for (var i = 0; i < totalImages; i++) {
      final imagePath = imagePaths[i];
      final sendableRects = _detectFaces(imagePath, faceDetector);

      images.add(ImageData(
        path: imagePath,
        faceCount: sendableRects.length,
        sendableFaceRects: sendableRects,
      ));

      final progress = (i + 1) / totalImages;
      sendPort.send(ProgressMessage(
        progress,
        i + 1,
        totalImages,
        0, // Isolate index is not needed in this context
      ));
    }

    sendPort.send(images);
    faceDetector.dispose();
  }

  static bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp'].any((ext) => path.toLowerCase().endsWith(ext));
  }

  static List<SendableRect> _detectFaces(String imagePath, cv.FaceDetectorYN detector) {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    detector.setInputSize((img.width, img.height));
    final faces = detector.detect(img);
    final returnValue = List.generate(faces.rows, (i) {
      final x = faces.at<double>(i, 0).toInt();
      final y = faces.at<double>(i, 1).toInt();
      final width = faces.at<double>(i, 2).toInt();
      final height = faces.at<double>(i, 3).toInt();
      final correctedWidth = (x + width) > img.width ? img.width - x : width;
      final correctedHeight = (y + height) > img.height ? img.height - y : height;
      final rawDetection = List.generate(faces.width, (index) => faces.at<double>(i, index));

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

class ProgressMessage {
  final double progress;
  final int processed;
  final int total;
  final int isolateIndex;

  ProgressMessage(this.progress, this.processed, this.total, this.isolateIndex);
}
