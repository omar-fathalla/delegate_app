---
name: pagination_system
description: Guidelines for implementing infinite scroll pagination (10-20 items) using Flutter, BLoC, and Firestore.
---

# Pagination System Skill

## Overview
This skill provides a standardized approach for implementing **infinite scroll pagination** in the Delegate App. It ensures that data is fetched in manageable chunks (typically 10-20 items) to optimize performance and reduce Firestore read costs.

## Core Principles
1.  **Batch Loading:** Fetch 10-20 items initially.
2.  **Scroll Trigger:** Automatically request the next batch when the user reaches ~90% of the scroll extent.
3.  **State Management:** Track the `lastDocument` in the BLoC state to use for `startAfterDocument` in Firestore queries.
4.  **Loading Indicators:** Show a loading spinner at the bottom of the list when more data is being fetched.

## Implementation Steps

### 1. BLoC Logic
The BLoC should manage:
-   `items`: The list of all currently loaded items.
-   `lastDoc`: The Firestore document snapshot of the last item (for pagination).
-   `hasReachedMax`: A boolean to stop fetching when no more data is available.
-   `status`: To handle initial loading, pagination loading, and errors.

### 2. UI (ScrollController)
-   Initialize a `ScrollController` in `initState`.
-   Add a listener that checks if the user is near the bottom.
-   Dispose the controller in `dispose`.

```dart
void _onScroll() {
  if (_isBottom) {
    context.read<YourBloc>().add(LoadMoreRequested());
  }
}

bool get _isBottom {
  if (!_scrollController.hasClients) return false;
  final maxScroll = _scrollController.position.maxScrollExtent;
  final currentScroll = _scrollController.offset;
  return currentScroll >= (maxScroll * 0.9);
}
```

### 3. Firestore Query
Use `.limit(20)` and `.startAfterDocument(lastDoc)` for pagination.

## Example Templates
-   **Bloc Template:** `examples/pagination_bloc_template.dart`
-   **View Template:** `examples/pagination_view_template.dart`

## When to Use
-   Any screen displaying a list of data from Firestore (Tasks, Attendance Logs, Delegates).
-   When data set size is unknown or potentially large.

## Limitations
-   Ensure composite indexes are created in Firestore for queries involving filters and sorting.
-   Handle "No Data" and "End of List" states gracefully in the UI.
