import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Shared empty / loading / permission / failure panels with a next action.
class StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accent;

  const StatusPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  factory StatusPanel.loading({required String title, String? message}) {
    return StatusPanel(
      icon: Icons.hourglass_top,
      title: title,
      message: message ?? 'Please wait…',
      accent: AppColors.gps,
    );
  }

  factory StatusPanel.permissionDenied({
    required String title,
    required String message,
    VoidCallback? onAction,
  }) {
    return StatusPanel(
      icon: Icons.lock_outline,
      title: title,
      message: message,
      actionLabel: 'Open settings',
      onAction: onAction,
      accent: AppColors.alertWarningBorder,
    );
  }

  factory StatusPanel.empty({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return StatusPanel(
      icon: Icons.inbox_outlined,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      accent: AppColors.textSecondary,
    );
  }

  factory StatusPanel.failure({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return StatusPanel(
      icon: Icons.error_outline,
      title: title,
      message: message,
      actionLabel: actionLabel ?? 'Try again',
      onAction: onAction,
      accent: AppColors.trustLow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.textSecondary;
    return Semantics(
      container: true,
      label: '$title. $message',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
