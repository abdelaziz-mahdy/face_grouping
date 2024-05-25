import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'image_service.dart';
import 'dart:typed_data';
class HomePage extends StatefulWidget {
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

  void _selectDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _isProcessing = true;
        _progress = 0.0;
        _timeRemaining = Duration.zero;
        _processedImages = 0;
        _totalImages = 0;
      });

      List<ImageData> images = await ImageService.instance.processDirectory(
        selectedDirectory,
        (progress, timeRemaining, processed, total) {
          setState(() {
            _progress = progress;
            _timeRemaining = timeRemaining;
            _processedImages = processed;
            _totalImages = total;
          });
        },
      );

      setState(() {
        _images = images;
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
                    Text('Processing: ${(_progress * 100).toStringAsFixed(2)}%'),
                    SizedBox(height: 10),
                    Text('Estimated time remaining: ${_timeRemaining.inSeconds} seconds'),
                    SizedBox(height: 10),
                    Text('Images processed: $_processedImages out of $_totalImages'),
                  ],
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_images[index].path),
                        subtitle: Text('Faces detected: ${_images[index].faceCount}'),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildFacesTab() {
    final faceImages = _images.expand((image) => image.faceImages).toList();

    return Center(
      child: _isProcessing
          ? CircularProgressIndicator()
          : faceImages.isEmpty
              ? Text('No faces detected')
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: faceImages.length,
                  itemBuilder: (context, index) {
                    return Image.memory(faceImages[index]);
                  },
                ),
    );
  }
}
