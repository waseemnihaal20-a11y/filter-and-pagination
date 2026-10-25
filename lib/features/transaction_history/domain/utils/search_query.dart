/// Normalizes search text for matching and for cache keys: surrounding
/// whitespace is ignored and matching is case-insensitive. An empty result
/// means "no search".
String normalizeSearchQuery(String? query) =>
    (query ?? '').trim().toLowerCase();
