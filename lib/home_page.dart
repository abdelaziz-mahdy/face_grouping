import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'face_recognition_controller.dart';
import 'images_tab.dart';
import 'faces_tab.dart';
import 'similar_faces_tab.dart';
import 'package:file_picker/file_picker.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FaceRecognitionController(),
      child: const HomePageContent(),
    );
  }
}

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<FaceRecognitionController>(context);

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
            ImagesTab(controller: controller),
            FacesTab(controller: controller),
            SimilarFacesTab(controller: controller),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
            if (selectedDirectory != null) {
              controller.processDirectory(selectedDirectory);
            }
          },
          child: const Icon(Icons.folder_open),
        ),
      ),
    );
  }
}
