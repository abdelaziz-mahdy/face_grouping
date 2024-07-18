import 'dart:typed_data';

import 'package:face_grouping/models/sendable_rect.dart';


class FaceGroup {
  final Uint8List faceImage;
  final String originalImagePath;
  final SendableRect rect;

  FaceGroup({
    required this.faceImage,
    required this.originalImagePath,
    required this.rect,
  });

  Map<String, dynamic> toMap() {
    return {
      'faceImage': faceImage,
      'originalImagePath': originalImagePath,
      'rect': rect.toMap(),
    };
  }

  factory FaceGroup.fromMap(Map<String, dynamic> map) {
    return FaceGroup(
      faceImage: map['faceImage'],
      originalImagePath: map['originalImagePath'],
      rect: SendableRect.fromMap(map['rect']),
    );
  }
}
