import 'package:face_grouping/models/sendable_rect.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImageData {
  final String path;
  final int faceCount;
  final List<SendableRect> sendableFaceRects;

  ImageData({
    required this.path,
    required this.faceCount,
    required this.sendableFaceRects,
  });

  List<cv.Rect> get faceRects {
    return sendableFaceRects.map((r) => r.toRect()).toList();
  }
}
