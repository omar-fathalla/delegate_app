import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class PaginationResponse<T> extends Equatable {
  final List<T> items;
  final DocumentSnapshot? lastDoc;
  final bool hasReachedMax;

  const PaginationResponse({
    required this.items,
    this.lastDoc,
    required this.hasReachedMax,
  });

  @override
  List<Object?> get props => [items, lastDoc, hasReachedMax];

  PaginationResponse<T> copyWith({
    List<T>? items,
    DocumentSnapshot? lastDoc,
    bool? hasReachedMax,
  }) {
    return PaginationResponse<T>(
      items: items ?? this.items,
      lastDoc: lastDoc ?? this.lastDoc,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
    );
  }
}
