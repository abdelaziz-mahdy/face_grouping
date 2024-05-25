import 'dart:io';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageData {
  final String path;
  final int faceCount;

  ImageData({required this.path, required this.faceCount});
}

class ImageService {
  ImageService._privateConstructor();
  static final ImageService instance = ImageService._privateConstructor();

  factory ImageService() {
    return instance;
  }

  Future<List<ImageData>> processDirectory(String directoryPath) async {
    List<ImageData> images = [];
    await for (var entity in Directory(directoryPath).list(recursive: true)) {
      if (entity is File && _isImageFile(entity.path)) {
        final faceRects = await detectFaces(entity.path);
        images.add(ImageData(path: entity.path, faceCount: faceRects.length));
      }
    }
    return images;
  }

  bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }

  Future<void> _copyAssetFileToTmp(String assetPath, String tmpPath) async {
    final byteData = await rootBundle.load(assetPath);
    final file = File(tmpPath);
    await file.writeAsBytes(byteData.buffer.asUint8List());
  }

  Future<cv.VecRect> detectFaces(String imagePath) async {
    final tmpDir = await getTemporaryDirectory();
    final haarcascadesPath =
        '${tmpDir.path}/haarcascade_frontalface_default.xml';

    await _copyAssetFileToTmp(
        'assets/haarcascade_frontalface_default.xml', haarcascadesPath);

    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    final classifier = cv.CascadeClassifier.empty();
    classifier.load(haarcascadesPath);
    final rects = classifier.detectMultiScale(img);
    return rects;
  }

  Future<List<Uint8List>> extractFaces(
      String imagePath, cv.VecRect faceRects) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    List<Uint8List> faceImages = [];

    for (var i = 0; i < faceRects.length; i++) {
      final faceRect = faceRects.elementAt(i);

      final face = img.region(faceRect);

      faceImages.add(cv.imencode('.jpg', face));
    }

    return faceImages;
  }
}
