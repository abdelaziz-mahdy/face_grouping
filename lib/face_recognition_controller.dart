import 'package:flutter/material.dart';
import 'image_service.dart';
import 'face_recognition_service.dart';

class FaceRecognitionController extends ChangeNotifier {
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

  void processDirectory(String directoryPath) async {
    _setProcessing(true);
    _images = await ImageService.instance.processDirectory(
      directoryPath,
      (progress, timeRemaining, processed, total) {
        _updateProgress(progress, timeRemaining, processed, total);
      },
    );

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
