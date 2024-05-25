import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

  Future<List<ImageData>> processDirectory(String directoryPath, void Function(double) progressCallback) async {
    final completer = Completer<List<ImageData>>();
    final receivePort = ReceivePort();

    Isolate.spawn(_processDirectoryIsolate, _ProcessDirectoryParams(directoryPath, receivePort.sendPort, _haarcascadesPath!));

    receivePort.listen((message) {
      if (message is double) {
        progressCallback(message);
      } else if (message is List<ImageData>) {
        completer.complete(message);
        receivePort.close();
      }
    });

    return completer.future;
  }

  static Future<void> _processDirectoryIsolate(_ProcessDirectoryParams params) async {
    final images = <ImageData>[];
    final dir = Directory(params.directoryPath);
    final entities = await dir.list(recursive: true).toList();
    final imageFiles = entities.where((entity) => entity is File && _isImageFile(entity.path)).toList();

    for (var i = 0; i < imageFiles.length; i++) {
      final entity = imageFiles[i] as File;
      final faceRects = await _detectFaces(entity.path, params.haarcascadesPath);
      images.add(ImageData(path: entity.path, faceCount: faceRects.length));
      params.sendPort.send((i + 1) / imageFiles.length);
    }

    params.sendPort.send(images);
  }

  static bool _isImageFile(String path) {
    return ['.jpg', '.jpeg', '.png', '.bmp']
        .any((ext) => path.toLowerCase().endsWith(ext));
  }

  static Future<cv.VecRect> _detectFaces(String imagePath, String haarcascadesPath) async {
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    final classifier = cv.CascadeClassifier.empty();
    classifier.load(haarcascadesPath);
    final rects = classifier.detectMultiScale(img);
    return rects;
  }

  Future<List<Uint8List>> extractFaces(String imagePath, cv.VecRect faceRects) async {
    final completer = Completer<List<Uint8List>>();
    final receivePort = ReceivePort();

    Isolate.spawn(_extractFacesIsolate, _ExtractFacesParams(imagePath, faceRects, receivePort.sendPort));

    receivePort.listen((message) {
      if (message is List<Uint8List>) {
        completer.complete(message);
        receivePort.close();
      }
    });

    return completer.future;
  }

  static Future<void> _extractFacesIsolate(_ExtractFacesParams params) async {
    final img = cv.imread(params.imagePath, flags: cv.IMREAD_COLOR);
    final faceImages = <Uint8List>[];

    for (var i = 0; i < params.faceRects.length; i++) {
      final faceRect = params.faceRects.elementAt(i);
      final face = img.region(faceRect);
      faceImages.add(cv.imencode('.jpg', face));
    }

    params.sendPort.send(faceImages);
  }
}

class _ProcessDirectoryParams {
  final String directoryPath;
  final SendPort sendPort;
  final String haarcascadesPath;

  _ProcessDirectoryParams(this.directoryPath, this.sendPort, this.haarcascadesPath);
}

class _ExtractFacesParams {
  final String imagePath;
  final cv.VecRect faceRects;
  final SendPort sendPort;

  _ExtractFacesParams(this.imagePath, this.faceRects, this.sendPort);
}
