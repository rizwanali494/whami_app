import 'dart:async';
import '../../data/models/trust_event.dart';

/// Service that maintains a running history of trust/health events emitted by the positioning engines
class TrustEventLog {
  final List<TrustEvent> _events = [];
  final _controller = StreamController<List<TrustEvent>>.broadcast();

  Stream<List<TrustEvent>> get stream => _controller.stream;

  List<TrustEvent> getEvents() => List.unmodifiable(_events);

  /// Log a new navigation or trust state event
  void addEvent({
    required String title,
    required String description,
    required String severity, // info, warning, critical
    required String iconName,
  }) {
    final event = TrustEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      severity: severity,
      timestamp: DateTime.now(),
      description: description,
      iconName: iconName,
    );

    _events.insert(0, event); // newest first
    // Limit log to last 100 entries to prevent memory growth
    if (_events.length > 100) {
      _events.removeLast();
    }
    _controller.add(List.from(_events));
  }

  /// Seed initial logs on startup so the timeline screen is populated
  void seedInitialEvents() {
    if (_events.isNotEmpty) return;
    
    addEvent(
      title: 'Fusion Engine Initialized',
      description: 'Multi-spectral sensor integration engine started offline.',
      severity: 'info',
      iconName: 'settings',
    );
    addEvent(
      title: 'GPS Signal Active',
      description: 'Received initial GPS fix with ±12.4m estimated error.',
      severity: 'info',
      iconName: 'gps_fixed',
    );
  }

  void clear() {
    _events.clear();
    _controller.add([]);
  }

  void dispose() {
    _controller.close();
  }
}
