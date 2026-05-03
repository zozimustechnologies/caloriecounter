//
//  ContentView.swift
//  caloriecounter
//
//  Created by DJAviCC on 02/05/26
//
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]

    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var showingDeleteConfirm = false
    @State private var entryPendingDeletion: FoodEntry?
    @State private var pendingDeleteName: String = ""
    @State private var pendingDeleteCalories: Int = 0
    @State private var tourStepIndex: Int = 0
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @AppStorage("dailyGoal") private var dailyGoal: Int = 2000
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedTour") private var hasCompletedTour: Bool = false

    private var tourActive: Bool { hasCompletedOnboarding && !hasCompletedTour }

    private var today: Date { currentDay }

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: today) }
    }

    private var todayTotal: Int {
        todayEntries.reduce(0) { $0 + $1.calories }
    }

    private var groupedByDay: [(date: Date, items: [FoodEntry])] {
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.timestamp) }
        return groups.map { (date: $0.key, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Ring
                CalorieRing(consumed: todayTotal, goal: dailyGoal)
                    .frame(width: 220, height: 220)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .tourTarget(.ring)

                // Thin separator between ring and logs
                Divider()
                    .padding(.horizontal)

                // Logs header
                HStack {
                    Text("Logs")
                        .font(.headline)
                    Spacer()
                    Text("\(todayEntries.count) today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)

                // Logs list
                Group {
                    if entries.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("No food logged yet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(groupedByDay, id: \.date) { group in
                                Section(header: Text(sectionTitle(for: group.date))) {
                                    ForEach(group.items) { entry in
                                        EntryRow(entry: entry)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    entryPendingDeletion = entry
                                                    pendingDeleteName = entry.name
                                                    pendingDeleteCalories = entry.calories
                                                    showingDeleteConfirm = true
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
                .tourTarget(.logs)
            }
            .navigationTitle("Calorie Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        CalorieCounterLogo(size: 26)
                        Text("Calorie Counter")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tourTarget(.settings)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                    .tourTarget(.add)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFoodView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView { startTour in
                    hasCompletedOnboarding = true
                    if startTour {
                        // User wants the tour – make sure it's not marked done.
                        hasCompletedTour = false
                        tourStepIndex = 0
                    } else {
                        // User skipped the tour – mark it done so it doesn't appear.
                        hasCompletedTour = true
                    }
                    showingOnboarding = false
                }
            }
            .onAppear {
                refreshDayIfNeeded()
                if !hasCompletedOnboarding { showingOnboarding = true }
                syncTourSheets()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refreshDayIfNeeded() }
            }
            .onChange(of: hasCompletedOnboarding) { _, newValue in
                if !newValue { showingOnboarding = true }
            }
            .onChange(of: tourStepIndex) { _, _ in syncTourSheets() }
            .onChange(of: tourActive) { _, isActive in
                if isActive {
                    syncTourSheets()
                } else {
                    // Tour ended — close any sheets the tour opened.
                    showingAdd = false
                    showingSettings = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshDayIfNeeded()
            }
            .alert(
                "Delete entry?",
                isPresented: $showingDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryPendingDeletion {
                        delete(entry)
                    }
                }
                Button("Cancel", role: .cancel) {
                    entryPendingDeletion = nil
                }
            } message: {
                Text("Remove \"\(pendingDeleteName)\" (\(pendingDeleteCalories) kcal) from your log? This can't be undone.")
            }
        }
        // Overlay is attached OUTSIDE NavigationStack so it draws on top
        // of the navigation bar / toolbar items (front-most layer).
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if tourActive {
                    TourOverlay(
                        stepIndex: $tourStepIndex,
                        anchors: anchors,
                        proxy: proxy,
                        onFinish: {
                            withAnimation { hasCompletedTour = true }
                            tourStepIndex = 0
                        }
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: tourActive)
            .animation(.easeInOut(duration: 0.25), value: tourStepIndex)
        }
    }

    private func sectionTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func delete(_ entry: FoodEntry) {
        withAnimation {
            modelContext.delete(entry)
            entryPendingDeletion = nil
        }
    }

    private func refreshDayIfNeeded() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let dayChanged = startOfToday != currentDay
        // Always purge any stale (pre-today) entries — handles both the
        // midnight rollover while the app is open AND the case where the
        // app is launched fresh on a new day with leftover logs from before.
        purgeOldEntries(before: startOfToday)
        if dayChanged {
            withAnimation(.easeInOut(duration: 0.4)) {
                currentDay = startOfToday
            }
        }
    }

    /// Deletes every `FoodEntry` whose timestamp is strictly before
    /// `startOfToday`, clearing the log cache so only today's entries remain.
    private func purgeOldEntries(before startOfToday: Date) {
        let stale = entries.filter { $0.timestamp < startOfToday }
        guard !stale.isEmpty else { return }
        withAnimation {
            for entry in stale {
                modelContext.delete(entry)
            }
        }
    }

    /// Open or close the Add / Settings sheets so they match the current
    /// guided-tour step. Demo steps:
    ///   • .add        → present Add Food sheet
    ///   • .changeLimit, .support → present Settings sheet
    /// All other steps close both sheets.
    private func syncTourSheets() {
        guard tourActive,
              tourStepIndex >= 0,
              tourStepIndex < TourStep.allCases.count
        else { return }
        let step = TourStep.allCases[tourStepIndex]
        switch step {
        case .add:
            if showingSettings { showingSettings = false }
            if !showingAdd { showingAdd = true }
        case .changeLimit, .support:
            if showingAdd { showingAdd = false }
            if !showingSettings { showingSettings = true }
        case .settings, .ring, .logs, .deleteLog:
            if showingAdd { showingAdd = false }
            if showingSettings { showingSettings = false }
        }
    }
}

// MARK: - Circular progress ring

private struct CalorieRing: View {
    let consumed: Int
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1.0)
    }

    private var overGoal: Bool { consumed > goal }

    private var ringColor: Color {
        if overGoal { return .red }
        if progress >= 0.85 { return .orange }
        return .accentColor
    }

    private var remaining: Int { max(goal - consumed, 0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 18)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)

            VStack(spacing: 4) {
                Text("\(consumed)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(goal) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(overGoal ? "+\(consumed - goal) over" : "\(remaining) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(overGoal ? .red : .secondary)
            }
        }
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.name)
                    .font(.body)
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.calories) kcal")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Add food sheet

