//
//  ContentView.swift
//  caloriecounter
//
//  Created by Avi Chadda on 02/05/26
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
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @AppStorage("dailyGoal") private var dailyGoal: Int = 2000
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

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
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFoodView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView {
                    hasCompletedOnboarding = true
                    showingOnboarding = false
                }
            }
            .onAppear {
                refreshDayIfNeeded()
                if !hasCompletedOnboarding { showingOnboarding = true }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshDayIfNeeded()
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, newValue in
                if !newValue { showingOnboarding = true }
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

    // All foods, loaded from Supabase.
    @State private var foods: [FavoriteFood] = []
    @State private var loadState: LoadState = .loading

    /// Favourite food IDs persisted across launches as a CSV of UUID strings.
    @AppStorage("favoriteFoodIDs") private var favoriteIDsCSV: String = ""

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var favoriteIDs: Set<UUID> {
        Set(favoriteIDsCSV
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) })
    }

    /// Foods filtered by the current query (case-insensitive). Prefix matches
    /// come before substring matches for a more useful search order.
    private var filteredFoods: [FavoriteFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return foods }
        let prefix = foods.filter { $0.name.lowercased().hasPrefix(trimmed) }
        let contains = foods.filter {
            !$0.name.lowercased().hasPrefix(trimmed) &&
            $0.name.lowercased().contains(trimmed)
        }
        return prefix + contains
    }

    private var favoriteFoods: [FavoriteFood] {
        filteredFoods.filter { favoriteIDs.contains($0.id) }
    }

    private var otherFoods: [FavoriteFood] {
        filteredFoods.filter { !favoriteIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g. Apple)", text: $name)
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                }

                switch loadState {
                case .loading:
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading foods…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                case .failed(let message):
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Couldn't load foods", systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await loadFoods() }
                            }
                            .font(.footnote)
                        }
                    }

                case .loaded:
                    if !favoriteFoods.isEmpty {
                        Section {
                            ForEach(favoriteFoods) { food in
                                foodRow(food)
                            }
                        } header: {
                            Text("Favourites")
                        }
                    }

                    Section {
                        if otherFoods.isEmpty && favoriteFoods.isEmpty {
                            Text(query.isEmpty
                                 ? "No foods available."
                                 : "No matches for \"\(query)\".")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(otherFoods) { food in
                                foodRow(food)
                            }
                        }
                    } header: {
                        Text(query.isEmpty ? "Popular foods" : "Matches")
                    } footer: {
                        Text("Swipe right on a food to add it to your favourites.")
                            .font(.caption2)
                    }
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
            .task { await loadFoods() }
        }
    }

    @ViewBuilder
    private func foodRow(_ food: FavoriteFood) -> some View {
        let isFavorite = favoriteIDs.contains(food.id)
        Button {
            name = food.name
            calories = String(food.calories)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).foregroundStyle(.primary)
                    if !food.serving.isEmpty {
                        Text(food.serving)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(food.calories) kcal")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation { toggleFavorite(food.id) }
            } label: {
                if isFavorite {
                    Label("Unfavourite", systemImage: "star.slash.fill")
                } else {
                    Label("Favourite", systemImage: "star.fill")
                }
            }
            .tint(isFavorite ? .gray : .yellow)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(calories) ?? 0) > 0
    }

    private func save() {
        guard let cals = Int(calories) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let entry = FoodEntry(name: trimmedName, calories: cals)
        modelContext.insert(entry)
        dismiss()
    }

    private func toggleFavorite(_ id: UUID) {
        var ids = favoriteIDs
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        favoriteIDsCSV = ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func loadFoods() async {
        loadState = .loading
        do {
            foods = try await SupabaseService.fetchFavoriteFoods()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyGoal") private var dailyGoal: Int = 2000
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var goalText: String = ""
    @State private var showingWheel: Bool = false

    private let donateURL = URL(string: "https://wise.com/pay/business/sandeepchadda?utm_source=open_link")!
    private let companyURL = URL(string: "https://zozimustechnologies.github.io/")!
    private let contactURL = URL(string: "mailto:zozimustechnologies@outlook.com")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        HStack {
                            Text("Daily goal")
                            Spacer()
                            // Tap the value to reveal a fine-grained wheel.
                            Button {
                                withAnimation { showingWheel.toggle() }
                            } label: {
                                Text("\(dailyGoal) kcal")
                                    .foregroundStyle(showingWheel ? Color.accentColor : .secondary)
                                    .monospacedDigit()
                            }
                            .buttonStyle(.plain)

                            // Keep the - | + stepper (coarse, 100 kcal steps).
                            Stepper("", value: $dailyGoal, in: 100...20000, step: 100)
                                .labelsHidden()
                        }

                        if showingWheel {
                            Picker("Daily goal", selection: $dailyGoal) {
                                ForEach(100...20000, id: \.self) { value in
                                    Text("\(value) kcal").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxHeight: 150)
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
                        Text("Tap the value for a precise wheel (1 kcal steps), use the − / + stepper for quick 100 kcal changes, or type a custom value.")
                    }

                    Section {
                        Button {
                            hasCompletedOnboarding = false
                            dismiss()
                        } label: {
                            Label("Show onboarding again", systemImage: "sparkles")
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
            .onChange(of: dailyGoal) { _, newValue in
                goalText = "\(newValue)"
            }
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
    var onFinish: () -> Void

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
                Button {
                    if isLastPage {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "Get Started" : "Next")
                }
                .buttonStyle(BrandButtonStyle(color: .blue))
                .padding(.horizontal, 32)

                Button("Skip") {
                    onFinish()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 28)
                .opacity(isLastPage ? 0 : 1)
                .allowsHitTesting(!isLastPage)
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
