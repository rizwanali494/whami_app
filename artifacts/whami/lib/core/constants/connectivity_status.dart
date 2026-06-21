import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectivityMode { online, offline, limited }

class ConnectivityState {
  final ConnectivityMode mode;
  final String activePackName;
  final String packCoverageStatus;

  const ConnectivityState({
    required this.mode,
    required this.activePackName,
    required this.packCoverageStatus,
  });

  factory ConnectivityState.fromResults(
    List<ConnectivityResult> results, {
    required String activePackName,
    required String packCoverageStatus,
  }) {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final hasEthernet = results.contains(ConnectivityResult.ethernet);

    ConnectivityMode mode = ConnectivityMode.offline;
    if (hasWifi || hasMobile || hasEthernet) {
      mode = ConnectivityMode.online;
    }

    return ConnectivityState(
      mode: mode,
      activePackName: activePackName,
      packCoverageStatus: packCoverageStatus,
    );
  }
}
