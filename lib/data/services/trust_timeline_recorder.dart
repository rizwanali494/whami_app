import '../models/trust_timeline_sample.dart';

/// Ring buffer of trust samples for post-walk / post-flight replay.
class TrustTimelineRecorder {
  static const int maxSamples = 600;

  final List<TrustTimelineSample> _samples = [];

  List<TrustTimelineSample> get samples =>
      List<TrustTimelineSample>.unmodifiable(_samples);

  bool get isEmpty => _samples.isEmpty;
  int get length => _samples.length;

  void clear() => _samples.clear();

  void add(TrustTimelineSample sample) {
    _samples.add(sample);
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }
  }
}