struct AddFoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var calories: String = ""
    @State private var query: String = ""

    /// Foods from the bundled catalog whose name matches the query
    /// (or a curated set of starter suggestions when the query is empty).
    private var suggestions: [CatalogFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return FoodCatalog.popular }
        let lower = trimmed.lowercased()
        let all = FoodCatalog.all
        // Prefix matches first, then substring matches — more useful order.
        let prefix = all.filter { $0.name.lowercased().hasPrefix(lower) }
        let contains = all.filter {
            !$0.name.lowercased().hasPrefix(lower) &&
            $0.name.lowercased().contains(lower)
        }
        return Array((prefix + contains).prefix(40))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g. Apple)", text: $name)
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                }

                Section {
                    ForEach(suggestions) { food in
                        Button {
                            name = food.name
                            calories = String(food.calories)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).foregroundStyle(.primary)
                                    Text(food.serving)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(food.calories) kcal")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if suggestions.isEmpty {
                        Text("No matches. Type a name and calories above to log it manually.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(query.isEmpty ? "Popular foods" : "Matches")
                } footer: {
                    Text("Calorie values are approximate, per the listed serving.")
                        .font(.caption2)
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search foods")
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(calories) ?? 0) > 0
    }

    private func save() {
        guard let cals = Int(calories) else { return }
        let entry = FoodEntry(name: name.trimmingCharacters(in: .whitespaces),
                              calories: cals)
        modelContext.insert(entry)
        dismiss()
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyGoal") private var dailyGoal: Int = 2000
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedTour") private var hasCompletedTour: Bool = false
    @State private var goalText: String = ""

    private let donateURL = URL(string: "https://wise.com/pay/business/sandeepchadda?utm_source=open_link")!
    private let companyURL = URL(string: "https://zozimustechnologies.github.io/")!
    private let contactURL = URL(string: "mailto:zozimustechnologies@outlook.com")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Stepper(value: $dailyGoal, in: 500...10000, step: 100) {
                            HStack {
                                Text("Daily goal")
                                Spacer()
                                Text("\(dailyGoal) kcal")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        HStack {
                            Text("Custom")
                            Spacer()
                            TextField("kcal", text: $goalText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                                .onSubmit(applyCustom)
                        }
                    } header: {
                        Text("Calorie limit")
                    } footer: {
                        Text("Use the stepper for quick changes or type a custom value and press return.")
                    }

                    Section {
                        Button {
                            hasCompletedOnboarding = false
                            hasCompletedTour = false
                            dismiss()
                        } label: {
                            Label("Show onboarding again", systemImage: "sparkles")
                        }

                        Button {
                            hasCompletedTour = false
                            dismiss()
                        } label: {
                            Label("Show guided tour", systemImage: "hand.point.up.left.fill")
                        }
                    }
                }

                // Pinned bottom area – separator, buttons, copyright
                VStack(spacing: 14) {
                    // Rounded separator line – longer than the buttons,
                    // with a small inset so it doesn't touch the edges.
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(height: 3)
                        .padding(.horizontal, 8)

                    Link(destination: contactURL) {
                        Label("Contact us", systemImage: "envelope.fill")
                    }
                    .buttonStyle(BrandButtonStyle(color: .blue))
                    .padding(.horizontal, 32)

                    Link(destination: donateURL) {
                        Label("Donate", systemImage: "heart.fill")
                    }
                    .buttonStyle(BrandButtonStyle(color: .red))
                    .padding(.horizontal, 32)

                    Link(destination: companyURL) {
                        Text("© Zozimus Technologies. All rights reserved.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyCustom()
                        dismiss()
                    }
                }
            }
            .onAppear { goalText = "\(dailyGoal)" }
        }
    }

    private func applyCustom() {
        if let value = Int(goalText), (100...20000).contains(value) {
            dailyGoal = value
        } else {
            goalText = "\(dailyGoal)"
        }
    }
}

// MARK: - Brand button style

private struct BrandButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}

// MARK: - Onboarding

struct OnboardingView: View {
    /// `startTour == true` → user wants the guided tour after onboarding.
    /// `startTour == false` → user wants to go straight to the app.
    var onFinish: (_ startTour: Bool) -> Void

