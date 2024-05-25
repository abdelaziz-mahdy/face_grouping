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

  bool _xmlLoaded = false;
  String? _haarcascadesPath;

  Future<void> _loadXml() async {
    if (!_xmlLoaded) {
      final tmpDir = await getTemporaryDirectory();
      _haarcascadesPath = '${tmpDir.path}/haarcascade_frontalface_default.xml';

      await _copyAssetFileToTmp(
          'assets/haarcascade_frontalface_default.xml', _haarcascadesPath!);
      _xmlLoaded = true;
    }
  }

  Future<void> _copyAssetFileToTmp(String assetPath, String tmpPath) async {
    final byteData = await rootBundle.load(assetPath);
    final file = File(tmpPath);
    await file.writeAsBytes(byteData.buffer.asUint8List());
  }

  Future<cv.VecRect> detectFaces(String imagePath) async {
    await _loadXml();

    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    final classifier = cv.CascadeClassifier.empty();
    classifier.load(_haarcascadesPath!);
    final rects = classifier.detectMultiScale(img);
    return rects;
  }

  Future<List<Uint8List>> extractFaces(String imagePath, cv.VecRect faceRects) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    List<Uint8List> faceImages = [];

    for (var i = 0; i < faceRects.length; i++) {
      final faceRect = faceRects.elementAt(i);
      final face = img.region(faceRect);
      faceImages.add(cv.imencode('.jpg', face));
    }

    return faceImages;
  }

  Future<List<ImageData>> processDirectory(String directoryPath, void Function(double) progressCallback) async {
    List<ImageData> images = [];
    final dir = Directory(directoryPath);
    final entities = await dir.list(recursive: true).toList();
    final imageFiles = entities.where((entity) => entity is File && _isImageFile(entity.path)).toList();

    for (var i = 0; i < imageFiles.length; i++) {
      final entity = imageFiles[i] as File;
      final faceRects = await detectFaces(entity.path);
      images.add(ImageData(path: entity.path, faceCount: faceRects.length));
      progressCallback((i + 1) / imageFiles.length);
    }
    return images;
  }

  bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }
}
