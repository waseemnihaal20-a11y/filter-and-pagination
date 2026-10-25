import 'package:equatable/equatable.dart';

import 'transaction.dart';

/// One batch of transactions returned by a paginated request, plus the
/// offset to request the next batch from.
///
/// This is pagination data, not UI: screens live in `presentation/pages/`.
class PaginatedTransactions extends Equatable {
  PaginatedTransactions({
    required List<Transaction> transactions,
    this.nextOffset,
  }) : transactions = List.unmodifiable(transactions);

  /// The transactions in this batch, newest first. Unmodifiable.
  final List<Transaction> transactions;

  /// Offset of the next batch, or `null` when there is nothing more.
  final int? nextOffset;

  @override
  List<Object?> get props => [transactions, nextOffset];
}
