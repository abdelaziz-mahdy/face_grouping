import 'package:flutter/material.dart';
import '../services/face_recognition_service.dart';
import '../services/image_service.dart';

class FaceGroupingController extends ChangeNotifier {
  bool _isProcessing = false;
  double _progress = 0.0;
  Duration _timeRemaining = Duration.zero;
  int _processedImages = 0;
  int _totalImages = 0;
  List<List<Map<String, dynamic>>> _faceGroups = [];
  List<ImageData> _images = [];

  bool get isProcessing => _isProcessing;
  double get progress => _progress;
  Duration get timeRemaining => _timeRemaining;
  int get processedImages => _processedImages;
  int get totalImages => _totalImages;
  List<List<Map<String, dynamic>>> get faceGroups => _faceGroups;
  List<ImageData> get images => _images;

  void setImages(List<ImageData> images) {
    _images = images;
    notifyListeners();
  }

  void groupFaces() async {
    _setProcessing(true);
    await FaceRecognitionService.instance.groupSimilarFaces(
      _images,
      (progress, stage, processedFaces, totalFaces, timeRemaining) {
        _updateProgress(progress, timeRemaining, processedFaces, totalFaces);
      },
      (faceGroups) {
        _updateFaceGroups(faceGroups);
        _setProcessing(false);
      },
    );
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

  void _updateFaceGroups(List<List<Map<String, dynamic>>> faceGroups) {
    _faceGroups = faceGroups;
    notifyListeners();
  }
}
