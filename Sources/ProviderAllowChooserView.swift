import SwiftUI

/// First-run / settings-revisitable allow chooser inspired by ChatGPT’s plugin picker.
/// Selecting providers only marks local tracking/usage-peek permission and queues Connect Usage —
/// it does not create a MOMO account or a cloud OAuth scraper.
struct ProviderAllowChooserView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: Set<AIProvider>
    var onContinue: (Set<AIProvider>) -> Void
    var onDismiss: (() -> Void)?

    init(
        initial: Set<AIProvider>? = nil,
        onContinue: @escaping (Set<AIProvider>) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        let seed = initial ?? Set(AIProvider.allCases)
        _selection = State(initialValue: seed)
        self.onContinue = onContinue
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AnimatedMomoMark(size: 42, animated: false)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                    ProviderMark(provider: .codex, size: 42, active: true)
                }
                Text("Choose providers to track")
                    .font(BarBoyStyle.display)
                    .multilineTextAlignment(.center)
                Text("You can revisit this anytime in Settings.")
                    .font(BarBoyStyle.bodySmall)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(AIProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider().overlay(BarBoyStyle.hairline.opacity(0.7))
                    }
                    HStack(spacing: 12) {
                        ProviderMark(provider: provider, size: 28, active: selection.contains(provider))
                        Text(provider.name)
                            .font(BarBoyStyle.rowTitle)
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { selection.contains(provider) },
                            set: { enabled in
                                if enabled { selection.insert(provider) } else { selection.remove(provider) }
                            }
                        ))
                        .labelsHidden()
                        .tint(BarBoyStyle.coral)
                        .accessibilityLabel("Allow \(provider.name)")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selection.contains(provider) { selection.remove(provider) }
                        else { selection.insert(provider) }
                    }
                }
            }
            .background(BarBoyStyle.surface)
            .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
            .padding(.horizontal, 18)

            Text("MOMO opens each selected provider’s official usage page in an isolated WebKit view. No Safari/Chrome cookie import. No MOMO account.")
                .font(BarBoyStyle.microLabel)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            Button {
                onContinue(selection)
            } label: {
                Text(selection.isEmpty ? "Continue without providers" : "Continue with selected providers")
                    .font(BarBoyStyle.navLabel)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(BarBoyStyle.inverseInk)
                    .background(Color.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 420)
        .background(BarBoyStyle.panel)
        .overlay(Rectangle().stroke(BarBoyStyle.hairline, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
    }
}
