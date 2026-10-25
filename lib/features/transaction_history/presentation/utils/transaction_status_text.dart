import '../../domain/entities/transaction.dart';

/// User-facing text for statuses and filters.
extension TransactionStatusText on TransactionStatus {
  String get label => switch (this) {
    TransactionStatus.completed => 'Completed',
    TransactionStatus.pending => 'Pending',
    TransactionStatus.failed => 'Failed',
  };
}

/// Label of a status filter option; `null` is "All".
String filterLabel(TransactionStatus? filter) => filter?.label ?? 'All';

/// Empty-state message for a filter and search, e.g. "No pending
/// transactions" or "No pending transactions matching 'swig'".
String emptyMessage(TransactionStatus? filter, [String searchQuery = '']) {
  final transactions = filter == null
      ? 'transactions'
      : '${filter.label.toLowerCase()} transactions';
  if (searchQuery.isNotEmpty) return "No $transactions matching '$searchQuery'";
  return filter == null ? 'No transactions yet' : 'No $transactions';
}
