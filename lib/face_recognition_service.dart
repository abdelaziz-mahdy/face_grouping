import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'image_service.dart';
import 'dart:convert';

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
    void Function(double, String, int, int, Duration) progressCallback,
    void Function(List<List<Map<String, dynamic>>>) completionCallback,
  ) async {
    final tmpModelPath = await _copyAssetFileToTmp("assets/face_recognition_sface_2021dec.onnx");

    final receivePort = ReceivePort();
    final startTime = DateTime.now();

    Isolate.spawn(
      _groupSimilarFacesIsolate,
      _GroupFacesParams(images, receivePort.sendPort, tmpModelPath),
    );

    receivePort.listen((message) {
      if (message is _ProgressMessage) {
        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / message.progress);
        final remainingTime = estimatedTotalTime - elapsed;

        progressCallback(message.progress, message.stage, message.processedFaces, message.totalFaces, remainingTime);
      } else if (message is List<List<Map<String, dynamic>>>) {
        saveGroupedFacesResult(message); // Save the results for future usage
        completionCallback(message);
        receivePort.close();
      }
    });
  }

  static Future<void> _groupSimilarFacesIsolate(_GroupFacesParams params) async {
    final recognizer = cv.FaceRecognizerSF.fromFile(
      params.modelPath,
      "",
      backendId: cv.DNN_BACKEND_OPENCV,
      targetId: cv.DNN_TARGET_OPENCL,
    );
    final faceFeatures = <Uint8List, cv.Mat>{};
    final faceInfoMap = <Uint8List, Map<String, dynamic>>{};
    final totalFaces = params.images.fold<int>(0, (sum, image) => sum + image.sendableFaceRects.length);

    int processedFaces = 0;

    // Phase 1: Extract features for each face image
    for (var image in params.images) {
      final imagePath = image.path;
      for (var i = 0; i < image.sendableFaceRects.length; i++) {
        final rect = image.sendableFaceRects[i];
        final mat = cv.imread(imagePath, flags: cv.IMREAD_COLOR);

        // Create a bounding box Mat from raw detection data
        final faceBox = cv.Mat.fromList(1, rect.rawDetection.length, cv.MatType.CV_32FC1, rect.rawDetection);

        // Align and crop the face using alignCrop
        final alignedFace = recognizer.alignCrop(mat, faceBox);

        // Extract features from the aligned and cropped face
        final feature = recognizer.feature(alignedFace);
        final encodedFace = cv.imencode('.jpg', alignedFace);

        faceFeatures[encodedFace] = feature.clone();
        faceInfoMap[encodedFace] = {
          'originalImagePath': rect.originalImagePath,
          'rect': rect,
        };

        alignedFace.dispose();
        faceBox.dispose(); // Dispose the faceBox after use
        processedFaces++;
        params.sendPort.send(_ProgressMessage(processedFaces / totalFaces, "Extracting Features", processedFaces, totalFaces));
      }
    }

    final faceGroups = <List<Map<String, dynamic>>>[];
    processedFaces = 0; // Reset processedFaces for the next phase

    // Phase 2: Group similar faces
    for (var entry in faceFeatures.entries) {
      final faceImage = entry.key;
      final faceFeature = entry.value;

      bool added = false;

      for (var group in faceGroups) {
        double totalMatchScoreCosine = 0;
        double totalMatchScoreNormL2 = 0;

        // Compare the new face feature with each member in the group
        for (var existingFace in group) {
          final existingFeature = faceFeatures[existingFace['faceImage']]!;
          totalMatchScoreCosine += recognizer.match(
            faceFeature,
            existingFeature,
            disType: cv.FaceRecognizerSF.FR_COSINE,
          );
          totalMatchScoreNormL2 += recognizer.match(
            faceFeature,
            existingFeature,
            disType: cv.FaceRecognizerSF.FR_NORM_L2,
          );
        }

        // Average the match scores
        final averageMatchScoreCosine = totalMatchScoreCosine / group.length;
        final averageMatchScoreNormL2 = totalMatchScoreNormL2 / group.length;

        if (averageMatchScoreCosine >= 0.38 && averageMatchScoreNormL2 <= 1.12) {
          // Thresholds for similarity
          group.add({
            'faceImage': faceImage,
            'originalImagePath': faceInfoMap[faceImage]!['originalImagePath'],
            'rect': faceInfoMap[faceImage]!['rect'],
          });
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([
          {
            'faceImage': faceImage,
            'originalImagePath': faceInfoMap[faceImage]!['originalImagePath'],
            'rect': faceInfoMap[faceImage]!['rect'],
          }
        ]);
      }

      processedFaces++;
      params.sendPort.send(_ProgressMessage(processedFaces / totalFaces, "Grouping Faces", processedFaces, totalFaces));
    }

    recognizer.dispose();
    params.sendPort.send(faceGroups);
  }

  Future<void> saveGroupedFacesResult(List<List<Map<String, dynamic>>> faceGroups) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/grouped_faces.json';
    final file = File(filePath);

    final jsonString = jsonEncode(faceGroups);
    await file.writeAsString(jsonString);
  }

  Future<List<List<Map<String, dynamic>>>> loadGroupedFacesResult() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/grouped_faces.json';
    final file = File(filePath);

    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);

      return jsonData.map((group) => (group as List<dynamic>).map((face) => Map<String, dynamic>.from(face)).toList()).toList();
    } else {
      return [];
    }
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
  final int processedFaces;
  final int totalFaces;

  _ProgressMessage(this.progress, this.stage, this.processedFaces, this.totalFaces);
}
