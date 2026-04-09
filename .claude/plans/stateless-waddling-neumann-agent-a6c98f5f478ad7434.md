# Automatic Hourly Phrase Refresh — Implementation Plan

## Design Decisions

### Q1: Dedicated hourly timer vs. piggyback on the 60-sec timer?
**Answer: Piggyback on the existing 60-second timer.**

The `startTimeUpdates()` timer already fires every 60 seconds to update the clock display. Adding a simple hour-boundary check inside that callback is the lowest-complexity path. We avoid a second `Timer` and its lifecycle management. The check is just a Date comparison — negligible cost.

### Q2: Widget phrase strategy — always fresh, or only when stale?
**Answer: Always generate a fresh phrase on every timeline refresh.**

The widget already has weather data (condition, temp, isDay) available inside `fetchWeatherEntry()`. Generating a fresh phrase every 15 minutes costs nothing (PhraseEngine is local, no network). This makes the widget fully self-sufficient — it never depends on the app being alive. The shared UserDefaults phrase becomes a "hint" rather than a requirement.

### Q3: Store a `phraseTimestamp` in shared UserDefaults?
**Answer: No — not needed.**

Since the widget will always generate its own phrase (Decision Q2), it does not need to check staleness. The app writes `currentPhrase` to shared defaults as it does today, but the widget no longer reads it. This simplifies the system: remove a data dependency rather than add one. The `currentPhrase` key can be kept for backward compatibility but is effectively unused by the widget.

### Q4: Background behavior?
**Answer: Accept that the timer pauses when backgrounded.** The user is not looking at the app. On foreground return, `refreshOnForeground()` already fetches fresh weather AND calls `refreshPhrase()`, so the phrase will update immediately. No BGTaskScheduler needed.

---

## Implementation Plan

### Step 1: Add hourly phrase rotation to WeatherViewModel.swift

**File:** `/Users/matthewcosensci/Documents/dev/The Damn Weather/The Damn Weather/ViewModels/WeatherViewModel.swift`

**Changes:**

1. Add a private property to track the hour of the last phrase refresh:

```swift
private var lastPhraseHour: Int = -1
```

2. Modify `startTimeUpdates(timezone:)` to check for hour changes on each tick:

```swift
private func startTimeUpdates(timezone: TimeZone) {
    timeTimer?.invalidate()
    currentTime = Date.currentTimeString(timezone: timezone)
    // Seed the last phrase hour so we don't immediately re-phrase on timer start
    lastPhraseHour = Calendar.current.component(.hour, from: Date())
    
    timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        guard let self else { return }
        self.currentTime = Date.currentTimeString(timezone: timezone)
        
        let currentHour = Calendar.current.component(.hour, from: Date())
        if currentHour != self.lastPhraseHour {
            self.lastPhraseHour = currentHour
            Task { @MainActor in
                await self.refreshPhrase()
            }
        }
    }
}
```

That is the entire app-side change. Every 60 seconds the timer fires, checks if the hour rolled over, and if so calls the existing `refreshPhrase()` which already:
- Generates a new phrase via PhraseEngine
- Updates `currentPhrase` (the published property that drives the UI)
- Writes to shared UserDefaults
- Calls `WidgetCenter.shared.reloadAllTimelines()`

No new methods, no new timers, no new dependencies.

### Step 2: Make the widget always generate a fresh phrase

**File:** `/Users/matthewcosensci/Documents/dev/The Damn Weather/WeatherWidgetExtension/WeatherWidgetProvider.swift`

**Changes to `fetchWeatherEntry()`:**

Replace the current phrase-selection block (lines 189-201) which prefers the shared UserDefaults phrase:

```swift
// CURRENT CODE (remove):
let phrase: String
if let sharedPhrase = defaults.string(forKey: "currentPhrase"), !sharedPhrase.isEmpty {
    phrase = sharedPhrase
} else {
    let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
    let mode = PhraseMode(rawValue: modeStr) ?? .clean
    phrase = await phraseEngine.selectPhrase(...)
}
```

