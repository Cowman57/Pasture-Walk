# PastureWalk Application Context Guide

## Overview
**PastureWalk** is a Flutter-based cross-platform farm management app for recording paddock covers, grazing data, and farm KPIs. Primary platform is Android with iOS, macOS, Windows, Linux, and Web support.

## Quick Reference

### Project Structure
```
Pasture-Walk/
├── lib/                    # Dart source code
│   ├── main.dart          # App entry point
│   ├── app.dart           # App widget & theme
│   ├── models.dart        # Data models (Paddock, Herd, Grazing, GrazingSlot, etc.)
│   ├── storage.dart       # Data persistence layer
│   ├── utils.dart         # Utility functions (DST-safe calendar helpers)
│   ├── screens/           # UI screens
│   │   ├── grazing_plan_setup_screen.dart  # Herds & grazing breaks setup
│   │   └── ...
│   └── widgets/           # Reusable components
│       ├── grazing_planner.dart            # Drag-and-drop planning calendar
│       └── grazing_calendar_board.dart     # Legacy board (used by schedule preview)
├── android/               # Android-specific config
├── ios/                   # iOS-specific config
├── macos/                 # macOS-specific config
├── windows/               # Windows-specific config
├── linux/                 # Linux-specific config
├── web/                   # Web-specific config
├── test/                  # Unit/widget tests
└── pubspec.yaml          # Dependencies & metadata
```

### Key Commands
```bash
# Development
flutter run                # Run app with hot reload
flutter build apk --release  # Build Android APK
flutter analyze           # Run code analysis
flutter test              # Run tests

# Platform-specific builds
flutter build ios --release
flutter build macos --release
flutter build windows --release
flutter build linux --release
flutter build web --release
```

## Data Models (lib/models.dart)

### Core Entities
- **`Paddock`**: Farm paddock with area, rotation order, silage status (`isSilage`, `shutForSilage`)
- **`Herd`**: Animal group with `cowCount`, `areaGrazedPerDayHa` (**the daily target**), and supplement
- **`GrazingSlot`**: A recurring grazing break (slot) belonging to a herd — `label`, `hours`, `sortOrder`. (A legacy `targetAreaHa` field is kept for backup compatibility but is no longer used.)
- **`Measurement`**: Paddock cover measurement with GPS location
- **`Grazing`**: Grazing event. Beyond paddock/date/pre/post/harvest it carries:
  - `slotId` — the break it fulfils (null = unassigned)
  - `areaHa` — actual area grazed for this record (null = full paddock); enables partial/split breaks
  - `groupId` — links records that form one planned block (a paddock across breaks/days)
  - `durationDays` — multi-day run length
- **`GrowthModifier`**: Environmental factor affecting growth
- **`Note`**: Text note with GPS location
- **`SilageCut`**: Silage harvesting record

### Grazing planning model
- **Daily target** lives only on the herd (`areaGrazedPerDayHa`), entered directly or via **m²/cow/day** (linked by cow count). Breaks have no targets.
- A paddock placed into a break writes one `Grazing` record per (break, day-run). A block spanning several breaks/days shares a `groupId` and moves/resizes as a unit.
- **Area allocation conventions** (see `grazing_accuracy_screen.dart`, `home_screen.dart`, `grazing_planner.dart`):
  - Multi-day runs are **spread across their days** (area/duration per day).
  - A paddock grazed in **multiple slots on the same day is split** across them (counted once per day, not double-counted).
  - Partial-paddock records use `g.areaHa ?? paddock.areaHa`.

### Serialization Pattern
All models use `toMap()` and `fromMap()` methods for JSON serialization:
```dart
Map<String, dynamic> toMap() {
  return {
    'id': id,
    'name': name,
    // ... other fields
  };
}

static Paddock fromMap(Map<String, dynamic> map) {
  return Paddock(
    id: map['id'],
    name: map['name'],
    // ... other fields
  );
}
```

## Storage Layer (lib/storage.dart)

