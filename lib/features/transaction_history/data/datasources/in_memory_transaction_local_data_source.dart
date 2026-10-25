import '../../domain/entities/transaction.dart';
import '../models/saved_page_codec.dart';
import 'transaction_local_data_source.dart';

/// [TransactionLocalDataSource] that keeps entries in memory, for tests.
///
/// Entries are stored in the same JSON form as the persistent cache, so tests
/// exercise the real encoding and can plant corrupt entries in [entries].
class InMemoryTransactionLocalDataSource implements TransactionLocalDataSource {
  /// Raw stored JSON by cache key.
  final Map<String, String> entries = {};

  @override
  Future<List<Transaction>?> readFirstPage(String key) async =>
      decodeSavedPage(entries[key]);

  @override
  Future<void> writeFirstPage(
    String key,
    List<Transaction> transactions,
  ) async => entries[key] = encodeSavedPage(transactions);
}
