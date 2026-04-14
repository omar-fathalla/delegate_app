# Company Search Feature

## Overview
A complete company search feature with infinite scroll pagination, built using Clean Architecture and Material Design 3.

## Features
- ✅ Search companies by company code (`companyCodeInOrg`)
- ✅ Infinite scroll pagination (20 items per page)
- ✅ Material Design 3 UI components
- ✅ Arabic and English language support
- ✅ Real-time search with debouncing
- ✅ Loading states and error handling
- ✅ Pull-to-refresh functionality

## Architecture
```
lib/features/admin/
├── domain/
│   ├── entities/company.dart
│   ├── repositories/company_repository.dart
│   └── usecases/
│       ├── search_companies_by_code.dart
│       └── get_companies.dart
├── data/
│   ├── models/company_model.dart
│   ├── datasources/company_remote_datasource.dart
│   └── repositories/company_repository_impl.dart
└── presentation/
    ├── bloc/
    │   ├── company_search_bloc.dart
    │   ├── company_search_event.dart
    │   └── company_search_state.dart
    ├── pages/company_search_screen.dart
    └── widgets/
        ├── company_search_bar.dart
        ├── company_search_list.dart
        └── company_list_item.dart
```

## Usage

### Navigation
```dart
context.push('/admin/company-search', extra: organizationUID);
```

### BLoC Events
- `SearchCompaniesRequested` - Start new search
- `LoadMoreCompaniesRequested` - Load next page
- `ClearSearchRequested` - Clear search results
- `RefreshSearchRequested` - Refresh current search

### BLoC States
- `CompanySearchInitial` - Initial state
- `CompanySearchLoading` - Loading first page
- `CompanySearchLoadingMore` - Loading additional pages
- `CompanySearchSuccess` - Results loaded successfully
- `CompanySearchEmpty` - No results found
- `CompanySearchError` - Error occurred

## Firestore Query
The search uses a range query on the `companyCodeInOrg` field:
```dart
.where('companyCodeInOrg', isGreaterThanOrEqualTo: companyCode)
.where('companyCodeInOrg', isLessThan: '$companyCode\uf8ff')
.orderBy('companyCodeInOrg')
```

## Required Firestore Index
```json
{
  "collectionGroup": "companies",
  "queryScope": "COLLECTION", 
  "fields": [
    {
      "fieldPath": "companyCodeInOrg",
      "order": "ASCENDING"
    }
  ]
}
```

## Translations
All UI text is localized in both Arabic and English:
- `searchCompanies` - Screen title
- `searchCompaniesHint` - Search hint text
- `enterCompanyCode` - Input placeholder
- `noCompaniesFound` - Empty state message
- `errorOccurred` - Error message
- `tryAgain` - Retry button

## Dependencies
- `flutter_bloc` - State management
- `cloud_firestore` - Database queries
- `equatable` - Value equality
- `get_it` - Dependency injection

## Testing
Run diagnostics to ensure no compilation errors:
```bash
flutter analyze lib/features/admin/
```

## Performance
- Pagination with 20 items per page
- Efficient Firestore queries with proper indexing
- Lazy loading of additional pages
- Memory-efficient list rendering with ListView.builder

## Future Enhancements
- [ ] Add filters (company type, status, etc.)
- [ ] Add sorting options
- [ ] Add company details navigation
- [ ] Add search history
- [ ] Add offline caching