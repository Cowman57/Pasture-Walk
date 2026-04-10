---
name: Grazings map data UX batch
overview: "Bulk future-grazing actions, map measure mode, GPS copy, label floors, water troughs, paddock history edit/delete, future-grazing cow indicators, unified Settings activity log with batch delete, plus Settings copy."
todos:
  - id: storage-crud
    content: "Add Storage: delete/update by id for Measurement, Grazing, Note; grazing bulk delete + updateGrazing; water troughs prefs + CRUD; map layer toggle key"
    status: pending
  - id: history-edit-delete
    content: "Paddock history: row menus, edit dialogs, delete confirm for covers/grazings/notes"
    status: pending
  - id: grazings-tab-bulk
    content: "Home Grazings tab: delete all upcoming + per-row reschedule; refresh home"
    status: pending
  - id: map-measure-labels
    content: "Home Map: measure mode (distance/area), polyline/polygon + stats; label opacity floor for names"
    status: pending
  - id: water-troughs
    content: "WaterTrough model, water_troughs_screen.dart, map markers + layer toggle"
    status: pending
  - id: settings-instructions
    content: "Clarify GPS walk toggle in Settings; Instructions bullets for new features"
    status: pending
  - id: future-grazing-indicators
    content: "Paddocks column + Map: future-grazing cow symbol; map blue border always; cow marker only when show3 (same as notes)"
    status: pending
  - id: settings-activity-log
    content: "New Settings screen: unified changelog (covers, grazings, notes); columns date, type, paddock, summary; multi-select + batch delete"
    status: pending
isProject: true
---

# Grazings tab, map tools, layers, and single-event edit/delete

## Clarification (existing vs new)

- **Settings → GPS measuring** today controls **live GPS follow + auto-switch paddock while recording** (`round_screen.dart` `_maybeStartGpsLiveTracking`), not ruler/area on the map. The plan will **rename/clarify** that toggle and add a **separate map measure mode** on the Home Map tab.

---

## 1. Future grazings: bulk delete and reschedule (`home_screen.dart`, `storage.dart`)

**Storage**

- `Future<int> deleteGrazingsWhere(bool Function(Grazing g) test)` — load grazings, `removeWhere`, save (or targeted: `deleteGrazingsByIds(Set<String> ids)`).
- `Future<void> updateGrazing(Grazing updated)` — replace by `id` in list, save.
- Optionally `Future<int> deleteAllFutureGrazings()` as sugar: `g.at.isAfter(DateTime.now())`.

**UI (Grazings tab)**

- When **Upcoming** section has items, show an **app bar row** or **overflow menu** (e.g. “Delete all upcoming” / “Reschedule…”).
- **Bulk delete:** confirm dialog “Delete all N upcoming grazings?”
- **Reschedule:** minimum viable **per-row** “Reschedule” → `showDatePicker` → `updateGrazing` with new `at`.

**Refresh:** call `_refreshHome()` after mutations.

---

## 2. Map: distance / area measure (new behaviour) (`home_screen.dart`)

- Local state: `MeasureMode` (`off`, `distance`, `area`), `List<LatLng> measurePoints`, display length (haversine sum) and area (closed polygon; document formula).
- Toolbar: Off | Distance | Area; Undo / Clear; show m and ha.
- Map `onTap` adds vertices when mode ≠ off; draw polyline/polygon layers.

---

## 3. Surface GPS walk feature + copy (`settings_screen.dart`, `instructions_screen.dart`)

- Subtitle under the switch explaining auto-advance while recording.

---

## 4. Paddock labels “always on” (`home_screen.dart`)

- Raise opacity **floor** for the **name** line in centroid labels; reduce zoom-only fade for line 1 only.

---

## 5. Water troughs optional layer

- Model + `Storage` key; CRUD; `MarkerLayer`; Settings → manage screen; persisted “show troughs” toggle.

---

## 6. Edit / delete single events (`storage.dart`, `paddock_history_screen.dart`)

- `delete*ById` / `update*` for Measurement, Grazing, Note.
- Row menus + dialogs on Covers / Grazings / Notes tabs.

---

## 7. Future grazing indicators — Paddocks list + Map (new)

**Data**

- **`_RowData`:** add `bool hasFutureGrazing` — true if any stored grazing for that paddock has `g.at.isAfter(DateTime.now())`. Compute in `_buildRows` using the same grazings batch already loaded (or one pass over `gsAll`).
- **`_MapPoly`:** add `bool hasFutureGrazing` (or pass a `Set<String>` into `_buildMapPolys` and set per polygon). Derive from `loadAllGrazings()` in the map `FutureBuilder` batch (already loads notes; add grazings if not present) or precompute `paddockIdsWithFutureGrazing`.

