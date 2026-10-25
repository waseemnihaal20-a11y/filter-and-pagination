import 'package:flutter/material.dart';

import 'core/demo/request_failure_switch.dart';
import 'features/transaction_history/domain/repositories/transaction_repository.dart';
import 'features/transaction_history/presentation/pages/transaction_history_page.dart';

class TransactionHistoryApp extends StatelessWidget {
  const TransactionHistoryApp({
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
    return MaterialApp(
      title: 'Transactions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A4FD6)),
      ),
      home: TransactionHistoryPage(
        repository: repository,
        failureSwitch: failureSwitch,
        searchDebounce: searchDebounce,
      ),
    );
  }
}
