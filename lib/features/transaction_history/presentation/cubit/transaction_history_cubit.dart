import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/transaction.dart';
import '../../domain/errors/transaction_fetch_exception.dart';
import '../../domain/usecases/get_saved_first_page.dart';
import '../../domain/usecases/get_paginated_transactions.dart';
import '../../domain/usecases/save_first_page.dart';
import 'transaction_history_state.dart';

/// Loads, filters, searches, paginates and refreshes the transaction history.
///
/// ## Request generations
///
/// Responses can arrive out of order: the user may switch filter, change the
/// search, or pull to refresh while an older request is still in flight.
/// Every operation that replaces the list (first load, retry of the first
/// page, filter change, search change, refresh) increments [_generation].
/// Every request and every cache read captures the generation it started in,
/// and when its result arrives it is dropped unless that generation is still
/// current and the cubit is still open. This means:
///
/// * a slow response for a previous filter or search never overwrites the
///   new one;
/// * a next-page response that started before a refresh is never appended to
///   the refreshed list;
/// * a slow cache read never replaces newer rows, and only current first
///   pages are written to the cache;
/// * nothing is emitted after [close].
///
/// Duplicate next-page requests are prevented separately by [loadNextPage],
/// which only runs while [NextPageStatus.idle].
///
/// ## Saved results
///
/// Every successful first page is saved under its filter and search. Loading
/// a first page shows the saved rows for that query (if any) while the fresh
/// request runs; see [TransactionHistoryState.isShowingSavedResults].
///
/// The cubit depends only on domain use cases, never on the data layer.
class TransactionHistoryCubit extends Cubit<TransactionHistoryState> {
  TransactionHistoryCubit({
    required GetPaginatedTransactions getPaginatedTransactions,
    required GetSavedFirstPage getSavedFirstPage,
    required SaveFirstPage saveFirstPage,
    Duration searchDebounce = const Duration(milliseconds: 300),
  }) : _getPaginatedTransactions = getPaginatedTransactions,
       _getSavedFirstPage = getSavedFirstPage,
       _saveFirstPage = saveFirstPage,
       _searchDebounce = searchDebounce,
       super(const TransactionHistoryState());

  final GetPaginatedTransactions _getPaginatedTransactions;
  final GetSavedFirstPage _getSavedFirstPage;
  final SaveFirstPage _saveFirstPage;

  final Duration _searchDebounce;

  int _generation = 0;

  Timer? _searchTimer;

  /// Trimmed search text waiting for [_searchTimer], if any.
  String? _pendingSearch;

  bool _isCurrent(int generation) => !isClosed && generation == _generation;

  Future<void> loadInitial() => _loadFirstPage(state.filter, state.searchQuery);

  Future<void> retryFirstPage() =>
      _loadFirstPage(state.filter, state.searchQuery);

  /// Switches to [filter] (`null` = All) and loads its first page.
  ///
  /// A search that is still waiting for its debounce is applied at the same
  /// time, so the result matches what the user sees in the search field.
  /// Does nothing if [filter] and the search are unchanged and the first page
  /// is loaded or loading. After a first-page failure selecting the same
  /// filter again retries.
  Future<void> selectFilter(TransactionStatus? filter) async {
    final searchQuery = _takePendingSearch() ?? state.searchQuery;
    if (filter == state.filter &&
        searchQuery == state.searchQuery &&
        state.firstPageStatus != FirstPageStatus.failure) {
      return;
    }
    await _loadFirstPage(filter, searchQuery);
  }

  /// Called on every change of the search field.
  ///
  /// The search is applied once [text] has been unchanged for the debounce
  /// duration, so typing quickly sends one request. Applying it resets
  /// pagination and starts a new generation. Surrounding whitespace is
  /// ignored, so text that only differs from the current search by
  /// whitespace sends no request.
  void searchChanged(String text) {
    final searchQuery = text.trim();
    _takePendingSearch();
    if (searchQuery == state.searchQuery &&
        state.firstPageStatus != FirstPageStatus.failure) {
      return;
    }
    _pendingSearch = searchQuery;
    _searchTimer = Timer(_searchDebounce, () {
      final pending = _takePendingSearch();
      if (pending != null) _loadFirstPage(state.filter, pending);
    });
  }

  /// Cancels the debounce timer and returns the search it was waiting for.
  String? _takePendingSearch() {
    _searchTimer?.cancel();
    _searchTimer = null;
    final pending = _pendingSearch;
    _pendingSearch = null;
    return pending;
  }

  /// Loads the page after the current rows.
  ///
  /// A no-op unless the first page has loaded, there is a next page, no other
  /// next-page request is running or has failed, and no refresh is running.
  /// After a failure only [retryNextPage] tries again, so scrolling never
  /// hammers a failing endpoint.
  Future<void> loadNextPage() async {
    final offset = state.nextOffset;
    if (state.firstPageStatus != FirstPageStatus.success ||
        offset == null ||
        state.nextPageStatus != NextPageStatus.idle ||
        state.isRefreshing) {
      return;
    }
    await _loadPageFrom(offset);
  }

