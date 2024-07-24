import 'package:flutter/material.dart';
// import 'package:opencv_dart/opencv_dart.dart';
import 'ui/home_page.dart';

void main() {
  // print(getBuildInformation());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Detection App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}
