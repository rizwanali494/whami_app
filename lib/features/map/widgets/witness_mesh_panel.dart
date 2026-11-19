import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../data/repositories/whami_repository.dart';

class WitnessMeshPanel extends StatefulWidget {
  final WhamiRepository repository;
  final VoidCallback onClose;

  const WitnessMeshPanel({
    super.key,
    required this.repository,
    required this.onClose,
  });

  @override
  State<WitnessMeshPanel> createState() => _WitnessMeshPanelState();
}

class _WitnessMeshPanelState extends State<WitnessMeshPanel> {
  final _importCtrl = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareLocal() async {
    try {
      final json = widget.repository.exportMeshPeerJson();
      await Share.share(json, subject: 'WHAMI Witness Mesh');
      setState(() => _status = 'Shared this device snapshot');
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  Future<void> _copyLocal() async {
    try {
      final json = widget.repository.exportMeshPeerJson();
      await Clipboard.setData(ClipboardData(text: json));
      setState(() => _status = 'Copied mesh snapshot');
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  void _import() {
    final result = widget.repository.importMeshPeerJson(_importCtrl.text.trim());
    setState(() {
      _status = result?.headline ?? 'Invalid mesh JSON';
    });
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.repository.witnessMesh;
    final compare = mesh.lastCompare;

    return Container(
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: WhamiAviation.glassPanel(radius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, color: WhamiAviation.cyan, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WITNESS MESH',
                      style: TextStyle(
                        color: WhamiAviation.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Compare peer devices',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareLocal,
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('Share me'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyLocal,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _importCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Paste peer mesh JSON…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _import,
            style: FilledButton.styleFrom(
              backgroundColor: WhamiAviation.cyanDim,
            ),
            child: const Text('Import peer & compare'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (compare != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${compare.peer.deviceLabel}: ${compare.headline}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
