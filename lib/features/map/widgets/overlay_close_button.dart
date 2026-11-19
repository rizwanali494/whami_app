import 'package:flutter/material.dart';

/// Large, obvious dismiss control for map overlays (banners / panels).
class OverlayCloseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color iconColor;
  final Color backgroundColor;
  final String tooltip;

  const OverlayCloseButton({
    super.key,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.backgroundColor = const Color(0x33FFFFFF),
    this.tooltip = 'Close',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: iconColor,
        shape: const CircleBorder(),
      ),
      icon: Icon(Icons.close, color: iconColor, size: 22),
    );
  }
}
