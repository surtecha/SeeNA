import SwiftUI
import Combine

struct RefractionResultContent: View {
    let record: RefractionRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your result").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Label(record.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("EXPERIMENTAL · NOT A PRESCRIPTION")
                .font(.caption.weight(.bold)).tracking(0.6)
            ForEach(Eye.allCases, id: \.self) { eye in eyeCard(eye) }
            Text("Not clinically validated. Actual eye power may differ. Do not use this estimate to buy glasses or contacts.")
                .font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("How it’s calculated") {
                Text("Three clarity boundaries are converted using −1 ÷ distance in metres. The range spans the observed pass/fail boundaries with a 0.5 cm tape-reading allowance, not a clinical confidence interval. Focus effort, astigmatism, eye disease and display errors are not included. Rounding to 0.25 D does not mean 0.25 D accuracy.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 10)
            }
            DisclosureGroup("See answers") {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(record.levels) { level in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(level.eye.displayName) · Round \(level.repetition + 1) · \(level.measuredDistanceMetres * 100, specifier: "%.1f") cm")
                                .font(.subheadline.bold())
                            HStack { Text("Correct"); Spacer(); Text("Your answer") }.font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(zip(level.targets, level.responses).enumerated()), id: \.offset) { index, pair in
                                HStack {
                                    Text("\(index + 1). \(pair.0.rawValue.capitalized)")
                                    Spacer()
                                    Text(pair.1 == .notVisible ? "Not visible" : pair.1.rawValue.capitalized)
                                    Image(systemName: pair.1.matches(pair.0) ? "checkmark.circle.fill" : "xmark.circle")
                                }.font(.callout)
                            }
                        }.padding(14).background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(.top, 12)
            }
        }
    }
    private func eyeCard(_ eye: Eye) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(eye.displayName) eye").font(.headline)
            switch record.outcome(for: eye) {
            case .estimate(let midpoint, let lower, let upper):
                Text("≈ \(RefractionEstimator.roundedToQuarterDiopter(midpoint), specifier: "%.2f") D")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text("Endpoint range: \(floor(lower * 4) / 4, specifier: "%.2f") to \(ceil(upper * 4) / 4, specifier: "%.2f") D")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .outsideRange:
                Text("Outside test range").font(.title3.bold())
                Text("No bounded clarity threshold from 40 cm to 2 m. This does not rule out an eye problem.")
                    .font(.callout).foregroundStyle(.secondary)
            case .inconsistent, .incomplete:
                Text("Repeat needed").font(.title3.bold())
                Text("The measurements did not agree. No estimate is available.").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

@MainActor
final class RefractionHistoryViewModel: ObservableObject {
    @Published private(set) var records: [RefractionRecord] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = true
    @Published private(set) var deleting = false
    private var loadInProgress = false
    private let store: RefractionStore
    init(store: RefractionStore) { self.store = store }
    func load() async {
        guard !loadInProgress, !deleting else { return }
        loadInProgress = true
        loading = true
        defer { loading = false; loadInProgress = false }
        do {
            let loaded = try await store.load()
            guard !Task.isCancelled else { return }
            records = loaded; error = nil
        }
        catch is CancellationError { return }
        catch { self.error = "Could not open saved results. Nothing was deleted." }
    }
    func delete(_ id: UUID) async {
        guard !loadInProgress, !deleting else { return }
        deleting = true
        defer { deleting = false }
        do { try await store.delete(id); records = try await store.load(); error = nil }
        catch { self.error = "Could not delete this result. Try again." }
    }
}

struct RefractionHistoryView: View {
    @StateObject private var model: RefractionHistoryViewModel
    @State private var pendingDelete: UUID?
    init(store: RefractionStore) { _model = StateObject(wrappedValue: RefractionHistoryViewModel(store: store)) }
    var body: some View {
        List {
            if let error = model.error {
                Section("Needs attention") {
                    Text(error).accessibilityLabel("History error. " + error)
                    Button("Try again") { Task { await model.load() } }.disabled(model.loading || model.deleting)
                }
            }
            if model.loading, model.records.isEmpty {
                ProgressView("Opening saved results").frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            if model.records.isEmpty, model.error == nil, !model.loading {
                ContentUnavailableView("No estimates saved", systemImage: "calendar.badge.plus",
                    description: Text("Save a result after your measurement."))
            }
            ForEach(model.records) { record in
                NavigationLink {
                    ScrollView { RefractionResultContent(record: record).padding(24) }
                        .navigationTitle("Saved estimate").navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("Right: \(record.outcome(for: .right).shortDescription)")
                        Text("Left: \(record.outcome(for: .left).shortDescription)")
                    }.font(.subheadline).padding(.vertical, 6)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = record.id }
                        .disabled(model.loading || model.deleting)
                }
            }
            Section { Text("Experimental estimates · Stored on this iPhone").font(.caption).foregroundStyle(.secondary) }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: model.error) { _, error in
            if let error { UIAccessibility.post(notification: .announcement, argument: error) }
        }
        .alert("Delete this result?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { pendingDelete = nil; Task { await model.delete(id) } }
            }
        } message: { Text("This also deletes its answer record.") }
    }
}

struct SavedResultsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var selection = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Result type", selection: $selection) {
                Text("Vision checks").tag(0)
                Text("Eye power").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
            if selection == 0 {
                SessionHistoryView(model: SessionHistoryViewModel(store: dependencies.sessionStore))
            } else { RefractionHistoryView(store: dependencies.refractionStore) }
        }.navigationTitle("Saved results").navigationBarTitleDisplayMode(.inline)
    }
}
