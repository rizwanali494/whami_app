import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'landmark_scan_screen.dart';
import 'arcore_scan_screen.dart';

class ScanScreen extends StatelessWidget {
  final WhamiRepository repository;

  const ScanScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.headerBg,
          automaticallyImplyLeading: false,
          title: const Text(
            'Scan',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: TabBar(
            labelColor: AppColors.whami,
            unselectedLabelColor: const Color(0xFF78909C),
            indicatorColor: AppColors.whami,
            indicatorWeight: 2,
            tabs: const [
              Tab(
                icon: Icon(Icons.document_scanner, size: 18),
                text: 'Landmark Scan',
              ),
              Tab(
                icon: Icon(Icons.view_in_ar, size: 18),
                text: 'AR Scan',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            LandmarkScanScreen(repository: repository),
            ArScanScreen(repository: repository),
          ],
        ),
      ),
    );
  }
}