**Paddocks tab (cow column)**

- Show a **cow / scheduled indicator** when `hasFutureGrazing` is true.
- **Visual distinction vs “grazed recently”:** existing UI uses 🐄 for `r.grazed` (last grazing within 3 days). For **future** grazings use a **different** treatment so they are not confused, e.g. **`Icons.pets` size 16 in blue** (`colorScheme.primary` or fixed `Colors.blue.shade700`), or outlined icon + tooltip “Scheduled grazing”. If a paddock is both recently grazed **and** has a future event, stack both icons (same column).

**Map**

- **Border (all zoom levels):** in the `PolygonLayer` builder, if `p.hasFutureGrazing` (and not excluded), set **`borderColor`** to **blue** and a slightly thicker `borderStrokeWidth` so the paddock is visible at every zoom. **Precedence:** if `selectionMode && selected`, keep existing selection styling (stronger blue / width) or document stacking order (selection wins).
- **Cow symbol (zoom-gated, same logic as notes):** in the `MarkerLayer` loop ([`home_screen.dart`](lib/screens/home_screen.dart) ~990–1043), notes render when `p.pending && show3`, where **`show3`** is `lines.length >= 3` (same predicate that controls full three-line label: polygon large enough on screen + zoom so `_labelLines` returns three lines). Add a second marker when **`p.hasFutureGrazing && show3`**, using a **cow** icon (`Icons.pets` or `Icons.agriculture` to match Paddocks). **Offset** the marker so it does not sit on top of the note marker (notes use `Alignment.topRight` + `Transform.translate(18, -16)`; place cow at **opposite** corner, e.g. `Alignment.topLeft` with negative translate, or below the note).

---

## 8. Unified changelog / activity log in Settings (new)

**Goal:** One place under **Settings** for all user-visible “what happened” data, instead of fragmented per-paddock history only. Single list with **date**, **event type**, **paddock**, **summary**, plus **batch select** and **delete**.

**Scope (v1)**

- Merge **three** sources: **Measurement** (cover), **Grazing**, **NoteEntry** from [`Storage`](lib/storage.dart). Build a flat list of tagged items `{ kind, id, at, paddockId }`, sort by `at` descending, resolve paddock names from `loadPaddocks()`.

**Row fields**

- **Date/time** — from each entity’s `at`.
- **Type** — “Cover”, “Grazing”, “Note” (optional subtitle for scheduled grazing if `at` is in the future).
- **Paddock** — name from id.
- **Summary** — one line (cover value; grazing pre/post/harvest; note title).

**UI**

- New screen e.g. [`lib/screens/activity_log_screen.dart`](lib/screens/activity_log_screen.dart) (title: “Activity log”, “Farm log”, or “Changelog”).
- **Settings:** one list tile opening this screen (single entry point).
- **Multi-select:** checkboxes or selection mode; **Delete selected** with confirmation. Implement deletes via **`deleteMeasurementById` / `deleteGrazingById` / `deleteNoteById`** (§6). Optional **Select all** / filter by type in a later iteration.

**Out of scope (v1)**

- Backup/import/map/settings events (no persisted audit today). Editing from this screen is optional follow-up (edit stays in paddock history per §6).

**Dependency:** Prefer implementing after **delete-by-id** APIs (§6 / storage-crud todo) so the log can remove rows safely.

---

## Files likely touched

| Area | Files |
|------|--------|
| Storage | `lib/storage.dart`, optionally `lib/models.dart` |
| Home map + grazings + paddocks rows | `lib/screens/home_screen.dart` |
| Paddock history | `lib/screens/paddock_history_screen.dart` |
| Settings / Instructions | `lib/screens/settings_screen.dart`, `lib/screens/instructions_screen.dart` |
| New screens | `lib/screens/water_troughs_screen.dart`, `lib/screens/activity_log_screen.dart` (or chosen name) |

---

## Suggested implementation order

1. Storage primitives (delete/update by id; grazing bulk + update; water troughs + toggle).
2. **`_RowData.hasFutureGrazing` + Paddocks column icon + `_MapPoly` + map border + zoom-gated cow marker** (can ship with future-grazing UX early).
3. Paddock history edit/delete.
4. **Settings activity log** (merge lists + Settings entry + batch delete) — best after delete-by-id from step 1.
5. Home Grazings tab bulk/reschedule.
6. Map measure mode + label opacity tweak.
7. Water troughs screen + map.
8. Settings copy + instructions (include one line for the activity log).
