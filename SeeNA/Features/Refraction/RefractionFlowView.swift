import SwiftUI

struct RefractionFlowView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = RefractionViewModel()
    @State private var confirmExit = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                    if let message = model.message {
                        Label(message, systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .navigationTitle("Eye power")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        if model.phase == .introduction || model.saved { dismiss() }
                        else { model.pauseForExit(using: dependencies); confirmExit = true }
                    }.labelStyle(.iconOnly).disabled(model.saving)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false } }
            }
            .confirmationDialog("Leave this measurement?", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("Keep measuring") { confirmExit = false }
                Button("Leave without saving", role: .destructive) { dismiss() }
            } message: { Text("Unsaved answers will be lost.") }
        }
        .tint(.black)
        .interactiveDismissDisabled(model.phase != .introduction && !model.saved)
        .onDisappear { model.stopVoice(using: dependencies); dependencies.brightness.restore() }
#if DEBUG && targetEnvironment(simulator)
        .task { await SimulatorRefractionAutomation.drive(model, dependencies: dependencies, displayScale: displayScale) }
#endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.repeatPosition(using: dependencies)
                dependencies.brightness.restore()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .introduction:
            heading("Measure with a helper.", "Experimental myopia estimate")
            Label("Stay seated. A helper moves the phone.", systemImage: "person.2")
            Label("You’ll need a ruler and a measuring tape.", systemImage: "ruler")
            Text("Not clinically validated. Not a prescription or a test for astigmatism or long sight. Do not use the estimate to order glasses.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle(isOn: $model.eligibilityConfirmed) {
                Text("I’m 18+, have known short sight, have removed glasses and contacts, have no known eye disease or recent eye surgery, and have no new symptoms.")
                    .font(.callout)
            }
            Text("Sudden vision change, pain or injury? Stop and seek urgent eye care.")
                .font(.callout.weight(.semibold))
            Button("Set up with my helper") { model.begin() }
                .buttonStyle(PrimaryActionStyle()).disabled(!model.eligibilityConfirmed)
        case .calibration:
            heading("Measure this line.", "Screen setup")
            Text("Measure the full line, including its end marks. Enter the length in millimetres.")
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Rectangle().frame(width: 1, height: 18)
                Rectangle().frame(width: 198, height: 2)
                Rectangle().frame(width: 1, height: 18)
            }.frame(width: 200).frame(maxWidth: .infinity).padding(.vertical, 32)
                .accessibilityLabel("Calibration line, measure its full outer width")
            measurementField("Measured length", text: $model.rulerMillimetres, unit: "mm")
            Text("Read to within 0.5 mm. Keep Display Zoom unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Continue") { inputFocused = false; model.calibrate(displayScale: displayScale) }
                .buttonStyle(PrimaryActionStyle())
        case .positioning:
            heading("\(model.requestedCentimetres) cm", "\(model.eye.displayName) eye · Round \(model.round) of 3")
            Text("Helper: move the phone to this distance from the \(model.eye.rawValue) eye. Keep it at eye height.")
                .foregroundStyle(.secondary)
            Text("Cover the \(model.eye.eyeToCover) eye without pressing on it.").font(.headline)
            measurementField("Actual tape reading", text: $model.distanceCentimetres, unit: "cm")
            Text("Read the tape to within 0.5 cm. Then keep the phone and head still.")
                .font(.callout).foregroundStyle(.secondary)
            Button("In position · start") { inputFocused = false; model.startLevel(using: dependencies) }
                .buttonStyle(PrimaryActionStyle())
        case .answering:
            heading("\(model.eye.displayName) eye", "Answer \(model.answers.count + 1) of 3 · Round \(model.round) of 3")
            ZStack {
                Color.white
                if let target = model.currentTarget, !model.speaking {
                    TumblingETarget(direction: target).fill(.black)
                        .frame(width: model.targetPoints, height: model.targetPoints)
                        .accessibilityHidden(true)
                } else { Text("Get ready").foregroundStyle(.secondary) }
            }
            .frame(height: 220)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.black.opacity(0.08)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Direction target. Say where the three arms point.")
            HStack {
                if model.voiceState == .processing { ProgressView().controlSize(.small) }
                else { Image(systemName: model.listening ? "waveform" : "mic") }
                Text(model.voiceState.label)
                Spacer()
                Button("Listen") { model.startVoice(using: dependencies) }
                    .disabled(!model.voiceState.canStartListening)
            }.font(.callout.weight(.semibold))
            Text("Say a direction, or ask your helper to tap it.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(OptotypeDirection.allCases, id: \.self) { direction in
                    Button(direction.rawValue.capitalized) { model.submit(OptotypeResponse(direction), using: dependencies) }
                        .buttonStyle(SecondaryActionStyle())
                }
            }.disabled(model.speaking)
            Button("I can’t see it") { model.submit(.notVisible, using: dependencies) }
                .buttonStyle(SecondaryActionStyle()).disabled(model.speaking)
            Button("Position changed · measure again") { model.repeatPosition(using: dependencies) }
                .font(.callout).frame(minHeight: 44)
        case .nextEye:
            heading("Switch eyes.", "Right eye complete")
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 52)).padding(.vertical, 24)
            Text("Cover your right eye. Your helper will move the phone back to the starting position.")
                .foregroundStyle(.secondary)
            Button("Continue with left eye") { model.nextEye() }.buttonStyle(PrimaryActionStyle())
        case .finished:
            if let record = model.record {
                RefractionResultContent(record: record)
                Button(model.saved ? "Saved with date" : model.saving ? "Saving…" : "Save result") {
                    Task { await model.save(to: dependencies.refractionStore) }
                }
                .buttonStyle(PrimaryActionStyle()).disabled(model.saved || model.saving)
                if model.saved { Button("Done") { dismiss() }.buttonStyle(SecondaryActionStyle()) }
            }
        }
    }

    private func heading(_ title: String, _ eyebrow: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
        }
    }
    private func measurementField(_ label: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline)
            HStack {
                TextField("Enter measurement", text: text).keyboardType(.decimalPad).focused($inputFocused)
                    .accessibilityLabel(label + " in " + unit)
                Text(unit).foregroundStyle(.secondary)
            }.padding(18).background(SEENATheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Five equal units: three horizontal arms and a vertical spine. The shape
/// faces right before rotation. No scaling/clamping to an accessible minimum.
struct TumblingETarget: Shape {
    let direction: OptotypeDirection
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let u = rect.width / 5
        path.addRect(CGRect(x: 0, y: 0, width: u, height: 5 * u))
        for y in [0.0, 2.0, 4.0] { path.addRect(CGRect(x: u, y: y * u, width: 4 * u, height: u)) }
        let transform = CGAffineTransform(translationX: -rect.width / 2, y: -rect.height / 2)
            .concatenating(CGAffineTransform(rotationAngle: direction.rotationDegrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return path.applying(transform)
    }
}
