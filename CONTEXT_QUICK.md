# PastureWalk Quick Reference

## 🚀 Project Type
Flutter farm management app (Android primary, iOS/Web/Desktop support)

## 📁 Key Files
- `lib/main.dart` - Entry point
- `lib/models.dart` - Data models (Paddock, Herd, Measurement, Grazing)
- `lib/storage.dart` - CRUD operations with SharedPreferences
- `lib/screens/home_screen.dart` - Main dashboard (1658+ lines)

## 🔧 Commands
```bash
flutter run              # Run with hot reload
flutter build apk --release  # Build Android APK
flutter analyze          # Check code quality
flutter test             # Run tests
```

## 🗄️ Data Models
- **Paddock**: Farm area with attributes
- **Herd**: Animal group with feeding needs
- **Measurement**: Cover readings with GPS
- **Grazing**: Paddock grazing events

## 💾 Storage Pattern
```dart
// All models use this pattern
Map<String, dynamic> toMap() { ... }
static Model fromMap(Map<String, dynamic> map) { ... }
```

## 🧭 Navigation
Direct navigation:
```dart
Navigator.of(context).push(MaterialPageRoute(builder: (context) => Screen()));
```

## 🗺️ Map Features
- `flutter_map` with GPS overlay
- Shapefile import (NZTM/EPSG:2193)
- Auto-paddock selection by location

## 🏗️ Architecture
- StatefulWidget pattern (no external state libs)
- SharedPreferences for local storage
- Material Design 3 UI

## 📱 Platforms
- Android (primary, APK releases)
- iOS, macOS, Windows, Linux, Web
- Multi-platform Flutter builds

## 🔗 Key Dependencies
- Maps: `flutter_map`, `latlong2`, `proj4dart`
- Storage: `shared_preferences`
- Location: `geolocator`
- Files: `file_picker`, `shapefile`

## ⚡ Quick Tasks

### Add Screen
1. Create `lib/screens/new_screen.dart`
2. Add navigation from existing screen
3. Update storage if needed

### Add Data Field
1. Update model in `models.dart`
2. Add `toMap()`/`fromMap()` support
3. Update `storage.dart` methods
4. Update relevant screens

### Test Changes
```bash
flutter analyze
flutter run  # Test on target platform
```

## 🚨 Common Issues
- Android SDK: Configure `local.properties`
- Dependencies: Run `flutter pub get`
- Location: Check platform permissions
- Maps: Needs internet for tile servers

## 📝 Conventions
- Screen files: `*_screen.dart`
- Widget files: `*_widget.dart` or in `widgets/`
- Models: PascalCase
- Methods: camelCase with descriptive names

---

*Last updated: 2026-09-14*