    @State private var page: Int = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "flame.fill",
            tint: .blue,
            title: "Welcome to Calorie Counter",
            message: "A simple way to keep track of what you eat and stay on top of your daily goal.",
            useLogo: true
        ),
        OnboardingPage(
            symbol: "circle.dashed",
            tint: .blue,
            title: "Watch your ring fill",
            message: "The circular progress ring shows how many calories you've had today versus your daily goal."
        ),
        OnboardingPage(
            symbol: "list.bullet.rectangle.fill",
            tint: .green,
            title: "Log every meal",
            message: "Tap + to add food. Swipe a log left to delete it — we'll ask before removing anything."
        ),
        OnboardingPage(
            symbol: "gearshape.fill",
            tint: .purple,
            title: "Make it yours",
            message: "Open Settings to set your daily calorie limit and find ways to support the app."
        ),
        OnboardingPage(
            symbol: "hand.point.up.left.fill",
            tint: .orange,
            title: "Want a quick tour?",
            message: "We can briefly highlight each button on the main screen so you know what does what. Takes just a few seconds."
        )
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingPageView(page: item)
                        .tag(index)
                        .padding(.horizontal, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 0) {
                ZStack {
                    // Pages 1–4: Next + small Skip link.
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { page += 1 }
                        } label: {
                            Text("Next")
                        }
                        .buttonStyle(BrandButtonStyle(color: .blue))
                        .padding(.horizontal, 32)

                        Button("Skip") {
                            // Skipping onboarding entirely also skips the tour.
                            onFinish(false)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                    }
                    .opacity(isLastPage ? 0 : 1)
                    .allowsHitTesting(!isLastPage)

                    // Page 5: Yes / Skip choice for the guided tour.
                    VStack(spacing: 0) {
                        Button {
                            onFinish(true)
                        } label: {
                            Label("Yes, show me around", systemImage: "sparkles")
                        }
                        .buttonStyle(BrandButtonStyle(color: .blue))
                        .padding(.horizontal, 32)

                        Button("Skip") {
                            onFinish(false)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                    }
                    .opacity(isLastPage ? 1 : 0)
                    .allowsHitTesting(isLastPage)
                }
                .animation(.easeInOut(duration: 0.25), value: isLastPage)
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

private struct OnboardingPage {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var useLogo: Bool = false
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.15))
                    .frame(width: 160, height: 160)
                if page.useLogo {
                    CalorieCounterLogo(size: 120)
                } else {
                    Image(systemName: page.symbol)
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(page.tint)
                }
            }
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - App logo (SwiftUI-drawn)

struct CalorieCounterLogo: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            // Outer "calorie ring" — partial trim like a progress arc
            Circle()
                .trim(from: 0.0, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            // Inner flame
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Calorie Counter logo")
    }
}

// MARK: - Guided tour (coach marks)

enum TourStep: Int, CaseIterable, Hashable {
    case settings        // Spotlights the gear button (overview)
    case ring            // Spotlights the calorie ring
    case add             // Spotlights the + button
    case logs            // Spotlights the logs panel (where entries appear)
    case deleteLog       // Re-spotlights logs — explains swipe-to-delete
    case changeLimit     // Re-spotlights settings — explains daily-limit control
    case support         // Re-spotlights settings — explains Donate / Contact

    /// The visual anchor this step uses. Several "how-to" steps re-use an
    /// existing anchor with a different explanatory message.
    var anchorStep: TourStep {
        switch self {
        case .deleteLog:               return .logs
        case .changeLimit, .support:   return .settings
        default:                       return self
        }
    }

    var title: String {
        switch self {
        case .settings:    return "Settings"
        case .ring:        return "Your daily progress"
        case .add:         return "Add food"
        case .logs:        return "Your meal logs"
        case .deleteLog:   return "Deleting a log"
        case .changeLimit: return "Change your calorie limit"
        case .support:     return "Support the app"
        }
    }

    var message: String {
        switch self {
        case .settings:
            return "Tap the gear to open Settings — change your daily calorie limit, contact us, or support the app."
        case .ring:
            return "This ring fills up as you log food and turns red if you go over your goal. It resets to 0 at midnight every day."
        case .add:
            return "Tap + to log a new meal. A sheet will ask for the food's name and how many calories it has — then Save adds it to today's total."
        case .logs:
            return "Everything you've eaten today (and earlier days) shows up here, grouped by day with the time and calorie count."
        case .deleteLog:
            return "Made a mistake? Swipe any log row to the left to reveal a red Delete button. A confirmation alert will appear so you don't delete the wrong entry by accident."
        case .changeLimit:
            return "Open Settings (gear icon). Use the stepper to bump your daily limit by 100 kcal, or type any value between 100 and 20,000 in the text field. Your ring updates instantly."
        case .support:
            return "Inside Settings, scroll to the footer for Contact us (email) and Donate (Wise) — both help keep the app going. Thank you!"
        }
    }
}

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourStep: Anchor<CGRect>],
                       nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func tourTarget(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: $0] }
    }
}

struct TourOverlay: View {
    @Binding var stepIndex: Int
    let anchors: [TourStep: Anchor<CGRect>]
    let proxy: GeometryProxy
    let onFinish: () -> Void

    @State private var measuredCardHeight: CGFloat = 220
    @State private var showingSkipAlert: Bool = false

    private var step: TourStep { TourStep.allCases[stepIndex] }
    private var isLast: Bool { stepIndex >= TourStep.allCases.count - 1 }
    private var isFirst: Bool { stepIndex == 0 }

    // Approximate height of the inline navigation bar (toolbar) on iOS.
    private let navBarHeight: CGFloat = 44

