import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../utils/transaction_status_text.dart';

/// Status shown as icon + text + colour, so it never relies on colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background) = switch (status) {
      TransactionStatus.completed => (
        Icons.check_circle_outline,
        const Color(0xFF1B5E20),
        const Color(0xFFE8F5E9),
      ),
      TransactionStatus.pending => (
        Icons.schedule,
        const Color(0xFF7A4F01),
        const Color(0xFFFFF4D6),
      ),
      TransactionStatus.failed => (
        Icons.error_outline,
        const Color(0xFFB71C1C),
        const Color(0xFFFDECEA),
      ),
    };
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: MediaQuery.textScalerOf(context).scale(16),
              color: foreground,
            ),
            const SizedBox(width: 4),
            Flexible(child: Text(status.label, style: textStyle)),
          ],
        ),
      ),
    );
  }
}
