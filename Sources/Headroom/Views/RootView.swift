import SwiftUI
import HeadroomCore

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Group {
            switch model.screen {
            case .now: NowScreen(model: model)
            case .apps: RunningScreen(model: model)
            case .progress: ProgressScreen(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Ink.surface.overlay { Grain() } }
        .frame(minWidth: Metrics.minimumWidth, minHeight: Metrics.minimumHeight)
        // The tabs live in the window's own toolbar. On macOS 26 a segmented
        // picker there is real Liquid Glass, drawn by the system, sitting over
        // the content and picking up whatever scrolls under it. Nothing I can
        // hand-build in the content view will match it.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.screen) {
                    ForEach(Screen.allCases) { screen in
                        Text(screen.label).tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // A fixed width divides into three equal segments, so "Now"
                // got a selection pill twice the width of its word while
                // "Progress" ran to the capsule's inner edge with no padding
                // left. Sizing to content gives every label the same margin.
                .fixedSize()
                .help("Now, Apps, Progress")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        Text("Match system").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                } label: {
                    Image(systemName: appearance == "dark" ? "moon" : appearance == "light" ? "sun.max" : "circle.lefthalf.filled")
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Appearance")
                .help("Appearance")
            }
        }
        .confirmationDialog(
            "Force \(model.confirmingForceQuit?.name ?? "this app") to quit?",
            isPresented: Binding(
                get: { model.confirmingForceQuit != nil },
                set: { if !$0 { model.confirmingForceQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                if let app = model.confirmingForceQuit { model.forceQuit(app) }
                model.confirmingForceQuit = nil
            }
            Button("Cancel", role: .cancel) { model.confirmingForceQuit = nil }
        } message: {
            Text("The app is stopped immediately and cannot save. Anything unsaved in it is lost.")
        }
    }
}

/// A little room above four rising strokes. The space is the mark.
struct HeadroomMark: View {
    var body: some View {
        Canvas { context, size in
            var cap = Path()
            cap.move(to: CGPoint(x: 1, y: 1))
            cap.addLine(to: CGPoint(x: size.width - 1, y: 1))
            context.stroke(cap, with: .color(Ink.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for i in 0..<4 {
                let x = 2 + CGFloat(i) * (size.width - 4) / 3
                let h = size.height * (0.25 + Double(i) * 0.12)
                var stroke = Path()
                stroke.move(to: CGPoint(x: x, y: size.height - 1))
                stroke.addLine(to: CGPoint(x: x, y: size.height - h))
                context.stroke(stroke, with: .color(Ink.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: 1000, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
