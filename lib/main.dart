import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/demo/request_failure_switch.dart';
import 'features/transaction_history/data/datasources/fake_transaction_remote_data_source.dart';
import 'features/transaction_history/data/datasources/shared_preferences_transaction_local_data_source.dart';
import 'features/transaction_history/data/repositories/transaction_repository_impl.dart';

/// Composition root: the only place that knows every layer. It builds the
/// data layer and hands the app the domain repository.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final failureSwitch = RequestFailureSwitch();
  final repository = TransactionRepositoryImpl(
    remote: FakeTransactionRemoteDataSource(failureSwitch: failureSwitch),
    local: SharedPreferencesTransactionLocalDataSource(preferences),
  );
  runApp(
    TransactionHistoryApp(repository: repository, failureSwitch: failureSwitch),
  );
}
