// lib/home_page.dart
import 'package:flutter/material.dart';
import 'images_tab.dart';
import 'faces_tab.dart';
import 'similar_faces_tab.dart';
import 'package:file_picker/file_picker.dart';
import 'image_service.dart';
import 'face_recognition_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isProcessing = false;
  List<ImageData> _images = [];
  double _progress = 0.0;
  Duration _timeRemaining = Duration.zero;
  int _processedImages = 0;
  int _totalImages = 0;
  List<List<Map<String, dynamic>>> _faceGroups = [];

  void _selectDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _progress = 0.0;
          _timeRemaining = Duration.zero;
          _processedImages = 0;
          _totalImages = 0;
          _faceGroups = [];
        });
      }

      List<ImageData> images = await ImageService.instance.processDirectory(
        selectedDirectory,
        (progress, timeRemaining, processed, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _timeRemaining = timeRemaining;
              _processedImages = processed;
              _totalImages = total;
            });
          }
        },
      );

      FaceRecognitionService.instance.groupSimilarFaces(
        images,
        (progress, stage, processedFaces, totalFaces, timeRemaining) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _processedImages = processedFaces;
              _totalImages = totalFaces;
              _timeRemaining = timeRemaining;
            });
          }
        },
        (faceGroups) {
          if (mounted) {
            setState(() {
              _faceGroups = faceGroups;
              _isProcessing = false;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _images = images;
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Face Detection App'),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Images"),
              Tab(text: "Faces"),
              Tab(text: "Similar Faces"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ImagesTab(
              isProcessing: _isProcessing,
              progress: _progress,
              timeRemaining: _timeRemaining,
              processedImages: _processedImages,
              totalImages: _totalImages,
              images: _images,
            ),
            FacesTab(images: _images, isProcessing: _isProcessing),
            SimilarFacesTab(images: _images, faceGroups: _faceGroups),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _selectDirectory,
          child: const Icon(Icons.folder_open),
        ),
      ),
    );
  }
}
