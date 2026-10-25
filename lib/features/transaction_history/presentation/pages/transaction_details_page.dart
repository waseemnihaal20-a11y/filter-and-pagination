import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../../../../core/formatting/date_formatter.dart';
import '../../../../core/formatting/money_formatter.dart';
import '../widgets/status_badge.dart';

/// Read-only details of one transaction.
///
/// It receives the [Transaction] from the list and never refetches: the list
/// row already holds every field.
class TransactionDetailsPage extends StatelessWidget {
  const TransactionDetailsPage({super.key, required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction details')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.merchantName, style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  formatMoney(
                    transaction.amountMinor,
                    transaction.currencyCode,
                  ),
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                StatusBadge(status: transaction.status),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          _DetailRow(
            label: 'Date',
            value: formatTransactionDate(transaction.createdAt),
          ),
          _DetailRow(
            label: 'UTC time',
            value: formatUtcTimestamp(transaction.createdAt),
          ),
          _DetailRow(
            label: 'Reference',
            value: transaction.reference ?? 'No reference',
          ),
          _DetailRow(label: 'Transaction ID', value: transaction.id),
        ],
      ),
    );
  }
}

/// A label above a selectable value, read as one item by screen readers.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(value, style: textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
