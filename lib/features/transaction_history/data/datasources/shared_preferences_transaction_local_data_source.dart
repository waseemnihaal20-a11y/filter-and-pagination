import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/transaction.dart';
import '../models/saved_page_codec.dart';
import 'transaction_local_data_source.dart';

/// [TransactionLocalDataSource] backed by `shared_preferences`, one JSON string per key.
class SharedPreferencesTransactionLocalDataSource
    implements TransactionLocalDataSource {
  SharedPreferencesTransactionLocalDataSource(this._preferences);

  static const String _keyPrefix = 'transaction_history.first_page.';

  final SharedPreferences _preferences;

  @override
  Future<List<Transaction>?> readFirstPage(String key) async {
    // `get` rather than `getString`, which throws if the stored value is not a
    // string; a wrong type is just another corrupt entry.
    final raw = _preferences.get('$_keyPrefix$key');
    return decodeSavedPage(raw is String ? raw : null);
  }

  @override
  Future<void> writeFirstPage(String key, List<Transaction> transactions) =>
      _preferences.setString('$_keyPrefix$key', encodeSavedPage(transactions));
}
