# Calorie Counter

A simple, privacy-friendly iOS calorie tracker built with **SwiftUI** and **SwiftData**. Log every meal, watch your daily progress fill a circular ring, and start fresh every morning.

<p align="center">
  <em>Made by <a href="https://zozimustechnologies.github.io/">Zozimus Technologies</a></em>
</p>

---

## Features

- 🔥 **Circular calorie ring** — at-a-glance progress vs. your daily goal. Color shifts from blue → orange → red as you approach and exceed the limit.
- 🍎 **One-tap food logging** — name + calories, that's it. Entries are timestamped automatically.
- 📋 **Today's logs** — every entry you've added today, with swipe-left → confirm to delete.
- 🎯 **Custom daily goal** — set anywhere from 100 to 20,000 kcal via a stepper or by typing a value directly.
- 🌅 **Auto reset at midnight** — the ring resets and yesterday's entries are purged from local storage automatically. Works whether the app is open at midnight or launched fresh the next day.
- 🧭 **Onboarding + guided tour** — a 5-page intro on first launch, followed by an optional 7-step interactive walkthrough that highlights every button on the main screen.
- 🎨 **Brand-themed UI** — rounded blue primary buttons, red donate button, custom app icon (light / dark / tinted variants), and a vector-drawn logo in the nav bar and onboarding.
- 🔒 **Local-only data** — everything is stored on-device with SwiftData. No accounts, no analytics, no network calls (other than the optional Donate / Contact links the user explicitly taps).

## Requirements

- **iOS 17.0+** (for SwiftData)
- **Xcode 15+**
- Swift 5.9+

## Getting started

```bash
git clone https://github.com/zozimustechnologies/caloriecounter.git
cd caloriecounter
open caloriecounter.xcodeproj
```

Then in Xcode select your target device or simulator and hit **⌘R**.

## Project structure

```
caloriecounter/
├── caloriecounter/
│   ├── caloriecounterApp.swift   # App entry + ModelContainer setup
│   ├── ContentView.swift         # Main UI: ring, logs, onboarding, tour, settings
│   ├── Item.swift                # FoodEntry SwiftData model
│   └── Assets.xcassets/          # AccentColor + AppIcon (light/dark/tinted)
├── caloriecounterTests/          # Unit tests
├── caloriecounterUITests/        # UI tests
├── generate_icons.swift          # Script to (re)generate app icon PNGs from SwiftUI
├── LICENSE                       # MIT
└── README.md
```

## Regenerating the app icon

The app icon is rendered from a SwiftUI view (gradient background + flame glyph + ring). To tweak the design, edit `generate_icons.swift` and run:

```bash
swift generate_icons.swift
```

This writes three new 1024×1024 PNGs into `caloriecounter/Assets.xcassets/AppIcon.appiconset/` (light, dark, tinted). Rebuild the app and — if running on a device or simulator — delete the old install first so iOS picks up the new icon.

## Privacy

Calorie Counter stores your food log **only on your device** using Apple's SwiftData framework. Nothing is uploaded, synced, or shared. The Donate and Contact links in Settings open external URLs (Wise / Mail) only when you tap them.

## Contact & support

- 📧 **Email:** [zozimustechnologies@outlook.com](mailto:zozimustechnologies@outlook.com)
- 💚 **Donate:** [Wise — Sandeep Chadda](https://wise.com/pay/business/sandeepchadda?utm_source=open_link)
- 🌐 **Website:** [zozimustechnologies.github.io](https://zozimustechnologies.github.io/)

## License

Released under the [MIT License](LICENSE). © 2026 Zozimus Technologies. All rights reserved.