    /// True top safe-area inset. The GeometryReader hosting this overlay has
    /// `.ignoresSafeArea()` applied, which makes `proxy.safeAreaInsets.top`
    /// report 0 on some iOS versions. Fall back to the key window's actual
    /// safe-area inset so toolbar coordinates still land in the right place.
    private var topSafeArea: CGFloat {
        if proxy.safeAreaInsets.top > 0 { return proxy.safeAreaInsets.top }
        let windowInset = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets
            .top ?? 0
        // Sensible default for modern iPhones with a dynamic island / notch.
        return windowInset > 0 ? windowInset : 59
    }

    private var bottomSafeArea: CGFloat {
        if proxy.safeAreaInsets.bottom > 0 { return proxy.safeAreaInsets.bottom }
        return UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets
            .bottom ?? 34
    }

    /// y-coordinate of the bottom of the navigation toolbar, used both as a
    /// fallback for toolbar-item anchors (which don't propagate out of the
    /// UIKit-backed nav bar) and as a top boundary for the card placement.
    private var toolbarBottomY: CGFloat {
        topSafeArea + navBarHeight
    }

    private var targetRect: CGRect? {
        // Toolbar items live inside a UIKit UINavigationBar; their anchor
        // preferences don't reach this overlay. Synthesize a rect that
        // matches the visible glyph (~26pt for SF Symbol toolbar icons),
        // centered horizontally inside the standard 44pt tap target.
        switch step.anchorStep {
        case .settings:
            let glyph: CGFloat = 26
            let tap: CGFloat = 44   // standard toolbar tap target
            let inset: CGFloat = 8  // distance from screen edge to tap target
            return CGRect(
                x: inset + (tap - glyph) / 2,
                y: topSafeArea + (navBarHeight - glyph) / 2,
                width: glyph,
                height: glyph
            )
        case .add:
            let glyph: CGFloat = 26
            let tap: CGFloat = 44
            let inset: CGFloat = 8
            return CGRect(
                x: proxy.size.width - inset - tap + (tap - glyph) / 2,
                y: topSafeArea + (navBarHeight - glyph) / 2,
                width: glyph,
                height: glyph
            )
        case .ring, .logs:
            guard let anchor = anchors[step.anchorStep] else { return nil }
            return proxy[anchor]
        case .deleteLog, .changeLimit, .support:
            // Should never hit this — anchorStep maps these to one of above.
            return nil
        }
    }

    private var highlight: CGRect {
        guard let r = targetRect else { return .zero }
        // For circular spotlights, square up the rect around the target's
        // center so the circle outlines the button exactly — same diameter
        // as the visible icon.
        if isCircleStep {
            let side = max(r.width, r.height)
            return CGRect(
                x: r.midX - side / 2,
                y: r.midY - side / 2,
                width: side,
                height: side
            )
        }
        return r.insetBy(dx: -10, dy: -10)
    }

    /// Icon-shaped targets get a circular spotlight; the rectangular Logs
    /// section gets a rounded rectangle.
    private var isCircleStep: Bool {
        switch step.anchorStep {
        case .settings, .add, .ring: return true
        case .logs:                  return false
        case .deleteLog, .changeLimit, .support: return true // unreachable
        }
    }

    var body: some View {
        ZStack {
            // 1. Full-screen tap catcher: any tap outside the card prompts skip.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showingSkipAlert = true }
                .ignoresSafeArea()

            // 2. Visual dim with cutout (no hit-testing — purely cosmetic).
            backdrop
                .allowsHitTesting(false)

            // 3. Glowing outline around the highlighted target — circle for
            // icon buttons / the calorie ring, rounded rect for the logs panel.
            if highlight != .zero {
                Group {
                    if isCircleStep {
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    }
                }
                .frame(width: highlight.width, height: highlight.height)
                .position(x: highlight.midX, y: highlight.midY)
                .shadow(color: .white.opacity(0.6), radius: 10)
                .shadow(color: .blue.opacity(0.45), radius: 18)
                .allowsHitTesting(false)
            }

            // 3b. Demo content for steps that need a live mock (e.g. the
            // fake "Banana 121 kcal" swiped row for the delete-log step).
            demoContent

            // 4. Callout card – swallows taps so tapping it doesn't trigger skip.
            callout
        }
        .animation(.easeInOut(duration: 0.25), value: highlight)
        .animation(.easeInOut(duration: 0.25), value: stepIndex)
        .alert("Skip guided tour?", isPresented: $showingSkipAlert) {
            Button("Skip", role: .destructive) { onFinish() }
            Button("Continue", role: .cancel) { }
        } message: {
            Text("You can replay the tour any time from Settings.")
        }
    }

