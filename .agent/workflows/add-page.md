---
description: Add a new page with go_router navigation, including route definition, Material 3 page scaffold, and RTL support.
---

# Add a New Page with GoRouter

## 1. Create the Page Widget

Create `lib/features/<feature>/presentation/pages/<feature>_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page Title'),  // Use localized string
      ),
      body: BlocProvider(
        create: (_) => sl<FeatureBloc>()..add(const LoadRequested()),
        child: BlocBuilder<FeatureBloc, FeatureState>(
          builder: (context, state) {
            return switch (state) {
              FeatureLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              FeatureLoaded(:final data) => _buildContent(data),
              FeatureError(:final message) => Center(
                child: Text(message),
              ),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}
```

## 2. Define the Route

Add the route to your `go_router` configuration:

```dart
GoRoute(
  path: '/feature',
  name: 'feature',
  builder: (context, state) => const FeaturePage(),
),
```

For nested routes with parameters:
```dart
GoRoute(
  path: '/delegates/:delegateId',
  name: 'delegateDetail',
  builder: (context, state) {
    final delegateId = state.pathParameters['delegateId']!;
    return DelegateDetailPage(delegateId: delegateId);
  },
),
```

## 3. Navigate to the Page

```dart
// Named navigation
context.goNamed('feature');

// With parameters
context.goNamed('delegateDetail', pathParameters: {'delegateId': id});

// Push (adds to stack)
context.pushNamed('feature');
```

## 4. RTL & Material 3 Checklist

- ✅ Use `TextDirection.rtl` aware layouts (use `start`/`end` not `left`/`right`)
- ✅ Use `EdgeInsetsDirectional` instead of `EdgeInsets`
- ✅ Use `Align` with `AlignmentDirectional` for directional alignment
- ✅ Wrap text in localization functions
- ✅ Use Material 3 components: `FilledButton`, `OutlinedButton`, `Card.filled()`
- ✅ Use `Theme.of(context).colorScheme` for colors
- ✅ **CRITICAL FOR ARABIC FONTS:** When using `GoogleFonts.cairo` inside buttons or constrained height widgets, ALWAYS set `height: 1.2` (or similar) in the `TextStyle` to prevent the text from being vertically clipped or hidden.

## 5. Verify

// turbo
```
flutter analyze
```
