import '../../domain/entities/transaction.dart';
import '../../domain/utils/search_query.dart';

/// Local (on-device) source of saved first pages: the last successfully
/// loaded first page per query, so the list can show saved rows immediately
/// on startup while fresh data loads.
///
/// Only rows are stored, never a next offset: a saved offset could point
/// into data that has changed since, so pagination always waits for a fresh
/// first page.
abstract class TransactionLocalDataSource {
  /// Cache key for a status filter (`null` = All) and search text. The search
  /// is normalized, so "Swig " and "swig" share an entry.
  static String keyFor(TransactionStatus? status, String query) =>
      '${status?.name ?? 'all'}|${normalizeSearchQuery(query)}';

  /// The saved first page for [key], or `null` if nothing usable is stored.
  ///
  /// A corrupt or unreadable entry is reported as `null`, never as an error.
  Future<List<Transaction>?> readFirstPage(String key);

  /// Replaces the saved first page for [key].
  Future<void> writeFirstPage(String key, List<Transaction> transactions);
}
