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

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g. Apple)", text: $name)
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                }
            }
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
        Int(calories) != nil &&
        (Int(calories) ?? 0) > 0
    }

    private func save() {
        guard let cals = Int(calories) else { return }
        let entry = FoodEntry(name: name.trimmingCharacters(in: .whitespaces), calories: cals)
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
