import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'image_service.dart';

class FaceRecognitionService {
  FaceRecognitionService._privateConstructor();

  static final FaceRecognitionService instance = FaceRecognitionService._privateConstructor();

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
    void Function(double) progressCallback,
    void Function(List<List<Uint8List>>) completionCallback,
  ) async {
    final tmpModelPath = await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    final receivePort = ReceivePort();

    Isolate.spawn(
      _groupSimilarFacesIsolate,
      _GroupFacesParams(images, receivePort.sendPort, tmpModelPath),
    );

    receivePort.listen((message) {
      if (message is _ProgressMessage) {
        progressCallback(message.progress);
      } else if (message is List<List<Uint8List>>) {
        completionCallback(message);
        receivePort.close();
      }
    });
  }

  static Future<void> _groupSimilarFacesIsolate(_GroupFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.newRecognizer(params.modelPath, "", 0, 0);
    final faceFeatures = <Uint8List, cv.Mat>{};

    // Extract features for each face image
    for (var image in params.images) {
      for (var faceImage in image.faceImages) {
        final mat = cv.imdecode(faceImage,  cv.IMREAD_COLOR);
        final feature = recognizer.feature(mat);
        faceFeatures[faceImage] = feature;
      }
    }

    final faceGroups = <List<Uint8List>>[];
    final totalFaces = faceFeatures.length;
    var processedFaces = 0;

    // Group similar faces
    for (var entry in faceFeatures.entries) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      bool added = false;

      for (var group in faceGroups) {
        final representative = faceFeatures[group[0]]!;
        final matchScoreL2 = recognizer.match(
          faceFeature,
          representative,
          cv.FaceRecognizerSF.DIS_TYPE_FR_NORM_L2,
        );

        if (matchScoreL2 < 0.6) { // Threshold for similarity, adjust as needed
          group.add(faceImage);
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([faceImage]);
      }

      faceFeature.dispose();
      processedFaces++;
      params.sendPort.send(_ProgressMessage(processedFaces / totalFaces));
    }

    recognizer.dispose();
    params.sendPort.send(faceGroups);
  }
}

class _GroupFacesParams {
  final List<ImageData> images;
  final SendPort sendPort;
  final String modelPath;

  _GroupFacesParams(this.images, this.sendPort, this.modelPath);
}

class _ProgressMessage {
  final double progress;

  _ProgressMessage(this.progress);
}
