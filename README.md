# Wayfarer

A solo-women's travel assistant for iPhone. Enter a destination and dates, get a day-by-day itinerary on a map, customise it, and see calm, honest **safety guidance** for every stop.

> **MVP status:** itinerary and safety data are **mock** (clearly labelled in the UI). Every external dependency sits behind a protocol so real services can be swapped in without touching views or view models.

Swift 5 · SwiftUI · SwiftData · MapKit · iOS 17+ · no third-party dependencies · no API keys.

## Screenshots

| Trips | Itinerary | Safety detail |
| :---: | :---: | :---: |
| _placeholder_ | _placeholder_ | _placeholder_ |

## Run it

Requires Xcode 15+ (Xcode 16 recommended).

```bash
open Wayfarer.xcodeproj
```

Pick an iPhone simulator (e.g. iPhone 16) and press **⌘R**. Press **⌘U** to run unit tests.
Try "Lisbon", "Paris" or "Tokyo" for hand-written content. Any other city works too (placeholder stops around the city centre, found via MapKit).

The project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you add or move files: `brew install xcodegen && xcodegen generate`.

## Features

1. **Trip form** - destination + dates, validation, loading and error states.
2. **Itinerary** - a day picker, MapKit map (numbered markers tinted by safety band, route line), ordered stops with time slot, category, commute to next stop and safety badge.
3. **Customise** - add a place via MapKit local search, swipe to delete, Edit to drag-reorder. Changes persist in SwiftData and commute times are recalculated.
4. **Safety guidance** - band (Comfortable / Take care / Limited data), score, short reason, day-vs-night notes, confidence, sources, and an always-visible disclaimer.
5. **Offline** - trips are stored locally; saved itineraries open without a network, an offline banner explains what's unavailable, and commute estimates fall back to a local heuristic.

## Architecture

MVVM with protocol-based services and one composition root (`AppEnvironment`).

```
SwiftUI Views ───────────────► ViewModels (@Observable, @MainActor)
 TripListView                    TripFormViewModel
 TripFormView                    ItineraryViewModel
 ItineraryView / PlaceRow        PlaceSearchViewModel
 AddPlaceView / PlaceDetailView        │
        │                              ▼
        │                        TripPlanner  (turns service output into models)
        │                              │
        │            ┌─────────────────┼──────────────────┐
        │            ▼                 ▼                  ▼
        │   ItineraryService   SafetyScoringService   RoutingService     PlacesService
        │   └ MockItinerary…   └ MockSafetyScoring…   ├ MapKitRouting…   └ MapKitPlaces…
        │                                             └ HeuristicRouting… (offline fallback)
        ▼
 SwiftData models: Trip ─┬─< Day ─┬─< Place     (cascade delete; order via Place.order)
```

Design notes:

- **Services return plain `Sendable` values** (`DayProposal`, `SafetyAssessment`, `CommuteEstimate`, `PlaceSuggestion`), never SwiftData objects. A future LLM backend only has to return JSON that decodes to `DayProposal`.
- **`TripPlanner`** is the single place that composes itinerary + safety + routing into `Trip/Day/Place`, so view models stay small.
- **SwiftData relationships are unordered**, so `Place.order` is the source of truth and `Day.sortedPlaces` is the only way views read places.
- **Routing never throws**: MapKit ETA first, local heuristic on any failure, so editing works offline.
- **No UI in the model layer**: icons, colours and wording live in `Views/Components/Presentation.swift`.

```
Wayfarer/
  App/         WayfarerApp, AppEnvironment (composition root)
  Models/      Trip, Day, Place, enums, GeoPoint
  Services/    protocols, mock + MapKit implementations, TripPlanner
  ViewModels/  TripForm, Itinerary, PlaceSearch
  Views/       screens + Components/
  Support/     NetworkMonitor, PreviewData
WayfarerTests/ model, service and view-model tests
```

## Accessibility

VoiceOver: each stop is one element with a full spoken summary (stop number, category, safety band/score/confidence, reason, commute) and a hint. Safety is never colour-only: every band has an icon and text. Dynamic Type via system text styles, 44 pt minimum tap targets, light/dark via semantic colours and an accent colour with a dark variant.

## Tests

`WayfarerTests` covers the data model (ordering, cascade delete, band rules), mock itinerary/safety/routing services (determinism, validation, edge cases), `TripPlanner`, and the view models (add / delete / reorder with commute recalculation, form and search states) using an in-memory `ModelContainer`.

## Privacy and safety-score bias

- **Privacy:** trips live only on the device (SwiftData). The app has no accounts, analytics or API keys, and does not request your location. Destination and place searches go to Apple Maps (MapKit) only.
- **Safety scores are guidance, not guarantees.** The current numbers are category-based demo data, labelled as such.
- **Bias is a real risk** for any future real scoring: crime and incident data reflects reporting and policing patterns, can stigmatise neighbourhoods by income or ethnicity, and is thin outside well-mapped tourist areas. Mitigations designed in: gentle bands (we never say "unsafe"), an explicit **Limited data** band, a **confidence** level that hides the number when low, source citations, a day-vs-night split, and a persistent disclaimer. Real data should be reviewed for bias before launch, and users should be able to report wrong or unfair assessments.

## Limitations

- Itineraries and safety data are mock. Unknown destinations get generic placeholder stops.
- Max 14 days per trip. Time slots stay with a place when reordered.
- Map tiles and place search need a network; saved trips and their data do not.
- English only (strings aren't localised yet). iPhone, portrait only.
- Unit tests only; no UI tests yet.

## Roadmap (designed for, not built)

- **Real AI itinerary:** `ItineraryService` backed by a small backend calling an LLM that returns structured JSON; the app verifies every place via MapKit before saving.
- **Real safety score:** rule-based formula over structured signals (time of day, lighting/busy-ness from OpenStreetMap, government advisories, open crime data) with RAG-generated, cited explanations and a confidence value, precomputed and cached. Slots into `SafetyScoringService` / `SafetyAssessment` (`sources` and `confidence` already exist).
- **Apple Watch:** check-in timer, "I'm OK" / "I need help" with haptics.
- Live Activity, widget, App Intents / Siri, optional macOS companion.
