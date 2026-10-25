import 'package:flutter/material.dart';

import '../../../../core/demo/request_failure_switch.dart';

/// Always-visible demo toggle for the "Fail all requests" switch.
///
/// Toggling does not refetch; the next request (scroll, filter, search,
/// refresh or retry) shows the effect. While on, the row is tinted and shows
/// a helper line so it is obvious that the app is in failure mode. Screen
/// readers hear "Fail all requests" plus the switch state; the helper line is
/// visual only because the state already says the same thing.
class FailAllRequestsSwitch extends StatelessWidget {
  const FailAllRequestsSwitch({super.key, required this.failureSwitch});

  static const Color _warningTint = Color(0xFFFFF4D6);
  static const Color _warningText = Color(0xFF7A4F01);

  final RequestFailureSwitch failureSwitch;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: failureSwitch,
      builder: (context, failAllRequests, _) => Material(
        color: failAllRequests
            ? _warningTint
            : Theme.of(context).colorScheme.surfaceContainerLow,
        child: SwitchListTile(
          dense: true,
          title: const Text('Fail all requests'),
          subtitle: failAllRequests
              ? const ExcludeSemantics(
                  child: Text(
                    'All requests will fail',
                    style: TextStyle(color: _warningText),
                  ),
                )
              : null,
          secondary: Icon(
            failAllRequests ? Icons.warning_amber : Icons.science_outlined,
            color: failAllRequests ? _warningText : null,
          ),
          value: failAllRequests,
          onChanged: (enabled) => failureSwitch.failAllRequests = enabled,
        ),
      ),
    );
  }
}
