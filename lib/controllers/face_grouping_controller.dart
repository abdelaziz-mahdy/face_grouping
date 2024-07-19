import 'package:face_grouping/models/image_data.dart';
import 'package:flutter/material.dart';
import '../services/face_recognition_service.dart';
import '../models/face_group.dart';

class FaceGroupingController extends ChangeNotifier {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _stage = "";
  Duration _timeRemaining = Duration.zero;
  int _processedImages = 0;
  int _totalImages = 0;
  List<List<FaceGroup>> _faceGroups = [];
  List<ImageData> _images = [];

  bool get isProcessing => _isProcessing;
  String get stage => _stage;
  double get progress => _progress;
  Duration get timeRemaining => _timeRemaining;
  int get processedImages => _processedImages;
  int get totalImages => _totalImages;
  List<List<FaceGroup>> get faceGroups => _faceGroups;
  List<ImageData> get images => _images;

  void setImages(List<ImageData> images) {
    _images = images;
    notifyListeners();
  }

  Future<void> groupFaces() async {
    _setProcessing(true);
    await FaceRecognitionService.instance.groupSimilarFaces(
      _images,
      (progress, stage, processedFaces, totalFaces, timeRemaining) {
        _updateProgress(
            progress, stage, timeRemaining, processedFaces, totalFaces);
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

  void _updateProgress(double progress, String stage, Duration timeRemaining,
      int processedImages, int totalImages) {
    _progress = progress;
    _stage = stage;
    _timeRemaining = timeRemaining;
    _processedImages = processedImages;
    _totalImages = totalImages;
    notifyListeners();
  }

  void _updateFaceGroups(List<List<FaceGroup>> faceGroups) {
    _faceGroups = faceGroups;
    notifyListeners();
  }
}