### Key Methods
- `getPaddocks()`, `savePaddocks()` - CRUD for paddocks
- `getHerds()`, `saveHerds()` - CRUD for herds (holds the daily target)
- `loadGrazingSlots()`, `saveGrazingSlots()`, `slotsForHerd()` - CRUD for grazing breaks
- `getMeasurements()`, `saveMeasurements()` - CRUD for measurements
- `getGrazings()`, `saveGrazings()` - CRUD for grazing events
- `loadCalendarVisibleCols()`, `saveCalendarVisibleCols()` - planner zoom level
- `exportBackupJson()`, `restoreBackupJson()` - backup/restore **all** SharedPreferences keys (paddocks, herds, slots, grazings incl. `slotId`/`areaHa`/`groupId`, settings)
- `clearAllData()` - Reset all data

### Storage Backend
- Uses `shared_preferences` package
- Data stored as JSON strings in SharedPreferences (keys: `paddocks`, `grazings`, `grazing_slots_json`, `herds_json`, `calendar_visible_cols`, …)
- Platform-agnostic persistence

## Screens (lib/screens/)

### Main Screens
1. **`home_screen.dart`** - Main dashboard with map view; hosts the Summary / Paddocks / **Grazings** / Map tabs
2. **`round_screen.dart`** - Paddock recording interface
3. **`settings_screen.dart`** - App configuration
4. **`kpis_screen.dart`** - Farm performance metrics
5. **`paddock_history_screen.dart`** - Historical paddock data
6. **`grazing_accuracy_screen.dart`** - Grazing analysis
7. **`grazing_plan_setup_screen.dart`** - Set up herds and grazing breaks
8. **`activity_log_screen.dart`** - Activity history
9. **`farm_map_import_screen.dart`** - Map/GIS import

### Grazings tab
- Top-bar **Planner | List** toggle (icon-only) on the Grazings tab.
- **Planner** (`widgets/grazing_planner.dart`): timesheet-style grid (days = rows, breaks = columns, frozen date column + header). Column-width zoom snaps to a whole number of columns and is persisted. Bottom palette lists paddocks by **predicted cover** for drag-to-place. Tap a box to select (shows greyed extend boxes), drag to move, long-press for details.
- **List**: flat date-ordered list with herd·break·area; long-press for multi-select edit/delete.

### Navigation Pattern
Direct screen navigation (no formal router):
```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (context) => NextScreen()),
);
```

## Widgets (lib/widgets/)

### Reusable Components
- `grazing_planner.dart` - farm-wide drag-and-drop grazing planner (grid + palette)
- `grazing_calendar_board.dart` - legacy Gantt board (still used by the schedule preview screen)
- Map-related widgets (farm maps, GPS overlay)
- Data input forms
- Chart visualizations
- List views with filtering

## Dependencies (pubspec.yaml)

### Key Packages
- **UI**: `flutter`, `material`
- **Storage**: `shared_preferences`
- **Maps**: `flutter_map`, `latlong2`, `proj4dart`
- **Location**: `geolocator`
- **Files**: `file_picker`, `file_selector`, `archive`, `shapefile`
- **Utilities**: `uuid`, `intl`, `http`, `url_launcher`
- **Caching**: `flutter_map_cache`, `dio_cache_interceptor_hive_store`

## Build Configuration

### Android (android/)
- `key.properties` - Release signing keys
- `AndroidManifest.xml` - Permissions (location, storage)
- `build.gradle.kts` - Build configuration

### iOS (ios/)
- `Info.plist` - Location permissions required
- Xcode project with Flutter integration

### Multi-platform
Each platform has Flutter runner integration and platform-specific optimizations.

## Development Workflow

### Setup
1. Install Flutter SDK (3.9.0+)
2. Install Android SDK/Java (OpenJDK 11-17) or Xcode for iOS
3. Run `flutter pub get` to install dependencies
4. For Android: Configure `local.properties` with SDK path

### Development
- Use VS Code with Flutter/Dart extensions
- Hot reload available: `flutter run`
- Code analysis: `flutter analyze`
- Linting rules from `analysis_options.yaml`

### Testing
- Basic widget test in `test/widget_test.dart`
- Focus on manual testing for agricultural use cases
- No extensive automated test suite currently

