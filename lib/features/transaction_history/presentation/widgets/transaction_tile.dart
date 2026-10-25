import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../../../../core/formatting/date_formatter.dart';
import '../../../../core/formatting/money_formatter.dart';
import '../utils/transaction_status_text.dart';
import 'status_badge.dart';

/// One row of the history list.
///
/// Uses [Wrap] instead of a fixed two-column [Row] so that with large text or
/// a narrow screen the amount and status move onto their own line instead of
/// overflowing. Screen readers get a single combined label for the row and a
/// tap hint, e.g. "double tap to view details" on Android.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onTap,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondaryColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final amount = formatMoney(
      transaction.amountMinor,
      transaction.currencyCode,
    );
    final date = formatTransactionDate(transaction.createdAt);
    final reference = transaction.reference;

    return Semantics(
      label: semanticsLabel(transaction),
      button: true,
      onTap: onTap,
      onTapHint: 'view details',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(transaction.merchantName, style: textTheme.titleMedium),
                  Text(
                    amount,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    date,
                    style: textTheme.bodyMedium?.copyWith(
                      color: secondaryColor,
                    ),
                  ),
                  StatusBadge(status: transaction.status),
                ],
              ),
              if (reference != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Ref: $reference',
                  style: textTheme.bodySmall?.copyWith(color: secondaryColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// E.g. "Swiggy, ₹1,299.00, Pending, 20 Oct 2026, 6:00 PM, reference SWG-1".
  static String semanticsLabel(Transaction transaction) {
    final reference = transaction.reference;
    return [
      transaction.merchantName,
      formatMoney(transaction.amountMinor, transaction.currencyCode),
      transaction.status.label,
      formatTransactionDate(transaction.createdAt),
      if (reference != null) 'reference $reference',
    ].join(', ');
  }
}
