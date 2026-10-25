import 'package:flutter/material.dart';

import '../cubit/transaction_history_state.dart';

/// Last item of the list: next-page spinner, retry, or end-of-list marker.
class ListFooter extends StatelessWidget {
  const ListFooter({
    super.key,
    required this.nextPageStatus,
    required this.hasReachedEnd,
    required this.onRetry,
  });

  final NextPageStatus nextPageStatus;
  final bool hasReachedEnd;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondaryColor = Theme.of(context).colorScheme.onSurfaceVariant;

    final Widget child = switch (nextPageStatus) {
      NextPageStatus.loading => const CircularProgressIndicator(
        semanticsLabel: 'Loading more transactions',
      ),
      NextPageStatus.failure => Column(
        children: [
          Text(
            "Couldn't load more transactions",
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
      NextPageStatus.idle when hasReachedEnd => Text(
        'No more transactions',
        textAlign: TextAlign.center,
        style: textTheme.bodySmall?.copyWith(color: secondaryColor),
      ),
      NextPageStatus.idle => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(child: child),
    );
  }
}
