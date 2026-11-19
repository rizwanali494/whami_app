import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trust_timeline_sample.dart';
import '../../data/repositories/whami_repository.dart';

/// Scrub a recorded trust timeline after a walk / drive / flight.
class TrustTimelineScreen extends StatefulWidget {
  final WhamiRepository repository;

  const TrustTimelineScreen({super.key, required this.repository});

  @override
  State<TrustTimelineScreen> createState() => _TrustTimelineScreenState();
}

class _TrustTimelineScreenState extends State<TrustTimelineScreen> {
  double _index = 0;
  bool _exporting = false;

  WhamiRepository get repo => widget.repository;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await repo.exportEvidencePack();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'WHAMI Evidence Pack — verified by the real world.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final n = repo.trustTimeline.length;
    if (n > 0) _index = (n - 1).toDouble();
  }

  Color _colorFor(String level) {
    switch (level) {
      case 'reliable':
        return AppColors.trustHigh;
      case 'caution':
        return AppColors.trustMediumDark;
      case 'unreliable':
        return AppColors.trustLow;
      default:
        return AppColors.textSecondary;
    }
  }

  String _labelFor(String level) {
    switch (level) {
      case 'reliable':
        return 'RELIABLE';
      case 'caution':
        return 'CAUTION';
      case 'unreliable':
        return 'UNRELIABLE';
      default:
        return level.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        final samples = repo.trustTimeline.samples;
        if (samples.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Trust Timeline')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No timeline yet.\nStart tracking on Map, walk for a bit, then open Replay.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final i = _index.round().clamp(0, samples.length - 1);
        final sample = samples[i];
        final color = _colorFor(sample.level);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trust Timeline Replay'),
            actions: [
              TextButton(
                onPressed: _exporting ? null : _export,
                child: Text(_exporting ? '…' : 'Export'),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _index = (samples.length - 1).toDouble());
                },
                child: const Text('Latest'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      _labelFor(sample.level),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${sample.trustScore} / 100  ·  ±${sample.uncertaintyM.round()} m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sample.gnssSuspicious) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'GPS SUSPICIOUS — DON\'T TRUST THIS PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                sample.timestamp.toLocal().toString().split('.').first,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (sample.alertMessage != null) ...[
                const SizedBox(height: 8),
                Text(sample.alertMessage!, style: const TextStyle(fontSize: 14)),
              ],
              const SizedBox(height: 16),
              Text(
                'Scrub timeline (${i + 1} / ${samples.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Slider(
                value: _index.clamp(0, (samples.length - 1).toDouble()),
                min: 0,
                max: (samples.length - 1).toDouble(),
                divisions: samples.length > 1 ? samples.length - 1 : null,
                label: '${sample.trustScore}%',
                onChanged: (v) => setState(() => _index = v),
              ),
              SizedBox(
                height: 72,
                child: CustomPaint(
                  painter: _TimelineSparklinePainter(samples: samples, index: i),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sensors at this moment',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...sample.witnessScores.entries.map(
                (e) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(e.key, style: const TextStyle(fontSize: 11)),
                  ),
                  title: Text('Source ${e.key}'),
                  trailing: Text(
                    '${e.value}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: e.value < 55 ? AppColors.trustLow : null,
                    ),
                  ),
                ),
              ),
              if (sample.brokenWitnesses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Broke / weak: ${sample.brokenWitnesses.join(", ")}',
                  style: const TextStyle(
                    color: AppColors.trustLow,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (sample.gnssSuspicious &&
                  sample.gpsClaimLatitude != null &&
                  sample.trustedLatitude != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Ghost Pin split',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _GhostSplitCard(sample: sample),
              ],
              const SizedBox(height: 12),
              Text(
                'Position: ${sample.latitude.toStringAsFixed(5)}, '
                '${sample.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GhostSplitCard extends StatelessWidget {
  final TrustTimelineSample sample;

  const _GhostSplitCard({required this.sample});

  @override
  Widget build(BuildContext context) {
    final dist = sample.lieDistanceM;
    final distLabel = dist == null
        ? '—'
        : dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km'
            : '${dist.round()} m';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.trustLow.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GPS is $distLabel from reality',
            style: const TextStyle(
              color: AppColors.trustLow,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PinColumn(
                  title: 'Ghost (GPS)',
                  color: AppColors.gps,
                  lat: sample.gpsClaimLatitude!,
                  lng: sample.gpsClaimLongitude!,
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppColors.trustLow),
              Expanded(
                child: _PinColumn(
                  title: 'Trusted',
                  color: AppColors.trustHigh,
                  lat: sample.trustedLatitude!,
                  lng: sample.trustedLongitude!,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinColumn extends StatelessWidget {
  final String title;
  final Color color;
  final double lat;
  final double lng;

  const _PinColumn({
    required this.title,
    required this.color,
    required this.lat,
    required this.lng,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.place, color: color),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
        Text(
          '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _TimelineSparklinePainter extends CustomPainter {
  final List<TrustTimelineSample> samples;
  final int index;

  _TimelineSparklinePainter({required this.samples, required this.index});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..color = AppColors.whami;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1
          ? size.width / 2
          : i / (samples.length - 1) * size.width;
      final y = size.height -
          (samples[i].trustScore.clamp(0, 100) / 100.0) * (size.height - 8) -
          4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    final x = samples.length == 1
        ? size.width / 2
        : index / (samples.length - 1) * size.width;
    final y = size.height -
        (samples[index].trustScore.clamp(0, 100) / 100.0) * (size.height - 8) -
        4;
    canvas.drawCircle(
      Offset(x, y),
      5,
      Paint()..color = AppColors.trustLow,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineSparklinePainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.samples.length != samples.length;
}
