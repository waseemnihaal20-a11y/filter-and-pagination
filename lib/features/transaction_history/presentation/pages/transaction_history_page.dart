import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/demo/request_failure_switch.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/get_saved_first_page.dart';
import '../../domain/usecases/get_paginated_transactions.dart';
import '../../domain/usecases/save_first_page.dart';
import '../cubit/transaction_history_cubit.dart';
import '../cubit/transaction_history_state.dart';
import 'transaction_details_page.dart';
import '../utils/transaction_status_text.dart';
import '../widgets/fail_all_requests_switch.dart';
import '../widgets/list_footer.dart';
import '../widgets/saved_results_banner.dart';
import '../widgets/status_views.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/transaction_toolbar.dart';

/// Entry point of the feature. It receives the domain [TransactionRepository]
/// (never a data-layer class) and the demo failure switch, so tests can
/// replace both.
class TransactionHistoryPage extends StatelessWidget {
  const TransactionHistoryPage({
    super.key,
    required this.repository,
    required this.failureSwitch,
    this.searchDebounce = const Duration(milliseconds: 300),
  });

  final TransactionRepository repository;
  final RequestFailureSwitch failureSwitch;
  final Duration searchDebounce;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TransactionHistoryCubit(
        getPaginatedTransactions: GetPaginatedTransactions(repository),
        getSavedFirstPage: GetSavedFirstPage(repository),
        saveFirstPage: SaveFirstPage(repository),
        searchDebounce: searchDebounce,
      )..loadInitial(),
      child: TransactionHistoryView(failureSwitch: failureSwitch),
    );
  }
}

class TransactionHistoryView extends StatefulWidget {
  const TransactionHistoryView({super.key, required this.failureSwitch});

  final RequestFailureSwitch failureSwitch;

  @override
  State<TransactionHistoryView> createState() => _TransactionHistoryViewState();
}

class _TransactionHistoryViewState extends State<TransactionHistoryView> {
  /// Start loading the next page when this close to the end of the list.
  static const double _loadMoreThreshold = 300;

  /// `keepScrollOffset: false` so a list rebuilt for a new filter starts at
  /// the top instead of restoring the previous filter's offset.
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreIfNearEnd);
  }

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Asks for the next page when the user is near the end, or when the
  /// loaded rows do not fill the viewport (nothing to scroll). The cubit
  /// ignores the call if a request is already running, has failed, or the
  /// end has been reached.
  void _loadMoreIfNearEnd() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.hasContentDimensions &&
        position.extentAfter < _loadMoreThreshold) {
      context.read<TransactionHistoryCubit>().loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: MultiBlocListener(
        listeners: [
          BlocListener<TransactionHistoryCubit, TransactionHistoryState>(
            listenWhen: (previous, current) =>
                previous.refreshFailureCount != current.refreshFailureCount,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't refresh. Showing previous results.",
                    ),
                  ),
                );
            },
          ),
          BlocListener<TransactionHistoryCubit, TransactionHistoryState>(
            listenWhen: (previous, current) =>
                previous != current &&
                current.firstPageStatus == FirstPageStatus.success &&
                current.nextPageStatus == NextPageStatus.idle &&
                !current.hasReachedEnd &&
                !current.isRefreshing,
            listener: (context, state) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _loadMoreIfNearEnd(),
              );
            },
          ),
        ],
        child: Column(
          children: [
            FailAllRequestsSwitch(failureSwitch: widget.failureSwitch),
            BlocSelector<
              TransactionHistoryCubit,
              TransactionHistoryState,
              TransactionStatus?
            >(
              selector: (state) => state.filter,
              builder: (context, filter) {
                final cubit = context.read<TransactionHistoryCubit>();
                return TransactionToolbar(
                  searchController: _searchController,
                  onSearchChanged: cubit.searchChanged,
                  filter: filter,
                  onFilterChanged: cubit.selectFilter,
                );
              },
            ),
            Expanded(
              child:
                  BlocBuilder<TransactionHistoryCubit, TransactionHistoryState>(
                    builder: _buildContent,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TransactionHistoryState state) {
    final cubit = context.read<TransactionHistoryCubit>();
    if (state.isShowingSavedResults) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SavedResultsBanner(
            updateFailed: state.firstPageStatus == FirstPageStatus.failure,
            onRetry: cubit.retryFirstPage,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: cubit.refresh,
              // No footer: saved rows have no next offset, so there is nothing to
              // paginate until fresh rows arrive.
              child: _buildList(state.transactions),
            ),
          ),
        ],
      );
    }
    final Widget scrollable;
    switch (state.firstPageStatus) {
      case FirstPageStatus.loading:
        return const LoadingView();
      case FirstPageStatus.failure:
        scrollable = MessageView(
          icon: Icons.cloud_off,
          message: "Couldn't load transactions.",
          onRetry: cubit.retryFirstPage,
        );
      case FirstPageStatus.success when state.isEmpty:
        scrollable = MessageView(
          icon: Icons.receipt_long,
          message: emptyMessage(state.filter, state.searchQuery),
        );
      case FirstPageStatus.success:
        scrollable = _buildList(
          state.transactions,
          footer: ListFooter(
            nextPageStatus: state.nextPageStatus,
            hasReachedEnd: state.hasReachedEnd,
            onRetry: cubit.retryNextPage,
          ),
        );
    }
    return RefreshIndicator(onRefresh: cubit.refresh, child: scrollable);
  }

  Widget _buildList(List<Transaction> rows, {Widget? footer}) {
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length + (footer == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => index < rows.length
          ? TransactionTile(
              key: ValueKey(rows[index].id),
              transaction: rows[index],
              onTap: () => _openDetails(rows[index]),
            )
          : footer,
    );
  }

  void _openDetails(Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailsPage(transaction: transaction),
      ),
    );
  }
}
