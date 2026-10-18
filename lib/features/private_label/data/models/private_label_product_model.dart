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
    super.imageUrl,
    super.isActive,
  });

  factory PrivateLabelProductModel.fromJson(Map<String, dynamic> json, String id) {
    final name = PrivateLabelJson.parseString(json['name']);
    final barcode = PrivateLabelJson.parseNullableString(json['barcode']);
    var imageUrl = PrivateLabelJson.parseNullableString(json['imageUrl'] ?? json['photoUrl']);
    if (imageUrl == null || imageUrl.isEmpty) {
      imageUrl = _resolveDefaultImage(id: id, name: name, barcode: barcode);
    }
    return PrivateLabelProductModel(
      id: id,
      organizationUID: PrivateLabelJson.parseString(json['organizationUID']),
      name: name,
      barcode: barcode,
      category: PrivateLabelJson.parseNullableString(json['category']),
      referencePrice: PrivateLabelJson.parseDouble(json['referencePrice']),
      imageUrl: imageUrl,
      isActive: json['isActive'] != false,
    );
  }

  static String? _resolveDefaultImage({
    required String id,
    required String name,
    String? barcode,
  }) {
    final lower = name.trim().toLowerCase();
    if (id == 'default_wixmax' || lower == 'wixmax' || barcode == '62245165342547') {
      return 'assets/images/private_label/wixmax.jpg';
    }
    if (id == 'default_fathalla_rice_1kg' ||
        lower.contains('أرز فتح الله') ||
        lower.contains('ارز فتح الله') ||
        barcode == '6224001001015') {
      return 'assets/images/private_label/fathalla_rice_1kg.jpg';
    }
    if (id == 'default_fathalla_sugar_1kg' ||
        lower.contains('سكر فتح الله') ||
        barcode == '6224001001022') {
      return 'assets/images/private_label/fathalla_sugar_1kg.jpg';
    }
    if (id == 'default_fathalla_oil_1l' ||
        lower.contains('زيت خليط فتح الله') ||
        lower.contains('زيت فتح الله') ||
        barcode == '6224001001039') {
      return 'assets/images/private_label/fathalla_oil_1l.jpg';
    }
    return null;
  }

  factory PrivateLabelProductModel.fromEntity(PrivateLabelProduct p) {
    return PrivateLabelProductModel(
      id: p.id,
      organizationUID: p.organizationUID,
      name: p.name,
      barcode: p.barcode,
      category: p.category,
      referencePrice: p.referencePrice,
      imageUrl: p.imageUrl,
      isActive: p.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'organizationUID': organizationUID,
        'name': name.trim(),
        'barcode': barcode,
        'category': category,
        'referencePrice': referencePrice,
        'imageUrl': imageUrl,
        'isActive': isActive,
      };

  Map<String, dynamic> toLocalJson() => {'id': id, ...toJson()};

  factory PrivateLabelProductModel.fromLocalJson(Map<String, dynamic> json) =>
      PrivateLabelProductModel.fromJson(json, PrivateLabelJson.parseString(json['id']));
}