    // Dimmed background with a cutout (circle or rounded rect) around the
    // target, built from a single Path using even-odd fill.
    private var backdrop: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: proxy.size))
            if highlight != .zero {
                if isCircleStep {
                    path.addEllipse(in: highlight)
                } else {
                    path.addRoundedRect(
                        in: highlight,
                        cornerSize: CGSize(width: 14, height: 14)
                    )
                }
            }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .ignoresSafeArea()
    }

    /// Step-specific live mock content. Currently used by `.deleteLog` to
    /// show a fake "Banana 121 kcal" log row that's been swiped left to
    /// reveal the red Delete button — so the user can SEE the gesture's
    /// result without having to perform it (or even have any real entries).
    @ViewBuilder
    private var demoContent: some View {
        if step == .deleteLog {
            let logsRect = anchors[.logs].map { proxy[$0] }
            // Anchor the demo row near the top of the logs section if we
            // have its rect; otherwise fall back to roughly mid-screen.
            let yPos: CGFloat = {
                if let r = logsRect {
                    return r.minY + 60
                }
                return proxy.size.height * 0.55
            }()
            FakeSwipedLogRow()
                .frame(width: min(proxy.size.width - 32, 360))
                .position(x: proxy.size.width / 2, y: yPos)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var callout: some View {
        let rect = targetRect ?? CGRect(
            x: proxy.size.width / 2,
            y: proxy.size.height / 2,
            width: 0, height: 0
        )
        let cardWidth = min(proxy.size.width - 32, 360)
        let cardHeight = max(measuredCardHeight, 180)

        // The card lives outside the NavigationStack, so safeAreaInsets only
        // reports the dynamic-island/status-bar inset. We always keep the card
        // at least `toolbarBottomY` (status bar + nav bar height) so it can
        // never sit under the dynamic island, app title/logo, or toolbar
        // buttons — regardless of whether toolbar anchors propagated.
        let topBoundary = toolbarBottomY + 16
        let bottomBoundary = proxy.size.height - bottomSafeArea - 12

        // Choose whichever side has more clear room and place the card there.
        let edgePadding: CGFloat = 20
        let roomAbove = (rect.minY - edgePadding) - topBoundary
        let roomBelow = bottomBoundary - (rect.maxY + edgePadding)
        let placeBelow = roomBelow >= roomAbove

        // Position the card so its inner edge sits exactly `edgePadding` away
        // from the highlight, then clamp the *outer* edge to the boundary so
        // the card never crosses into the toolbar / home indicator areas.
        let centerY: CGFloat = {
            if placeBelow {
                let preferred = rect.maxY + edgePadding + cardHeight / 2
                let maxCenter = bottomBoundary - cardHeight / 2
                return min(preferred, maxCenter)
            } else {
                let preferred = rect.minY - edgePadding - cardHeight / 2
                let minCenter = topBoundary + cardHeight / 2
                return max(preferred, minCenter)
            }
        }()

        calloutCard
            .frame(width: cardWidth)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { measuredCardHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, new in
                            measuredCardHeight = new
                        }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture { /* swallow taps so backdrop's skip alert isn't triggered */ }
            .position(
                x: proxy.size.width / 2,
                y: centerY
            )
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step \(stepIndex + 1) of \(TourStep.allCases.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(step.title)
                .font(.title3.bold())
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    if !isFirst { stepIndex -= 1 }
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryRoundedButtonStyle())
                .disabled(isFirst)
                .opacity(isFirst ? 0.4 : 1.0)

                Button {
                    if isLast {
                        onFinish()
                    } else {
                        stepIndex += 1
                    }
                } label: {
                    HStack {
                        Text(isLast ? "Done" : "Next")
                        if !isLast { Image(systemName: "chevron.right") }
                    }
                }
                .buttonStyle(BrandButtonStyle(color: .blue))
            }
            .padding(.top, 4)

            // Centered, small Skip button below the action buttons.
            HStack {
                Spacer()
                Button {
                    showingSkipAlert = true
                } label: {
                    Text("Skip tour")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }
}

private struct SecondaryRoundedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Fake row used inside the guided tour to demonstrate swipe-to-delete

/// Static visual mock of a log entry that's been swiped left, revealing the
/// red Delete button on the trailing edge. Purely cosmetic — no taps, no data.
private struct FakeSwipedLogRow: View {
    private let revealWidth: CGFloat = 88
    @State private var animateReveal: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // The red "Delete" action sitting under the swiped row.
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Delete")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth, height: 64)
                .background(Color.red)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // The fake log row, shifted left to reveal the Delete action.
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.25))
                    Text("🍌")
                        .font(.title3)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Banana")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Just now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("121 kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .offset(x: animateReveal ? -revealWidth : 0)
        }
        .onAppear {
            // Animate the reveal so the user clearly sees the swipe action.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15)) {
                animateReveal = true
            }
        }
    }
}

// MARK: - Bundled food catalog
//
// Curated list of common foods with approximate calories per typical
// serving. Sources: USDA FoodData Central + standard nutrition labels,
// rounded to the nearest 5 kcal. Stored inline (no JSON resource needed)
// so it works fully offline with no API key or network access.

struct CatalogFood: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let calories: Int
    let serving: String
}

