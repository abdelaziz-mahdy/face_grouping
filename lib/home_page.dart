import 'package:face_grouping/faces_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart';
import 'image_service.dart';
import 'dart:typed_data';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isProcessing = false;
  List<ImageData> _images = [];
  List<Uint8List> _faceImages = [];
  double _progress = 0.0;

  void _selectDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _isProcessing = true;
        _progress = 0.0;
      });

      List<ImageData> images = await ImageService.instance.processDirectory(
        selectedDirectory,
        (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      List<Uint8List> faceImages = [];
      for (var image in images) {
        final faceRects = await ImageService.instance.detectFaces(image.path);
        final faces =
            await ImageService.instance.extractFaces(image.path, faceRects);
        faceImages.addAll(faces);
      }

      setState(() {
        _images = images;
        _faceImages = faceImages;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Face Detection App'),
          bottom: TabBar(
            tabs: [
              Tab(text: "Images"),
              Tab(text: "Faces"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildImagesTab(),
            _buildFacesTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _selectDirectory,
          child: Icon(Icons.folder_open),
        ),
      ),
    );
  }

  Widget _buildImagesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _isProcessing
              ? Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                        'Processing: ${(_progress * 100).toStringAsFixed(2)}%'),
                    SizedBox(height: 10),
                    Text('Images found: ${_images.length}'),
                  ],
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_images[index].path),
                        subtitle:
                            Text('Faces detected: ${_images[index].faceCount}'),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildFacesTab() {
    return Center(
      child: _isProcessing
          ? CircularProgressIndicator()
          : _faceImages.isEmpty
              ? Text('No faces detected')
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _faceImages.length,
                  itemBuilder: (context, index) {
                    return Image.memory(_faceImages[index]);
                  },
                ),
    );
  }
}
