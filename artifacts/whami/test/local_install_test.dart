import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:whami/data/services/region_engine.dart';
import 'package:whami/data/services/region_pack_storage.dart';
import 'package:whami/data/services/landmark_database.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  testWidgets('Install local .whami pack', (tester) async {
    WidgetsFlutterBinding.ensureInitialized();
    final storage = RegionPackStorage();
    final landmarkDb = LandmarkDatabase();
    final engine = RegionEngine(storage: storage, landmarkDatabase: landmarkDb);

    final zipPath = '${Directory.current.path}/scratch/test_region.whami';
    
    // Attempt installation
    try {
      await engine.installLocalPack(zipPath);
      
      expect(engine.activePackId, 'pakistan_punjab');
      expect(engine.activePackMetadata?.name, 'Punjab');
      expect(engine.activePackMetadata?.country, 'Pakistan');
      
      print('Installation and auto-activation successful!');
    } catch (e, stack) {
      print('Installation failed: $e\n$stack');
      fail('Exception during local install');
    }
  });
}
