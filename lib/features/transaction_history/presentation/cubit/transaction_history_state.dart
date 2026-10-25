import 'package:equatable/equatable.dart';

import '../../domain/entities/transaction.dart';

/// Status of the first page for the current filter and search.
enum FirstPageStatus { loading, success, failure }

/// Status of loading the page after the rows already shown.
enum NextPageStatus { idle, loading, failure }

class TransactionHistoryState extends Equatable {
  const TransactionHistoryState({
    this.filter,
    this.searchQuery = '',
    this.transactions = const [],
    this.nextOffset,
    this.firstPageStatus = FirstPageStatus.loading,
    this.nextPageStatus = NextPageStatus.idle,
    this.isRefreshing = false,
    this.refreshFailureCount = 0,
    this.isShowingSavedResults = false,
  });

  /// Selected status filter; `null` means "All".
  final TransactionStatus? filter;

  /// Search text that [transactions] match, trimmed; empty means no search.
  final String searchQuery;

  /// Rows loaded so far for [filter] and [searchQuery], in display order.
  final List<Transaction> transactions;

  /// Offset of the next page; `null` once the end has been reached.
  final int? nextOffset;

  final FirstPageStatus firstPageStatus;

  final NextPageStatus nextPageStatus;

  /// True while a pull-to-refresh is in flight. Current rows stay visible.
  final bool isRefreshing;

  /// Incremented every time a refresh fails while rows are visible. The UI
  /// shows one SnackBar per increment, so a failure is never replayed on
  /// rebuild and two consecutive failures still produce two SnackBars.
  final int refreshFailureCount;

  /// True while [transactions] are saved rows from the offline cache rather
  /// than a fresh first page. [firstPageStatus] is then
  /// [FirstPageStatus.loading] (updating) or [FirstPageStatus.failure]
  /// (the update failed). Pagination is disabled until fresh rows arrive,
  /// because saved rows have no next offset.
  final bool isShowingSavedResults;

  bool get hasReachedEnd => nextOffset == null;

  bool get isEmpty =>
      firstPageStatus == FirstPageStatus.success && transactions.isEmpty;

  /// Nullable fields take a function so they can be explicitly set to `null`.
  TransactionHistoryState copyWith({
    List<Transaction>? transactions,
    int? Function()? nextOffset,
    FirstPageStatus? firstPageStatus,
    NextPageStatus? nextPageStatus,
    bool? isRefreshing,
    int? refreshFailureCount,
    bool? isShowingSavedResults,
  }) {
    return TransactionHistoryState(
      filter: filter,
      searchQuery: searchQuery,
      transactions: transactions ?? this.transactions,
      nextOffset: nextOffset != null ? nextOffset() : this.nextOffset,
      firstPageStatus: firstPageStatus ?? this.firstPageStatus,
      nextPageStatus: nextPageStatus ?? this.nextPageStatus,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshFailureCount: refreshFailureCount ?? this.refreshFailureCount,
      isShowingSavedResults:
          isShowingSavedResults ?? this.isShowingSavedResults,
    );
  }

  @override
  List<Object?> get props => [
    filter,
    searchQuery,
    transactions,
    nextOffset,
    firstPageStatus,
    nextPageStatus,
    isRefreshing,
    refreshFailureCount,
    isShowingSavedResults,
  ];
}
