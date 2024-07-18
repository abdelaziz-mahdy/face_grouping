import 'package:opencv_dart/opencv_dart.dart' as cv;

class SendableRect {
  final int x, y, width, height;
  final List<double> rawDetection;
  final String originalImagePath;

  SendableRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rawDetection,
    required this.originalImagePath,
  });

  cv.Rect toRect() {
    return cv.Rect(x, y, width, height);
  }

  static SendableRect fromRect(
      cv.Rect rect, List<double> rawDetection, String originalImagePath) {
    return SendableRect(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      rawDetection: rawDetection,
      originalImagePath: originalImagePath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rawDetection': rawDetection,
      'originalImagePath': originalImagePath,
    };
  }

  static SendableRect fromMap(Map<String, dynamic> map) {
    return SendableRect(
      x: map['x'],
      y: map['y'],
      width: map['width'],
      height: map['height'],
      rawDetection: List<double>.from(map['rawDetection']),
      originalImagePath: map['originalImagePath'],
    );
  }
}
