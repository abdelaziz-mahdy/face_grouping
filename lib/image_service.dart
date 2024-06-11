import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

class SendableRect {
  final int x, y, width, height;
  SendableRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  cv.Rect toRect() {
    return cv.Rect(x, y, width, height);
  }

  static SendableRect fromRect(cv.Rect rect) {
    return SendableRect(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    );
  }
}

class ImageData {
  final String path;
  final int faceCount;
  final List<SendableRect> sendableFaceRects;
  final List<Uint8List> faceImages;

  ImageData({
    required this.path,
    required this.faceCount,
    required this.sendableFaceRects,
    required this.faceImages,
  });

  List<cv.Rect> get faceRects {
    List<cv.Rect> rects = [];
    for (var sendableRect in sendableFaceRects) {
      rects.add(sendableRect.toRect());
    }
    return rects;
  }
}

class ImageService {
  ImageService._privateConstructor();
  static final ImageService instance = ImageService._privateConstructor();

  factory ImageService() {
    return instance;
  }
  
  Future<void> _copyAssetFileToTmp(String assetPath, String tmpPath) async {
    final byteData = await rootBundle.load(assetPath);
    final file = File(tmpPath);
    await file.writeAsBytes(byteData.buffer.asUint8List());
  }

  Future<List<ImageData>> processDirectory(String directoryPath,
      void Function(double, Duration, int, int) progressCallback) async {
    final completer = Completer<List<ImageData>>();
    final receivePort = ReceivePort();
    final startTime = DateTime.now();

    Isolate.spawn(_processDirectoryIsolate,
        _ProcessDirectoryParams(directoryPath, receivePort.sendPort));

    receivePort.listen((message) {
      if (message is _ProgressMessage) {
        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / message.progress);
        final remainingTime = estimatedTotalTime - elapsed;
        progressCallback(
            message.progress, remainingTime, message.processed, message.total);
      } else if (message is List<ImageData>) {
        completer.complete(message);
        receivePort.close();
      }
    });

    return completer.future;
  }

  static Future<void> _processDirectoryIsolate(
      _ProcessDirectoryParams params) async {
    final images = <ImageData>[];
    final dir = Directory(params.directoryPath);
    final entities = await dir.list(recursive: true).toList();
    final imageFiles = entities
        .where((entity) => entity is File && _isImageFile(entity.path))
        .toList();

    const modelPath = "assets/face_detection_yunet_2023mar.onnx";
    final buf = (await rootBundle.load(modelPath)).buffer.asUint8List();
    final faceDetector =
        cv.FaceDetectorYN.fromBuffer("onnx", buf, Uint8List(0), (320, 320));

    // Initialize FaceDetectorYN with required parameters.
    final totalImages = imageFiles.length;

    for (var i = 0; i < imageFiles.length; i++) {
      final entity = imageFiles[i] as File;
      final faceRects = await _detectFaces(entity.path, faceDetector);
      final sendableRects =
          faceRects.map((rect) => SendableRect.fromRect(rect)).toList();
      final faceImages = await _extractFaces(entity.path, sendableRects);

      images.add(ImageData(
        path: entity.path,
        faceCount: faceRects.length,
        sendableFaceRects: sendableRects,
        faceImages: faceImages,
      ));

      final progress = (i + 1) / totalImages;
      params.sendPort.send(_ProgressMessage(progress, i + 1, totalImages));
    }

    params.sendPort.send(images);
  }

  static bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }

  static Future<List<cv.Rect>> _detectFaces(
      String imagePath, cv.FaceDetectorYN detector) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    detector.setInputSize((img.width, img.height));
    final faces = detector.detect(img);
    return List.generate(faces.rows, (i) {
      return cv.Rect(
        faces.at<double>(i, 0).toInt(),
        faces.at<double>(i, 1).toInt(),
        faces.at<double>(i, 2).toInt(),
        faces.at<double>(i, 3).toInt(),
      );
    });
  }

  static Future<List<Uint8List>> _extractFaces(
      String imagePath, List<SendableRect> sendableRects) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    final faceImages = <Uint8List>[];

    for (var sendableRect in sendableRects) {
      final faceRect = sendableRect.toRect();
      final face = img.region(faceRect);
      faceImages.add(cv.imencode('.jpg', face));
    }

    return faceImages;
  }
}

class _ProcessDirectoryParams {
  final String directoryPath;
  final SendPort sendPort;

  _ProcessDirectoryParams(this.directoryPath, this.sendPort);
}

class _ProgressMessage {
  final double progress;
  final int processed;
  final int total;

  _ProgressMessage(this.progress, this.processed, this.total);
}
