---
description: Run code generation for freezed, json_serializable, and injectable using build_runner.
---

# Run Code Generation

## When to use

Run code generation after modifying files that use:
- `@freezed` / `@Freezed` annotations (freezed)
- `@JsonSerializable()` annotations (json_serializable)
- `@injectable` / `@lazySingleton` annotations (injectable)

## 1. Ensure dev dependencies exist

Check `pubspec.yaml` has:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  injectable_generator: ^2.6.0
```

If missing, add them:

// turbo
```
flutter pub add --dev build_runner freezed json_serializable injectable_generator
```

## 2. Run build_runner

// turbo
```
dart run build_runner build --delete-conflicting-outputs
```

This generates:
- `*.freezed.dart` files for freezed classes
- `*.g.dart` files for json_serializable
- `injection_container.config.dart` for injectable

## 3. Watch mode (during development)

For automatic regeneration during development:

```
dart run build_runner watch --delete-conflicting-outputs
```

## 4. Clean generated files (if needed)

If you get conflicts or stale files:

// turbo
```
dart run build_runner clean
```

Then re-run step 2.

## 5. Verify

// turbo
```
flutter analyze
```

Ensure no analysis errors after generation.

## Freezed Model Example

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'delegate_model.freezed.dart';
part 'delegate_model.g.dart';

@freezed
class DelegateModel with _$DelegateModel {
  const factory DelegateModel({
    required String uid,
    required String firstName,
    required String lastName,
    required String nationalityID,  // Match existing Firestore schema!
    required String organizationUID,
    required String companyUID,
  }) = _DelegateModel;

  factory DelegateModel.fromJson(Map<String, dynamic> json)
      => _$DelegateModelFromJson(json);
}
```

**REMINDER:** JSON keys must match the existing camelCase Firestore schema exactly. Use `@JsonKey(name: 'fieldName')` if the Dart field name differs.
