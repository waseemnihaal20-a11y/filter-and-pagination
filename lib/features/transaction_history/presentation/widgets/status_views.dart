import 'package:flutter/material.dart';

/// Centered spinner for the first page.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(semanticsLabel: 'Loading transactions'),
    );
  }
}

/// Full-screen message for the empty and first-page error states.
///
/// Always scrollable (and at least as tall as the viewport) so pull-to-refresh
/// still works and large text can scroll instead of overflowing.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (retry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: retry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
