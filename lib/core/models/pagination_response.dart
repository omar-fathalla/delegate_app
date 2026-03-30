import 'package:cloud_firestore/cloud_firestore.dart';

class PaginationResponse<T> {
  final List<T> items;
  final DocumentSnapshot? lastDoc;
  final bool hasReachedMax;

  PaginationResponse({
    required this.items,
    this.lastDoc,
    required this.hasReachedMax,
  });
}
