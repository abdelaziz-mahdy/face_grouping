import 'package:face_grouping/faces_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart';

import 'image_service.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isProcessing = false;
  List<ImageData> _images = [];

  void _selectDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _isProcessing = true;
      });
      List<ImageData> images = await ImageService.instance.processDirectory(selectedDirectory);
      setState(() {
        _images = images;
        _isProcessing = false;
      });
    }
  }

  void _showFaces(String imagePath, VecRect faceRects) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FacesPage(imagePath: imagePath, faceRects: faceRects),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Face Detection App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _selectDirectory,
              child: Text('Select Directory'),
            ),
            SizedBox(height: 20),
            _isProcessing
                ? CircularProgressIndicator()
                : Expanded(
                    child: ListView.builder(
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_images[index].path),
                          subtitle: Text('Faces detected: ${_images[index].faceCount}'),
                          onTap: () async {
                            final faceRects = await ImageService.instance.detectFaces(_images[index].path);
                            _showFaces(_images[index].path, faceRects);
                          },
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
