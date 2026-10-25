import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_local_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/datasources/transaction_remote_data_source.dart';
import 'package:filter_and_pagination/features/transaction_history/data/repositories/transaction_repository_impl.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/get_saved_first_page.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/get_paginated_transactions.dart';
import 'package:filter_and_pagination/features/transaction_history/domain/usecases/save_first_page.dart';
import 'package:filter_and_pagination/features/transaction_history/presentation/cubit/transaction_history_cubit.dart';

/// Wires a cubit the same way the app does (data sources → repository →
/// use cases → cubit), so cubit tests exercise the real layers in between.
TransactionHistoryCubit buildCubit(
  TransactionRemoteDataSource remote, {
  TransactionLocalDataSource? cache,
  Duration searchDebounce = const Duration(milliseconds: 300),
}) {
  final repository = TransactionRepositoryImpl(remote: remote, local: cache);
  return TransactionHistoryCubit(
    getPaginatedTransactions: GetPaginatedTransactions(repository),
    getSavedFirstPage: GetSavedFirstPage(repository),
    saveFirstPage: SaveFirstPage(repository),
    searchDebounce: searchDebounce,
  );
}
