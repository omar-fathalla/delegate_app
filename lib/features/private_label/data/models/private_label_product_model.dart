import 'package:delegate_app/features/private_label/data/models/private_label_json.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';

/// Firestore: `/organizations/{organizationUID}/private_label_products/{id}`
class PrivateLabelProductModel extends PrivateLabelProduct {
  const PrivateLabelProductModel({
    required super.id,
    required super.organizationUID,
    required super.name,
    super.barcode,
    super.category,
    super.referencePrice,
    super.isActive,
  });

  factory PrivateLabelProductModel.fromJson(Map<String, dynamic> json, String id) {
    return PrivateLabelProductModel(
      id: id,
      organizationUID: PrivateLabelJson.parseString(json['organizationUID']),
      name: PrivateLabelJson.parseString(json['name']),
      barcode: PrivateLabelJson.parseNullableString(json['barcode']),
      category: PrivateLabelJson.parseNullableString(json['category']),
      referencePrice: PrivateLabelJson.parseDouble(json['referencePrice']),
      isActive: json['isActive'] != false,
    );
  }

  factory PrivateLabelProductModel.fromEntity(PrivateLabelProduct p) {
    return PrivateLabelProductModel(
      id: p.id,
      organizationUID: p.organizationUID,
      name: p.name,
      barcode: p.barcode,
      category: p.category,
      referencePrice: p.referencePrice,
      isActive: p.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'organizationUID': organizationUID,
        'name': name.trim(),
        'barcode': barcode,
        'category': category,
        'referencePrice': referencePrice,
        'isActive': isActive,
      };

  Map<String, dynamic> toLocalJson() => {'id': id, ...toJson()};

  factory PrivateLabelProductModel.fromLocalJson(Map<String, dynamic> json) =>
      PrivateLabelProductModel.fromJson(json, PrivateLabelJson.parseString(json['id']));
}
