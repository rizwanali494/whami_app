import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/flight_plan.dart';
import '../../../data/repositories/whami_repository.dart';
import '../../../data/services/route_progress.dart';
import 'overlay_close_button.dart';

/// Premium travel-route planner: drop pins ahead, review legs, save.
class FlightPlanPanel extends StatelessWidget {
  final WhamiRepository repository;
  final VoidCallback? onClose;

  const FlightPlanPanel({
    super.key,
    required this.repository,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final plan = repository.activeFlightPlan ?? FlightPlan.empty(name: 'Travel route');
    final edit = repository.flightPlanEditMode;
    final progress = repository.routeProgress;
    final legs = plan.legLengthsM;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2E), Color(0xFF12253D)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)],
                      ),
                    ),
                    child: const Icon(
                      Icons.alt_route,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (plan.name.isEmpty ? 'Travel route' : plan.name)
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          edit
                              ? 'Tap the map to place pins ahead'
                              : plan.isEmpty
                                  ? 'Build your route · Origin → Destination'
                                  : _summaryLine(plan),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onClose != null) OverlayCloseButton(onPressed: onClose!),
                ],
              ),
              if (plan.hasRoute && plan.totalLengthM >= 5) ...[
                const SizedBox(height: 12),
                _RouteStatsStrip(plan: plan, progress: progress),
              ],
              if (progress != null) ...[
                const SizedBox(height: 10),
                _AlongTrackCard(progress: progress),
              ],
              if (plan.waypoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: plan.waypoints.length,
                    itemBuilder: (context, i) {
                      final w = plan.waypoints[i];
                      final role = i == 0
                          ? _PinRole.origin
                          : (i == plan.waypoints.length - 1 &&
                                  plan.waypoints.length > 1)
                              ? _PinRole.destination
                              : _PinRole.enroute;
                      final legAfter =
                          i < legs.length ? legs[i] : null;
                      return _WaypointRow(
                        index: i + 1,
                        waypoint: w,
                        role: role,
                        legAfterM: legAfter,
                        editable: edit,
                        onRename: () => _rename(context, repository, w),
                        onDelete: () => repository.removeFlightWaypoint(w.id),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChip(
                    label: edit ? 'Done placing' : 'Place pins',
                    icon: edit ? Icons.check : Icons.add_location_alt_outlined,
                    filled: !edit,
                    accent: const Color(0xFF4FC3F7),
                    onTap: () {
                      if (edit) {
                        repository.setFlightPlanEditMode(false);
                        repository.saveActiveFlightPlan();
                        onClose?.call();
                      } else {
                        repository.beginTravelRoutePlanning();
                      }
                    },
                  ),
                  _ActionChip(
                    label: 'Pin my GPS',
                    icon: Icons.my_location,
                    onTap: () {
                      repository.beginTravelRoutePlanning();
                      final gps = repository.getPositionOpinions().where(
                        (o) =>
                            o.sourceType == 'gps' &&
                            o.status != 'unavailable',
                      );
                      if (gps.isEmpty) return;
                      final g = gps.first;
                      repository.addFlightWaypoint(
                        latitude: g.latitude,
                        longitude: g.longitude,
                        name: plan.waypoints.isEmpty ? 'Origin' : null,
                      );
                    },
                  ),
                  _ActionChip(
                    label: 'Save route',
                    icon: Icons.bookmark_added_outlined,
                    filled: true,
                    accent: const Color(0xFF1565C0),
                    onTap: () => repository.saveActiveFlightPlan(),
                  ),
                  if (!plan.isEmpty)
                    _ActionChip(
                      label: 'Clear',
                      icon: Icons.delete_outline,
                      onTap: () => repository.clearActiveFlightPlan(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summaryLine(FlightPlan plan) {
    final n = plan.waypoints.length;
    if (!plan.hasRoute || plan.totalLengthM < 5) {
      return '$n pin${n == 1 ? '' : 's'} · tap further ahead to stretch the route';
    }
    return '$n pins · ${FlightPlan.formatDistance(plan.totalLengthM)}';
  }

  Future<void> _rename(
    BuildContext context,
    WhamiRepository repo,
    FlightWaypoint w,
  ) async {
    final controller = TextEditingController(text: w.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2E),
        title: const Text(
          'Rename waypoint',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: const Color(0xFF4FC3F7),
          decoration: InputDecoration(
            hintText: 'e.g. Tocumwal / 052FinAP',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      repo.renameFlightWaypoint(w.id, name);
    }
  }
}

enum _PinRole { origin, enroute, destination }

class _RouteStatsStrip extends StatelessWidget {
  final FlightPlan plan;
  final RouteProgress? progress;

  const _RouteStatsStrip({required this.plan, required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = progress?.fractionAlong.clamp(0.0, 1.0) ?? 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Stat(
                label: 'DISTANCE',
                value: plan.totalLengthNm >= 1
                    ? '${plan.totalLengthNm.toStringAsFixed(plan.totalLengthNm >= 10 ? 0 : 1)} NM'
                    : FlightPlan.formatDistance(plan.totalLengthM),
              ),
              _Stat(
                label: 'LEGS',
                value: '${plan.waypoints.length - 1}',
              ),
              _Stat(
                label: 'PINS',
                value: '${plan.waypoints.length}',
              ),
              if (progress != null)
                _Stat(
                  label: 'ALONG',
                  value: '${(pct * 100).round()}%',
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC107)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlongTrackCard extends StatelessWidget {
  final RouteProgress progress;

  const _AlongTrackCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.whami.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.whami.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.whami,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.crossTrackLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progress.toNextLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  final int index;
  final FlightWaypoint waypoint;
  final _PinRole role;
  final double? legAfterM;
  final bool editable;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _WaypointRow({
    required this.index,
    required this.waypoint,
    required this.role,
    required this.legAfterM,
    required this.editable,
    required this.onRename,
    required this.onDelete,
  });

  Color get _roleColor {
    switch (role) {
      case _PinRole.origin:
        return const Color(0xFF43A047);
      case _PinRole.destination:
        return const Color(0xFFFFC107);
      case _PinRole.enroute:
        return const Color(0xFF4FC3F7);
    }
  }

  String get _roleLabel {
    switch (role) {
      case _PinRole.origin:
        return 'ORIGIN';
      case _PinRole.destination:
        return 'DEST';
      case _PinRole.enroute:
        return 'WP${index.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: editable ? onRename : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _roleColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: _roleColor, width: 1.5),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: _roleColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              waypoint.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _roleColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _roleLabel,
                              style: TextStyle(
                                color: _roleColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        FlightPlan.formatCoord(
                          waypoint.latitude,
                          waypoint.longitude,
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (editable)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 20,
                    ),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
        if (legAfterM != null)
          Padding(
            padding: const EdgeInsets.only(left: 13, bottom: 2),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.south,
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  FlightPlan.formatDistance(legAfterM!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color accent;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.accent = const Color(0xFF4FC3F7),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? accent : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
