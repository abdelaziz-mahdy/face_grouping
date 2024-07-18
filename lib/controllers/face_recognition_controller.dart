import 'package:face_grouping/models/face_group.dart';
import 'package:face_grouping/models/image_data.dart';
import 'package:flutter/material.dart';
import '../services/image_service.dart';
import '../services/face_recognition_service.dart';

class FaceRecognitionController extends ChangeNotifier {
  bool _isProcessing = false;
  double _progress = 0.0;
  Duration _timeRemaining = Duration.zero;
  int _processedImages = 0;
  int _totalImages = 0;
  List<List<FaceGroup>> _faceGroups = [];
  List<ImageData> _images = [];

  bool get isProcessing => _isProcessing;
  double get progress => _progress;
  Duration get timeRemaining => _timeRemaining;
  int get processedImages => _processedImages;
  int get totalImages => _totalImages;
  List<List<FaceGroup>> get faceGroups => _faceGroups;
  List<ImageData> get images => _images;

  void processDirectory(String directoryPath) async {
    _setProcessing(true);
    _images = await ImageService.instance.processDirectory(
      directoryPath,
      (progress, timeRemaining, processed, total) {
        _updateProgress(progress, timeRemaining, processed, total);
      },
    );

    _setProcessing(false); // Stop processing after detection
    _groupFaces(); // Start face grouping
  }

  void _groupFaces() async {
    _setProcessing(true); // Start processing for grouping

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

  void _updateProgress(double progress, Duration timeRemaining,
      int processedImages, int totalImages) {
    _progress = progress;
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