enum FoodCatalog {
    /// Shown when the search field in Add Food is empty.
    static let popular: [CatalogFood] = [
        CatalogFood(name: "Apple",            calories: 95,  serving: "1 medium (182 g)"),
        CatalogFood(name: "Banana",           calories: 105, serving: "1 medium (118 g)"),
        CatalogFood(name: "Egg, boiled",      calories: 78,  serving: "1 large"),
        CatalogFood(name: "Chicken breast",   calories: 165, serving: "100 g, cooked"),
        CatalogFood(name: "White rice",       calories: 205, serving: "1 cup, cooked"),
        CatalogFood(name: "Roti / Chapati",   calories: 120, serving: "1 medium (40 g)"),
        CatalogFood(name: "Milk, whole",      calories: 150, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Coffee, black",    calories: 2,   serving: "1 cup (240 ml)")
    ]

    /// Full catalog used for search inside Add Food.
    static let all: [CatalogFood] = [
        // — Fruits —
        CatalogFood(name: "Apple",            calories: 95,  serving: "1 medium (182 g)"),
        CatalogFood(name: "Banana",           calories: 105, serving: "1 medium (118 g)"),
        CatalogFood(name: "Orange",           calories: 62,  serving: "1 medium (131 g)"),
        CatalogFood(name: "Grapes",           calories: 104, serving: "1 cup (151 g)"),
        CatalogFood(name: "Strawberries",     calories: 49,  serving: "1 cup (152 g)"),
        CatalogFood(name: "Blueberries",      calories: 84,  serving: "1 cup (148 g)"),
        CatalogFood(name: "Mango",            calories: 200, serving: "1 whole (200 g)"),
        CatalogFood(name: "Pineapple",        calories: 82,  serving: "1 cup chunks (165 g)"),
        CatalogFood(name: "Watermelon",       calories: 46,  serving: "1 cup diced (152 g)"),
        CatalogFood(name: "Pear",             calories: 101, serving: "1 medium (178 g)"),
        CatalogFood(name: "Peach",            calories: 59,  serving: "1 medium (150 g)"),
        CatalogFood(name: "Avocado",          calories: 240, serving: "1 medium (150 g)"),
        CatalogFood(name: "Kiwi",             calories: 42,  serving: "1 medium (69 g)"),
        CatalogFood(name: "Pomegranate",      calories: 234, serving: "1 whole (282 g)"),
        CatalogFood(name: "Papaya",           calories: 119, serving: "1 small (157 g)"),
        CatalogFood(name: "Cherries",         calories: 87,  serving: "1 cup (138 g)"),
        CatalogFood(name: "Lemon",            calories: 17,  serving: "1 medium (58 g)"),
        CatalogFood(name: "Raisins",          calories: 130, serving: "1/4 cup (40 g)"),
        CatalogFood(name: "Dates",            calories: 66,  serving: "1 medjool date"),

        // — Vegetables —
        CatalogFood(name: "Broccoli",         calories: 55,  serving: "1 cup chopped, cooked"),
        CatalogFood(name: "Carrot",           calories: 25,  serving: "1 medium (61 g)"),
        CatalogFood(name: "Spinach",          calories: 7,   serving: "1 cup raw (30 g)"),
        CatalogFood(name: "Tomato",           calories: 22,  serving: "1 medium (123 g)"),
        CatalogFood(name: "Cucumber",         calories: 16,  serving: "1 cup sliced (104 g)"),
        CatalogFood(name: "Potato, baked",    calories: 161, serving: "1 medium (173 g)"),
        CatalogFood(name: "Sweet potato",     calories: 112, serving: "1 medium (130 g)"),
        CatalogFood(name: "Onion",            calories: 44,  serving: "1 medium (110 g)"),
        CatalogFood(name: "Bell pepper",      calories: 24,  serving: "1 medium (119 g)"),
        CatalogFood(name: "Cauliflower",      calories: 27,  serving: "1 cup (107 g)"),
        CatalogFood(name: "Mushrooms",        calories: 21,  serving: "1 cup sliced (96 g)"),
        CatalogFood(name: "Lettuce",          calories: 5,   serving: "1 cup shredded (47 g)"),
        CatalogFood(name: "Cabbage",          calories: 22,  serving: "1 cup chopped (89 g)"),
        CatalogFood(name: "Corn",             calories: 132, serving: "1 cup kernels (164 g)"),
        CatalogFood(name: "Peas",             calories: 117, serving: "1 cup (160 g)"),
        CatalogFood(name: "Eggplant",         calories: 35,  serving: "1 cup cubed (99 g)"),
        CatalogFood(name: "Zucchini",         calories: 19,  serving: "1 cup sliced (113 g)"),
        CatalogFood(name: "Green beans",      calories: 31,  serving: "1 cup (100 g)"),

        // — Proteins / Meats / Fish —
        CatalogFood(name: "Chicken breast",   calories: 165, serving: "100 g, cooked"),
        CatalogFood(name: "Chicken thigh",    calories: 209, serving: "100 g, cooked"),
        CatalogFood(name: "Beef, ground",     calories: 250, serving: "100 g, cooked"),
        CatalogFood(name: "Steak, sirloin",   calories: 271, serving: "100 g, cooked"),
        CatalogFood(name: "Pork chop",        calories: 231, serving: "100 g, cooked"),
        CatalogFood(name: "Bacon",            calories: 43,  serving: "1 slice cooked"),
        CatalogFood(name: "Ham",              calories: 46,  serving: "1 slice (28 g)"),
        CatalogFood(name: "Turkey breast",    calories: 135, serving: "100 g, cooked"),
        CatalogFood(name: "Salmon",           calories: 208, serving: "100 g, cooked"),
        CatalogFood(name: "Tuna, canned",     calories: 132, serving: "1 can (142 g)"),
        CatalogFood(name: "Shrimp",           calories: 99,  serving: "100 g, cooked"),
        CatalogFood(name: "Cod",              calories: 105, serving: "100 g, cooked"),
        CatalogFood(name: "Tilapia",          calories: 128, serving: "100 g, cooked"),
        CatalogFood(name: "Tofu",             calories: 144, serving: "100 g"),
        CatalogFood(name: "Paneer",           calories: 265, serving: "100 g"),
        CatalogFood(name: "Lentils (dal)",    calories: 230, serving: "1 cup cooked (198 g)"),
        CatalogFood(name: "Chickpeas",        calories: 269, serving: "1 cup cooked (164 g)"),
        CatalogFood(name: "Black beans",      calories: 227, serving: "1 cup cooked (172 g)"),
        CatalogFood(name: "Kidney beans",     calories: 225, serving: "1 cup cooked (177 g)"),
        CatalogFood(name: "Hummus",           calories: 70,  serving: "2 tbsp (30 g)"),

        // — Eggs / Dairy —
        CatalogFood(name: "Egg, boiled",      calories: 78,  serving: "1 large"),
        CatalogFood(name: "Egg, fried",       calories: 90,  serving: "1 large"),
        CatalogFood(name: "Egg, scrambled",   calories: 91,  serving: "1 large"),
        CatalogFood(name: "Omelette (2 eggs)",calories: 188, serving: "2 eggs, plain"),
        CatalogFood(name: "Milk, whole",      calories: 150, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Milk, skim",       calories: 83,  serving: "1 cup (240 ml)"),
        CatalogFood(name: "Almond milk",      calories: 39,  serving: "1 cup (240 ml)"),
        CatalogFood(name: "Yogurt, plain",    calories: 149, serving: "1 cup (245 g)"),
        CatalogFood(name: "Greek yogurt",     calories: 100, serving: "1 cup (245 g)"),
        CatalogFood(name: "Cheddar cheese",   calories: 113, serving: "1 slice (28 g)"),
        CatalogFood(name: "Mozzarella",       calories: 85,  serving: "1 oz (28 g)"),
        CatalogFood(name: "Cream cheese",     calories: 99,  serving: "2 tbsp (29 g)"),
        CatalogFood(name: "Butter",           calories: 102, serving: "1 tbsp (14 g)"),

        // — Grains / Bread / Pasta —
        CatalogFood(name: "White rice",       calories: 205, serving: "1 cup, cooked"),
        CatalogFood(name: "Brown rice",       calories: 216, serving: "1 cup, cooked"),
        CatalogFood(name: "Roti / Chapati",   calories: 120, serving: "1 medium (40 g)"),
        CatalogFood(name: "Naan",             calories: 260, serving: "1 piece (90 g)"),
        CatalogFood(name: "Bread, white",     calories: 79,  serving: "1 slice (28 g)"),
        CatalogFood(name: "Bread, whole wheat", calories: 81, serving: "1 slice (28 g)"),
        CatalogFood(name: "Bagel",            calories: 245, serving: "1 medium"),
        CatalogFood(name: "Pasta, cooked",    calories: 220, serving: "1 cup (140 g)"),
        CatalogFood(name: "Spaghetti w/ sauce", calories: 320, serving: "1 cup with marinara"),
        CatalogFood(name: "Oats, cooked",     calories: 154, serving: "1 cup (234 g)"),
        CatalogFood(name: "Cornflakes",       calories: 100, serving: "1 cup (28 g)"),
        CatalogFood(name: "Granola",          calories: 471, serving: "1 cup (122 g)"),
        CatalogFood(name: "Tortilla, flour",  calories: 138, serving: "1 medium (49 g)"),
        CatalogFood(name: "Quinoa",           calories: 222, serving: "1 cup cooked (185 g)"),
        CatalogFood(name: "Couscous",         calories: 176, serving: "1 cup cooked (157 g)"),
        CatalogFood(name: "Pancake",          calories: 175, serving: "1 medium (38 g)"),
        CatalogFood(name: "Waffle",           calories: 218, serving: "1 round (75 g)"),

        // — Nuts / Seeds —
        CatalogFood(name: "Almonds",          calories: 164, serving: "1 oz (28 g, ~23 nuts)"),
        CatalogFood(name: "Cashews",          calories: 157, serving: "1 oz (28 g)"),
        CatalogFood(name: "Peanuts",          calories: 161, serving: "1 oz (28 g)"),
        CatalogFood(name: "Walnuts",          calories: 185, serving: "1 oz (28 g)"),
        CatalogFood(name: "Pistachios",       calories: 159, serving: "1 oz (28 g)"),
        CatalogFood(name: "Peanut butter",    calories: 188, serving: "2 tbsp (32 g)"),
        CatalogFood(name: "Almond butter",    calories: 196, serving: "2 tbsp (32 g)"),
        CatalogFood(name: "Chia seeds",       calories: 138, serving: "2 tbsp (24 g)"),
        CatalogFood(name: "Flax seeds",       calories: 110, serving: "2 tbsp (20 g)"),

        // — Snacks / Sweets —
        CatalogFood(name: "Potato chips",     calories: 152, serving: "1 oz (28 g)"),
        CatalogFood(name: "Pretzels",         calories: 108, serving: "1 oz (28 g)"),
        CatalogFood(name: "Popcorn, plain",   calories: 31,  serving: "1 cup popped"),
        CatalogFood(name: "Chocolate bar",    calories: 235, serving: "1 bar (45 g)"),
        CatalogFood(name: "Dark chocolate",   calories: 170, serving: "1 oz (28 g)"),
        CatalogFood(name: "Cookie, chocolate chip", calories: 78, serving: "1 medium"),
        CatalogFood(name: "Donut, glazed",    calories: 269, serving: "1 medium"),
        CatalogFood(name: "Ice cream",        calories: 273, serving: "1 cup (132 g)"),
        CatalogFood(name: "Brownie",          calories: 132, serving: "1 small (28 g)"),
        CatalogFood(name: "Muffin, blueberry",calories: 426, serving: "1 large (139 g)"),
        CatalogFood(name: "Croissant",        calories: 272, serving: "1 medium (67 g)"),
        CatalogFood(name: "Granola bar",      calories: 130, serving: "1 bar (28 g)"),
        CatalogFood(name: "Gulab jamun",      calories: 150, serving: "1 piece"),
        CatalogFood(name: "Jalebi",           calories: 150, serving: "1 piece (30 g)"),
        CatalogFood(name: "Laddoo",           calories: 185, serving: "1 piece (40 g)"),

        // — Beverages —
        CatalogFood(name: "Coffee, black",    calories: 2,   serving: "1 cup (240 ml)"),
        CatalogFood(name: "Latte",            calories: 190, serving: "Tall (12 oz, whole milk)"),
        CatalogFood(name: "Cappuccino",       calories: 120, serving: "12 oz, whole milk"),
        CatalogFood(name: "Tea, black",       calories: 2,   serving: "1 cup (240 ml)"),
        CatalogFood(name: "Chai (with milk & sugar)", calories: 120, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Orange juice",     calories: 112, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Apple juice",      calories: 114, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Coca-Cola",        calories: 140, serving: "12 oz can (355 ml)"),
        CatalogFood(name: "Diet Coke",        calories: 0,   serving: "12 oz can (355 ml)"),
        CatalogFood(name: "Sprite",           calories: 140, serving: "12 oz can (355 ml)"),
        CatalogFood(name: "Beer (lager)",     calories: 153, serving: "12 oz (355 ml)"),
        CatalogFood(name: "Wine, red",        calories: 125, serving: "5 oz glass (148 ml)"),
        CatalogFood(name: "Smoothie, fruit",  calories: 200, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Lassi, sweet",     calories: 220, serving: "1 cup (240 ml)"),
        CatalogFood(name: "Coconut water",    calories: 46,  serving: "1 cup (240 ml)"),

        // — Fast food / restaurant —
        CatalogFood(name: "Cheeseburger",     calories: 303, serving: "1 regular (113 g)"),
        CatalogFood(name: "Big Mac",          calories: 563, serving: "1 burger"),
        CatalogFood(name: "Whopper",          calories: 657, serving: "1 burger"),
        CatalogFood(name: "French fries",     calories: 365, serving: "Medium (117 g)"),
        CatalogFood(name: "Pizza slice",      calories: 285, serving: "1 slice cheese"),
        CatalogFood(name: "Chicken nuggets",  calories: 270, serving: "6 piece"),
        CatalogFood(name: "Hot dog",          calories: 290, serving: "1 with bun"),
        CatalogFood(name: "Sub sandwich (6\")", calories: 350, serving: "Turkey, no mayo"),
        CatalogFood(name: "Caesar salad",     calories: 470, serving: "1 entree (with dressing)"),
        CatalogFood(name: "Sushi roll",       calories: 350, serving: "1 roll (8 pcs)"),
        CatalogFood(name: "Burrito",          calories: 510, serving: "1 medium"),
        CatalogFood(name: "Taco",             calories: 170, serving: "1 hard shell"),
        CatalogFood(name: "Ramen",            calories: 380, serving: "1 bowl"),

        // — Indian dishes —
        CatalogFood(name: "Dal makhani",      calories: 280, serving: "1 cup"),
        CatalogFood(name: "Paneer butter masala", calories: 320, serving: "1 cup"),
        CatalogFood(name: "Butter chicken",   calories: 490, serving: "1 cup"),
        CatalogFood(name: "Biryani, chicken", calories: 480, serving: "1 cup"),
        CatalogFood(name: "Samosa",           calories: 260, serving: "1 piece"),
        CatalogFood(name: "Pakora",           calories: 75,  serving: "1 piece"),
        CatalogFood(name: "Dosa, plain",      calories: 168, serving: "1 medium"),
        CatalogFood(name: "Masala dosa",      calories: 250, serving: "1 medium"),
        CatalogFood(name: "Idli",             calories: 39,  serving: "1 piece"),
        CatalogFood(name: "Vada",             calories: 97,  serving: "1 piece"),
        CatalogFood(name: "Poha",             calories: 250, serving: "1 cup"),
        CatalogFood(name: "Upma",             calories: 270, serving: "1 cup"),
        CatalogFood(name: "Aloo paratha",     calories: 260, serving: "1 piece"),
        CatalogFood(name: "Chole",            calories: 269, serving: "1 cup"),
        CatalogFood(name: "Rajma",            calories: 215, serving: "1 cup"),

        // — Condiments / sauces —
        CatalogFood(name: "Olive oil",        calories: 119, serving: "1 tbsp (14 g)"),
        CatalogFood(name: "Mayonnaise",       calories: 94,  serving: "1 tbsp (14 g)"),
        CatalogFood(name: "Ketchup",          calories: 17,  serving: "1 tbsp (15 g)"),
        CatalogFood(name: "Honey",            calories: 64,  serving: "1 tbsp (21 g)"),
        CatalogFood(name: "Sugar, white",     calories: 49,  serving: "1 tbsp (12 g)"),
        CatalogFood(name: "Maple syrup",      calories: 52,  serving: "1 tbsp (20 g)")
    ]
}
