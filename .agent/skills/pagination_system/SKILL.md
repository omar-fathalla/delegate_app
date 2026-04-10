# Pagination System Skill

## Overview
Implements Infinite Scroll Pagination for Flutter lists using BLoC pattern and Firestore `startAfterDocument`.

## When to Use
- Any screen that loads a list from Firestore
- When the list could have more than 20 items
- To improve app performance and loading speed

## Pattern
- Load 20 items initially
- Load 20 more when user scrolls near the bottom (200px threshold)
- Show loading indicator at the bottom while fetching more
- Use `startAfterDocument` for Firestore cursor-based pagination

## Examples
See `examples/pagination_bloc_template.dart` and `examples/pagination_view_template.dart`
