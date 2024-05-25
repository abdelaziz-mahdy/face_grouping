import 'package:flutter/material.dart';

import 'home_page.dart';
import 'image_service.dart';

void main() {
  runApp(MyApp());
  ImageService(); // Initialize the singleton
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Detection App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}
