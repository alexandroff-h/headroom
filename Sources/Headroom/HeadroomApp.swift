import AppKit
import SwiftUI
import HeadroomCore

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--sample") {
            Task {
                await printSample()
                exit(EXIT_SUCCESS)
            }
            dispatchMain()
        }
        HeadroomApp.main()
    }

    /// A terminal read-out of the same readings the window shows, so the
    /// measurements can be checked without launching a window server session.
    private static func printSample() async {
        do {
            let sampler = SystemSampler()
            _ = try await sampler.sample()
            try await Task.sleep(for: .seconds(1))
            let snapshot = try await sampler.sample()
            let launched = await MainActor.run {
                NSWorkspace.shared.runningApplications.map {
                    LaunchedApp(
                        pid: $0.processIdentifier,
                        bundleIdentifier: $0.bundleIdentifier,
                        localizedName: $0.localizedName,
                        bundlePath: $0.bundleURL?.path,
                        hasDockIcon: $0.activationPolicy == .regular
                    )
                }
            }
            let apps = Attribution.group(processes: snapshot.processes, launched: launched)
            let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot)

            print(diagnosis.title)
            print(diagnosis.explanation)
            print("")
            print("Processor  \(Measure.percent(snapshot.cpuPercent, digits: 0).inline)")
            print("Memory     \(Measure.memory(snapshot.memoryUsedBytes).inline) of \(Measure.memory(snapshot.memoryTotalBytes, digits: 0).inline)")
            print("Pressure   \(snapshot.memoryPressure.rawValue)")
            print("")

            let suggestions = SuggestionEngine.rank(apps: apps, snapshot: snapshot, frontmostID: nil, idleSeconds: [:])
            print(suggestions.isEmpty ? "Nothing worth closing." : "Things you could do:")
            for suggestion in suggestions {
                print("  \(suggestion.headline) — \(suggestion.reason) [\(Measure.memory(suggestion.footprintBytes).inline)]")
            }
            print("")

            print("Everything running:")
            for app in apps.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(12) {
                let name = app.name.padding(toLength: min(28, max(app.name.count, 28)), withPad: " ", startingAt: 0)
                print("  \(name)  \(Measure.memory(app.memoryBytes).inline.padding(toLength: 10, withPad: " ", startingAt: 0))  \(Measure.percent(app.cpuPercent, digits: 0).inline.padding(toLength: 6, withPad: " ", startingAt: 0))  \(app.kind.rawValue)")
                print("      \(app.explanation)")
            }
            for warning in snapshot.warnings {
                print("Unavailable: \(warning)")
            }
        } catch {
            FileHandle.standardError.write(Data("Headroom could not sample this Mac: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

@MainActor
struct HeadroomApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("Headroom") {
            RootView(model: model)
                .background(WindowChrome(model: model, appearance: appearance))
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { model.start() }
        }
        .defaultSize(width: Metrics.windowWidth, height: Metrics.windowHeight)
        .windowResizability(.contentMinSize)
        .commands {
            // A monitor has nothing to create, open, or print.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandMenu("View") {
                Picker("Screen", selection: $model.screen) {
                    ForEach(Screen.allCases) { screen in
                        Text(screen.label).tag(screen)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// The three things a SwiftUI scene cannot say about an AppKit window: that its
/// background is the one material, that its title bar is part of that material,
/// and that an invisible window should stop sampling every two seconds.
///
/// All of it runs once. `updateNSView` is called during a view update, and
/// touching observed state from there asks SwiftUI to update while it is
/// already updating.
private struct WindowChrome: NSViewRepresentable {
    let model: AppModel
    let appearance: String

    final class Coordinator {
        var configured = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        attach(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        attach(view, coordinator: context.coordinator)
        DispatchQueue.main.async {
            view.window?.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
            view.window?.backgroundColor = Ink.surfaceNSColor
        }
    }

    /// The window does not exist yet when the view is made, so this polls the
    /// next few run-loop turns until it does.
    ///
    /// It used to rely on SwiftUI calling `updateNSView` again. If the window
    /// was still unattached on the first hop and no further update happened to
    /// come, the window was never configured at all: no surface colour, no
    /// occlusion observer, so sampling stayed at the visible rate forever.
    private func attach(_ view: NSView, coordinator: Coordinator, attempt: Int = 0) {
        guard !coordinator.configured, attempt < 20 else { return }
        DispatchQueue.main.async {
            guard !coordinator.configured else { return }
            guard let window = view.window else {
                attach(view, coordinator: coordinator, attempt: attempt + 1)
                return
            }
            coordinator.configured = true
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.backgroundColor = Ink.surfaceNSColor
        window.titlebarAppearsTransparent = true
        // The scroll-edge hairline is how a Mac window says there is content
        // above the fold. It is the only line the chrome draws.
        window.titlebarSeparatorStyle = .automatic
        window.titleVisibility = .hidden
        window.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight)
        NSWindow.allowsAutomaticWindowTabbing = false

        // SwiftUI's own autosave key embeds the view type's memory address, so
        // it changes on every build: the preferences fill up with dozens of
        // dead frame entries and the restored one is whichever build happened
        // to write last. One stable name instead.
        window.setFrameAutosaveName("HeadroomWindow")

        // A restored frame can be taller than the display it comes back on, or
        // sit off the bottom of it, and then the app launches to a window
        // nobody can see. Bring it back onto the screen it is on.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            if frame != window.frame { window.setFrame(frame, display: true) }
        }

        // Capture affordances, for photographing the design without a pointer.
        // `HEADROOM_WINDOW=820x1560` opens a window taller than anyone would
        // use, so a whole scrolling column fits in one frame;
        // `HEADROOM_SCREEN=progress` opens on the other screen;
        // `HEADROOM_EXPAND=Chrome` opens that row. None of them does anything
        // unless the variable is set, and none of them invents a reading.
        let environment = ProcessInfo.processInfo.environment
        if let size = environment["HEADROOM_WINDOW"] {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            }
        }
        if let name = environment["HEADROOM_SCREEN"], let screen = Screen(rawValue: name) {
            model.screen = screen
        }

        if let want = environment["HEADROOM_EXPAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                MainActor.assumeIsolated {
                    model.expandedAppID = model.apps.first { $0.name.localizedCaseInsensitiveContains(want) }?.id
                }
            }
        }

        model.setVisible(window.occlusionState.contains(.visible))
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                model.setVisible(window.occlusionState.contains(.visible))
            }
        }
    }
}
