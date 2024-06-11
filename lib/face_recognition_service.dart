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

  static final FaceRecognitionService instance =
      FaceRecognitionService._privateConstructor();

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
    void Function(double, String) progressCallback,
    void Function(List<List<Uint8List>>) completionCallback,
  ) async {
    final tmpModelPath =
        await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    final receivePort = ReceivePort();

    Isolate.spawn(
      _groupSimilarFacesIsolate,
      _GroupFacesParams(images, receivePort.sendPort, tmpModelPath),
    );

    receivePort.listen((message) {
      if (message is _ProgressMessage) {
        progressCallback(message.progress, message.stage);
      } else if (message is List<List<Uint8List>>) {
        completionCallback(message);
        receivePort.close();
      }
    });
  }

  static Future<void> _groupSimilarFacesIsolate(
      _GroupFacesParams params) async {
    final recognizer =
        cv.FaceRecognizerSF.newRecognizer(params.modelPath, "", 0, 0);
    final faceFeatures = <Uint8List, cv.Mat>{};
    final totalFaces = params.images.fold<int>(0, (sum, image) => sum + image.faceImages.length);

    int processedFaces = 0;
    
    // Phase 1: Extract features for each face image
    for (var image in params.images) {
      for (var i = 0; i < image.sendableFaceRects.length; i++) {
        final faceImage = image.faceImages[i];
        final rect = image.sendableFaceRects[i].toRect();
        final mat = cv.imdecode(faceImage, cv.IMREAD_COLOR);

        final faceBox = cv.Mat.zeros(1, 4, cv.MatType.CV_32SC1);
        faceBox.set<int>(0, 0, rect.x); // x
        faceBox.set<int>(0, 1, rect.y); // y
        faceBox.set<int>(0, 2, rect.width); // width
        faceBox.set<int>(0, 3, rect.height); // height
        // Align and crop the face using alignCrop
        final alignedFace = recognizer.alignCrop(mat, faceBox);

        // Extract features from the aligned and cropped face
        final feature = recognizer.feature(alignedFace);
        faceFeatures[faceImage] = feature;

        alignedFace.dispose();
        processedFaces++;
        params.sendPort.send(_ProgressMessage(processedFaces / totalFaces, "Extracting Features"));
      }
    }

    final faceGroups = <List<Uint8List>>[];
    processedFaces = 0; // Reset processedFaces for the next phase

    // Phase 2: Group similar faces
    for (var entry in faceFeatures.entries) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      bool added = false;

      for (var group in faceGroups) {
        final representative = faceFeatures[group[0]]!;
        final matchScoreCosine = recognizer.match(
          faceFeature,
          representative,
          cv.FaceRecognizerSF.DIS_TYPR_FR_COSINE,
        );

        if (matchScoreCosine <= 0.363) { // Threshold for cosine similarity
          group.add(faceImage);
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([faceImage]);
      }

      processedFaces++;
      params.sendPort.send(_ProgressMessage(processedFaces / totalFaces, "Grouping Faces"));
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
  final String stage;

  _ProgressMessage(this.progress, this.stage);
}
