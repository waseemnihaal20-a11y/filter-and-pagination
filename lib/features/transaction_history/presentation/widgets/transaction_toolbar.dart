import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../utils/transaction_status_text.dart';

/// Search field and status dropdown.
///
/// Side by side (search expanded on the left, status on the right) when the
/// search field would still show its whole hint; otherwise stacked, so
/// neither a narrow screen nor large text can overflow or truncate. The hint
/// is measured at the current text size, so the decision follows the font
/// scale: tablets and landscape phones get one row, portrait phones two.
class TransactionToolbar extends StatelessWidget {
  const TransactionToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilterChanged,
  });

  static const List<TransactionStatus?> filters = [
    null,
    ...TransactionStatus.values,
  ];

  static const String searchHint = 'Search merchant or reference';

  static const double _dropdownWidth = 140;
  static const double _gap = 12;

  /// Space a text field needs besides its text: the prefix icon, the room
  /// kept for the clear button, and the borders' padding.
  static const double _searchChrome = 48 + 48 + 8;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final TransactionStatus? filter;
  final ValueChanged<TransactionStatus?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final search = _SearchField(
      controller: searchController,
      onChanged: onSearchChanged,
    );
    final dropdown = _StatusDropdown(
      filter: filter,
      onChanged: onFilterChanged,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dropdownWidth = textScaler.scale(_dropdownWidth);
          final inlineWidth =
              _hintWidth(context) +
              textScaler.scale(_searchChrome) +
              _gap +
              dropdownWidth;
          if (constraints.maxWidth >= inlineWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: search),
                const SizedBox(width: _gap),
                SizedBox(width: dropdownWidth, child: dropdown),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: _gap),
              dropdown,
            ],
          );
        },
      ),
    );
  }

  /// Width of [searchHint] in the text field's style at the current scale.
  double _hintWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: searchHint,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Icons grow with the text so they stay in proportion at large sizes.
    final iconSize = MediaQuery.textScalerOf(context).scale(24);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: TransactionToolbar.searchHint,
        // Wraps rather than truncates when large text makes it too wide.
        hintMaxLines: 2,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.search, size: iconSize),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  // A semantic label rather than a tooltip, so screen readers
                  // announce it as the button's label.
                  icon: Icon(
                    Icons.close,
                    size: iconSize,
                    semanticLabel: 'Clear search',
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.filter, required this.onChanged});

  final TransactionStatus? filter;
  final ValueChanged<TransactionStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TransactionStatus?>(
      // Re-created when the filter changes, so the field always shows the
      // cubit's filter.
      key: ValueKey(filter),
      initialValue: filter,
      isExpanded: true,
      iconSize: MediaQuery.textScalerOf(context).scale(24),
      decoration: const InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final option in TransactionToolbar.filters)
          DropdownMenuItem(
            value: option,
            child: Text(filterLabel(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
