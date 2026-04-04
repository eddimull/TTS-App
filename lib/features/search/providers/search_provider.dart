import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/search_models.dart';
import '../data/search_repository.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results,
    this.isLoading = false,
    this.error,
  });

  final String query;
  final SearchResults? results;
  final bool isLoading;
  final String? error;

  SearchState copyWith({
    String? query,
    SearchResults? results,
    bool clearResults = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: clearResults ? null : (results ?? this.results),
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() {
    // Cancel the debounce timer when this notifier is disposed (e.g. tab exit).
    ref.onDispose(() => _debounce?.cancel());
    return const SearchState();
  }

  void search(String query) {
    // Cancel any in-flight debounce timer.
    _debounce?.cancel();

    final trimmed = query.trim();

    // Clear results immediately when query is too short.
    if (trimmed.length < 2) {
      state = state.copyWith(
        query: trimmed,
        clearResults: true,
        isLoading: false,
        clearError: true,
      );
      return;
    }

    // Show loading right away so the UI feels responsive.
    state = state.copyWith(query: trimmed, isLoading: true, clearError: true);

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final repo = ref.read(searchRepositoryProvider);
      try {
        final results = await repo.search(trimmed);
        // Guard: a newer keystroke may have already cancelled this query.
        if (state.query == trimmed) {
          state = state.copyWith(results: results, isLoading: false);
        }
      } catch (e) {
        if (state.query == trimmed) {
          state = state.copyWith(
            isLoading: false,
            error: e.toString(),
            clearResults: true,
          );
        }
      }
    });
  }
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
