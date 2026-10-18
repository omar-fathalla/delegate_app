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
  final String? imageUrl;
  final bool isActive;

  const PrivateLabelProduct({
    required this.id,
    required this.organizationUID,
    required this.name,
    this.barcode,
    this.category,
    this.referencePrice,
    this.imageUrl,
    this.isActive = true,
  });

  /// Default 4 Fathalla Private Label catalog products with generated images.
  static List<PrivateLabelProduct> defaultCatalog(String organizationUID) => [
        PrivateLabelProduct(
          id: 'default_wixmax',
          organizationUID: organizationUID,
          name: 'wixmax',
          barcode: '62245165342547',
          category: 'منظفات وعناية',
          referencePrice: 58.0,
          imageUrl: 'assets/images/private_label/wixmax.jpg',
          isActive: true,
        ),
        PrivateLabelProduct(
          id: 'default_fathalla_rice_1kg',
          organizationUID: organizationUID,
          name: 'أرز فتح الله 1 كيلو',
          barcode: '6224001001015',
          category: 'بقالة جافة',
          referencePrice: 35.0,
          imageUrl: 'assets/images/private_label/fathalla_rice_1kg.jpg',
          isActive: true,
        ),
        PrivateLabelProduct(
          id: 'default_fathalla_sugar_1kg',
          organizationUID: organizationUID,
          name: 'سكر فتح الله 1 كيلو',
          barcode: '6224001001022',
          category: 'بقالة جافة',
          referencePrice: 32.0,
          imageUrl: 'assets/images/private_label/fathalla_sugar_1kg.jpg',
          isActive: true,
        ),
        PrivateLabelProduct(
          id: 'default_fathalla_oil_1l',
          organizationUID: organizationUID,
          name: 'زيت خليط فتح الله 1 لتر',
          barcode: '6224001001039',
          category: 'زيوت وسمن',
          referencePrice: 65.0,
          imageUrl: 'assets/images/private_label/fathalla_oil_1l.jpg',
          isActive: true,
        ),
      ];

  PrivateLabelProduct copyWith({
    String? id,
    String? name,
    String? barcode,
    String? category,
    double? referencePrice,
    String? imageUrl,
    bool? isActive,
  }) {
    return PrivateLabelProduct(
      id: id ?? this.id,
      organizationUID: organizationUID,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      referencePrice: referencePrice ?? this.referencePrice,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [
        id,
        organizationUID,
        name,
        barcode,
        category,
        referencePrice,
        imageUrl,
        isActive,
      ];
}

