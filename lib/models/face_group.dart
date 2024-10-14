import 'dart:convert';
import 'dart:typed_data';

import 'package:face_grouping/models/sendable_rect.dart';

class FaceGroup {
  final Uint8List faceImage;
  final String originalImagePath;
  final SendableRect rect;
  final List<double> faceFeature;

  FaceGroup({
    required this.faceImage,
    required this.originalImagePath,
    required this.rect,
    required this.faceFeature,
  });

  Map<String, dynamic> toMap() {
    return {
      'faceImage': faceImage,
      'originalImagePath': originalImagePath,
      'rect': rect.toMap(),
      'faceFeature': faceFeature
    };
  }

  factory FaceGroup.fromMap(Map<String, dynamic> map) {
    return FaceGroup(
        faceImage: map['faceImage'],
        originalImagePath: map['originalImagePath'],
        rect: SendableRect.fromMap(map['rect']),
        faceFeature: map['faceFeature'] is String
            ? jsonDecode(map['faceFeature'])
            : map['faceFeature']);
  }
}