  /// Retries the failed next-page request with the same offset.
  Future<void> retryNextPage() async {
    final offset = state.nextOffset;
    if (state.nextPageStatus != NextPageStatus.failure ||
        offset == null ||
        state.isRefreshing) {
      return;
    }
    await _loadPageFrom(offset);
  }

  /// Reloads the first page for the current filter and search and replaces
  /// the list.
  ///
  /// Current rows stay visible while refreshing. If the refresh fails while
  /// fresh rows are shown they are kept and
  /// [TransactionHistoryState.refreshFailureCount] is incremented; otherwise
  /// the first-page error state is shown (keeping saved rows, if any). The
  /// returned future completes when the refresh has finished, so it can be
  /// awaited by a `RefreshIndicator`.
  Future<void> refresh() async {
    final generation = ++_generation;
    final filter = state.filter;
    final searchQuery = state.searchQuery;
    emit(
      state.copyWith(isRefreshing: true, nextPageStatus: NextPageStatus.idle),
    );
    try {
      final page = await _getPaginatedTransactions(
        status: filter,
        query: searchQuery,
      );
      if (!_isCurrent(generation)) return;
      emit(
        TransactionHistoryState(
          filter: filter,
          searchQuery: searchQuery,
          transactions: page.transactions,
          nextOffset: page.nextOffset,
          firstPageStatus: FirstPageStatus.success,
          refreshFailureCount: state.refreshFailureCount,
        ),
      );
      _save(filter, searchQuery, page.transactions);
    } on TransactionFetchException {
      if (!_isCurrent(generation)) return;
      final hasVisibleRows =
          state.firstPageStatus == FirstPageStatus.success &&
          state.transactions.isNotEmpty;
      emit(
        hasVisibleRows
            ? state.copyWith(
                isRefreshing: false,
                refreshFailureCount: state.refreshFailureCount + 1,
              )
            : state.copyWith(
                isRefreshing: false,
                firstPageStatus: FirstPageStatus.failure,
              ),
      );
    }
  }

  Future<void> _loadFirstPage(
    TransactionStatus? filter,
    String searchQuery,
  ) async {
    final generation = ++_generation;
    // Retrying while saved rows are shown keeps them on screen.
    final keepSavedRows =
        state.isShowingSavedResults &&
        state.filter == filter &&
        state.searchQuery == searchQuery;
    emit(
      keepSavedRows
          ? state.copyWith(firstPageStatus: FirstPageStatus.loading)
          : TransactionHistoryState(
              filter: filter,
              searchQuery: searchQuery,
              refreshFailureCount: state.refreshFailureCount,
            ),
    );
    final request = _getPaginatedTransactions(
      status: filter,
      query: searchQuery,
    );
    if (!keepSavedRows) {
      unawaited(_showSavedRows(generation, filter, searchQuery));
    }
    try {
      final page = await request;
      if (!_isCurrent(generation)) return;
      emit(
        state.copyWith(
          transactions: page.transactions,
          nextOffset: () => page.nextOffset,
          firstPageStatus: FirstPageStatus.success,
          isShowingSavedResults: false,
        ),
      );
      _save(filter, searchQuery, page.transactions);
    } on TransactionFetchException {
      if (!_isCurrent(generation)) return;
      emit(state.copyWith(firstPageStatus: FirstPageStatus.failure));
    }
  }

  /// Shows the saved first page for the query, unless fresh rows have
  /// already arrived or a newer generation has started meanwhile.
  Future<void> _showSavedRows(
    int generation,
    TransactionStatus? filter,
    String searchQuery,
  ) async {
    final saved = await _getSavedFirstPage(status: filter, query: searchQuery);
    if (!_isCurrent(generation) ||
        state.firstPageStatus == FirstPageStatus.success ||
        saved == null ||
        saved.isEmpty) {
      return;
    }
    emit(state.copyWith(transactions: saved, isShowingSavedResults: true));
  }

  /// Saves a fresh first page in the background. Callers only call this for
  /// the current generation, so a stale response is never saved.
  void _save(
    TransactionStatus? filter,
    String searchQuery,
    List<Transaction> transactions,
  ) {
    unawaited(
      _saveFirstPage(
        status: filter,
        query: searchQuery,
        transactions: transactions,
      ),
    );
  }

  Future<void> _loadPageFrom(int offset) async {
    final generation = _generation;
    emit(state.copyWith(nextPageStatus: NextPageStatus.loading));
    try {
      final page = await _getPaginatedTransactions(
        offset: offset,
        status: state.filter,
        query: state.searchQuery,
      );
      if (!_isCurrent(generation)) return;
      final knownIds = {for (final t in state.transactions) t.id};
      emit(
        state.copyWith(
          transactions: [
            ...state.transactions,
            ...page.transactions.where((t) => !knownIds.contains(t.id)),
          ],
          nextOffset: () => page.nextOffset,
          nextPageStatus: NextPageStatus.idle,
        ),
      );
    } on TransactionFetchException {
      if (!_isCurrent(generation)) return;
      emit(state.copyWith(nextPageStatus: NextPageStatus.failure));
    }
  }

  @override
  Future<void> close() {
    _takePendingSearch();
    return super.close();
  }
}
