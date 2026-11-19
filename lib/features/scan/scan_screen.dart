import 'package:flutter/material.dart';
import '../../core/theme/whami_aviation.dart';
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
        backgroundColor: WhamiAviation.navy,
        appBar: AppBar(
          backgroundColor: WhamiAviation.navy,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VERIFY',
                style: TextStyle(
                  color: WhamiAviation.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                'Lock to the real world',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            labelColor: WhamiAviation.cyan,
            unselectedLabelColor: WhamiAviation.textMuted,
            indicatorColor: WhamiAviation.cyan,
            indicatorWeight: 2.5,
            tabs: [
              Tab(
                icon: Icon(Icons.document_scanner, size: 18),
                text: 'Landmark',
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
