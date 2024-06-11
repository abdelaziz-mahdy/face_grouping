import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'image_service.dart';

class FaceRecognitionService {
  static List<List<Uint8List>> groupSimilarFaces(List<ImageData> images) {
    const modelPath = "assets/face_recognition_sface_2021dec.onnx";
    final recognizer = cv.FaceRecognizerSF.newRecognizer(modelPath, "", 0, 0);

    final faceFeatures = <Uint8List, cv.Mat>{};

    // Extract features for each face image
    for (var image in images) {
      for (var faceImage in image.faceImages) {
        final mat = cv.imdecode(faceImage, cv.IMREAD_COLOR);
        final feature = recognizer.feature(mat);
        faceFeatures[faceImage] = feature;
      }
    }

    final faceGroups = <List<Uint8List>>[];

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

        if (matchScoreL2 < 0.6) {
          // Threshold for similarity, adjust as needed
          group.add(faceImage);
          added = true;
          break;
        }
      }

      if (!added) {
        faceGroups.add([faceImage]);
      }

      faceFeature.dispose();
    }

    recognizer.dispose();
    return faceGroups;
  }
}
