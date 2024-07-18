import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/face_detection_controller.dart';
import '../controllers/face_grouping_controller.dart';
import 'tabs/images_tab.dart';
import 'tabs/faces_tab.dart';
import 'tabs/similar_faces_tab.dart';
import 'package:file_picker/file_picker.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FaceDetectionController()),
        ChangeNotifierProvider(create: (_) => FaceGroupingController()),
      ],
      child: const HomePageContent(),
    );
  }
}

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final faceDetectionController = Provider.of<FaceDetectionController>(context);
    final faceGroupingController = Provider.of<FaceGroupingController>(context);

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
            ImagesTab(controller: faceDetectionController),
            FacesTab(controller: faceDetectionController),
            SimilarFacesTab(controller: faceGroupingController),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
            if (selectedDirectory != null) {
              await faceDetectionController.processDirectory(selectedDirectory);
              faceGroupingController.setImages(faceDetectionController.images);
              await faceGroupingController.groupFaces();
            }
          },
          child: const Icon(Icons.folder_open),
        ),
      ),
    );
  }
}
