import 'package:flutter/material.dart';

/// Strip above saved (cached) rows: either "updating" with a small spinner,
/// or "couldn't update" with Retry.
class SavedResultsBanner extends StatelessWidget {
  const SavedResultsBanner({
    super.key,
    required this.updateFailed,
    required this.onRetry,
  });

  final bool updateFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final spinnerSize = MediaQuery.textScalerOf(context).scale(14);

    return Material(
      color: updateFailed
          ? colorScheme.errorContainer
          : colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: updateFailed
              ? [
                  Text(
                    "Couldn't update. Showing saved results.",
                    style: textStyle?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ]
              : [
                  SizedBox.square(
                    dimension: spinnerSize,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Showing saved results · Updating…',
                      style: textStyle?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
