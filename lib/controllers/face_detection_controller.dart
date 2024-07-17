import 'package:flutter/material.dart';
import '../services/image_service.dart';

class FaceDetectionController extends ChangeNotifier {
  bool _isProcessing = false;
  double _progress = 0.0;
  Duration _timeRemaining = Duration.zero;
  int _processedImages = 0;
  int _totalImages = 0;
  List<ImageData> _images = [];

  bool get isProcessing => _isProcessing;
  double get progress => _progress;
  Duration get timeRemaining => _timeRemaining;
  int get processedImages => _processedImages;
  int get totalImages => _totalImages;
  List<ImageData> get images => _images;

  void processDirectory(String directoryPath) async {
    _setProcessing(true);
    _images = await ImageService.instance.processDirectory(
      directoryPath,
      (progress, timeRemaining, processed, total) {
        _updateProgress(progress, timeRemaining, processed, total);
      },
    );
    _setProcessing(false);
  }

  void _setProcessing(bool value) {
    _isProcessing = value;
    notifyListeners();
  }

  void _updateProgress(double progress, Duration timeRemaining, int processedImages, int totalImages) {
    _progress = progress;
    _timeRemaining = timeRemaining;
    _processedImages = processedImages;
    _totalImages = totalImages;
    notifyListeners();
  }
}