## Architecture Patterns

### State Management
- Classic Flutter `StatefulWidget` pattern
- No external state management libraries
- Local state within screens

### Data Flow
1. UI → User input
2. Screen → Business logic
3. Storage → Persist to SharedPreferences
4. Models → Data structure validation

### Error Handling
- Basic `try-catch` for storage operations
- User-friendly error messages
- Graceful degradation for missing features

## Key Features Implementation

### Map Integration
- `flutter_map` for farm mapping
- GPS overlay with `geolocator`
- Shapefile import (NZTM/EPSG:2193 projection)
- Farm boundary visualization

### GPS Features
- Auto-selection of nearest paddock
- Location-based data recording
- Coordinate projection between systems

### Data Import/Export
- Shapefile import for farm boundaries
- JSON-based data backup/restore
- Cross-platform file operations

### KPI Calculations
- Growth rate calculations
- Cover trends analysis
- Grazing accuracy metrics
- Feed requirement calculations

### Date arithmetic (DST safety)
- **Never** advance calendar days with `date.add(Duration(days: n))` — across a daylight-saving change that shifts an hour and can skip/duplicate a day. Use calendar construction instead: `DateTime(d.year, d.month, d.day + n)` (see `utils.dart`, `grazing_planner.dart`, `storage.dart`).
- `calendarDay(d)` (in `utils.dart`) strips the time to compare days.

## Code Conventions

### Naming
- Screen files: `*_screen.dart`
- Widget files: `*_widget.dart` or in `widgets/` directory
- Models: PascalCase (Paddock, Herd)
- Methods: camelCase with descriptive names

### Code Style
- Dart null safety enabled
- Material Design 3 components
- Consistent indentation (2 spaces)
- Descriptive variable names

### Comments
- Complex logic has explanatory comments
- TODO/FIXME markers for future work
- API documentation for public methods

## Platform-Specific Considerations

### Android
- Primary deployment platform
- APK distribution via GitHub Releases
- Location and storage permissions required
- Release signing with keystore

### iOS
- Location permissions in Info.plist
- Xcode project configuration
- App Store distribution possible

### Desktop (Windows, macOS, Linux)
- File system access
- Window management
- Platform-native menus

### Web
- PWA configuration in `web/` directory
- IndexedDB for storage
- Responsive design

## Common Tasks & Solutions

### Adding a New Screen
1. Create `lib/screens/new_screen.dart`
2. Implement as `StatefulWidget`
3. Add navigation from existing screen
4. Update storage if new data type needed

### Adding New Data Field
1. Update model in `models.dart`
2. Add `toMap()`/`fromMap()` support
3. Update storage methods in `storage.dart`
4. Update relevant screens

### Map Feature Development
- Use `flutter_map` and `latlong2`
- Coordinate projection with `proj4dart`
- GPS integration with `geolocator`
- Cache maps with `flutter_map_cache`

### Testing Changes
- Run `flutter analyze` for code quality
- Test on target platform (Android recommended)
- Verify data persistence
- Check GPS/map functionality if relevant

## Troubleshooting

### Common Issues
1. **Build failures**: Check Flutter version (3.9.0+)
2. **Missing dependencies**: Run `flutter pub get`
3. **Android SDK path**: Configure `local.properties`
4. **Location permissions**: Verify platform config
5. **Map loading**: Check internet connection for tile servers

### Debugging
- Use Flutter DevTools for performance profiling
- Check console output for errors
- Test with sample farm data
- Verify GPS simulation in emulator

## Performance Considerations

- Maps can be resource-intensive (caching enabled)
- Large farm datasets may affect list performance
- GPS updates impact battery life
- Cross-platform builds increase complexity

## Security Notes

- No sensitive data transmitted externally
- Local storage only (no cloud sync)
- File import/export requires user permission
- Release builds signed with Android keystore

## Future Development Areas

1. Cloud sync functionality
2. Enhanced data visualization
3. More automated calculations
4. Additional farm management features
5. Improved testing coverage

---

*This context file provides AI agents with the essential knowledge to work effectively in the PastureWalk codebase. Update as the codebase evolves.*