With code that always generates a fresh phrase:

```swift
// NEW CODE:
let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
let mode = PhraseMode(rawValue: modeStr) ?? .clean
let phrase = await phraseEngine.selectPhrase(
    conditionTag: conditionTag,
    tempF: tempF,
    mode: mode,
    isDay: current.isDaylight
)
```

**Also update the error/fallback block in `getTimeline()` (lines 124-135)** to generate a fresh phrase instead of reading stale shared state. Replace:

```swift
// CURRENT fallback phrase logic (remove):
let phrase: String
if let sharedPhrase = defaults.string(forKey: "currentPhrase"), !sharedPhrase.isEmpty {
    phrase = sharedPhrase
} else {
    phrase = await phraseEngine.selectPhrase(...)
}
```

With:

```swift
// NEW fallback:
let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
let mode = PhraseMode(rawValue: modeStr) ?? .clean
let phrase = await phraseEngine.selectPhrase(
    conditionTag: .partlyCloudy,
    tempF: 72,
    mode: mode,
    isDay: true
)
```

This ensures the widget always shows a fresh phrase on every 15-minute timeline refresh, regardless of whether the app is running.

### Step 3: (No changes needed to these files)

- **PhraseEngine.swift** — No changes. It already handles deduplication via seen-phrases tracking.
- **AppConstants.swift** — No new UserDefaults keys needed.
- **MainView.swift** — No changes. The `.onChange(of: scenePhase)` handler already calls `refreshOnForeground()` which calls `refreshPhrase()`.
- **PhraseText.swift** — No changes. It reacts to `currentPhrase` binding changes automatically.

---

## Summary of All Changes

| File | Change | Lines affected |
|------|--------|---------------|
| `WeatherViewModel.swift` | Add `lastPhraseHour` property | +1 line, new property |
| `WeatherViewModel.swift` | Modify `startTimeUpdates()` to check hour boundary | ~8 lines modified in existing method |
| `WeatherWidgetProvider.swift` | `fetchWeatherEntry()`: always generate fresh phrase | ~6 lines replaced |
| `WeatherWidgetProvider.swift` | `getTimeline()` fallback: always generate fresh phrase | ~6 lines replaced |

**Total: ~2 files changed, ~20 lines of code modified.**

---

## Behavior After Implementation

| Scenario | Phrase behavior |
|----------|----------------|
| App open, left idle | Phrase rotates every hour (on the hour boundary) |
| App backgrounded | Timer suspended; phrase refreshes immediately on foreground return via existing `refreshOnForeground()` |
| App killed | No app-side refresh; widget handles itself |
| Widget timeline refresh (every ~15 min) | Widget generates a fresh phrase from PhraseEngine every time |
| User taps phrase | Immediate refresh (unchanged from current behavior) |
| App launch / pull-to-refresh | Immediate refresh (unchanged from current behavior) |

---

## Risks and Mitigations

1. **Timer callback threading**: The 60-second Timer fires on the main run loop. The `refreshPhrase()` call is `async` and accesses the `PhraseEngine` actor. Wrapping in `Task { @MainActor in ... }` ensures `currentPhrase` (an `@Observable` property) is set on the main actor. The PhraseEngine is an actor so its internals are safe.

2. **Widget PhraseEngine seen-phrases divergence**: The app and widget each have their own PhraseEngine instance, but they share the same UserDefaults (app group) for seen-phrases tracking. This is the existing behavior and works correctly — both write to the same `seenPhrases_clean`/`seenPhrases_explicit` keys.

3. **Phrase animation on hourly change**: The `currentPhrase` property update will cause SwiftUI to re-render `PhraseText`. Since `PhraseText` uses `.contentTransition(.opacity)`, the text will smoothly transition. However, unlike the tap-triggered refresh, there is no fade-out-then-fade-in sequence. If a smoother animation is desired for automatic refreshes, that would be a separate UI enhancement — not part of this plan's scope.
