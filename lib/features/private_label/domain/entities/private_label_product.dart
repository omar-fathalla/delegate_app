import 'package:equatable/equatable.dart';

/// Catalog item for the organization's private label products.
///
/// [referencePrice] is the official price used to detect shelf price mismatches.
class PrivateLabelProduct extends Equatable {
  final String id;
  final String organizationUID;
  final String name;
  final String? barcode;
  final String? category;
  final double? referencePrice;
  final bool isActive;

  const PrivateLabelProduct({
    required this.id,
    required this.organizationUID,
    required this.name,
    this.barcode,
    this.category,
    this.referencePrice,
    this.isActive = true,
  });

  PrivateLabelProduct copyWith({
    String? id,
    String? name,
    String? barcode,
    String? category,
    double? referencePrice,
    bool? isActive,
  }) {
    return PrivateLabelProduct(
      id: id ?? this.id,
      organizationUID: organizationUID,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      referencePrice: referencePrice ?? this.referencePrice,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props =>
      [id, organizationUID, name, barcode, category, referencePrice, isActive];
}
