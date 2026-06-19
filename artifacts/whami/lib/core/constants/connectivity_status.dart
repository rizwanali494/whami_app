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
}
