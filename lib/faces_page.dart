import 'dart:io';
import 'dart:typed_data';

import 'package:face_grouping/image_service.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class FacesPage extends StatelessWidget {
  final String imagePath;
  final cv.VecRect faceRects;

  FacesPage({required this.imagePath, required this.faceRects});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detected Faces'),
      ),
      body: FutureBuilder<List<Uint8List>>(
        future: ImageService.instance.extractFaces(imagePath, faceRects),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No faces detected'));
          } else {
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                return Image.memory(snapshot.data![index]);
              },
            );
          }
        },
      ),
    );
  }
}
