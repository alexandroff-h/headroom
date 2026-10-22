import Foundation

/// Headroom's fourth question is "what IS this thing". A process list cannot
/// answer it: `mdworker_shared` and `Google Chrome Helper (Renderer)` are the
/// names of implementation details, not the names of anything a person started.
///
/// Attribution turns the flat process list into a list of things the reader
/// recognises, and says in plain words what each one is. Everything here is
/// pure and path-based so it can be tested without a running Mac.

public enum AppKind: String, Sendable, Codable {
    /// Something the reader opened. Has a Dock icon or a window.
    case app
    /// Runs on its own behalf: a login item, a menu-bar agent, an updater.
    case background
    /// Part of macOS. Quitting it is not the reader's business.
    case system
    /// We could not attribute it to anything. Said so rather than guessed.
    case unidentified
}

/// What the app target knows from AppKit and Core does not. Built from
/// `NSRunningApplication` and handed in, so Core stays free of AppKit.
public struct LaunchedApp: Sendable, Hashable {
    public let pid: Int32
    public let bundleIdentifier: String?
    public let localizedName: String?
    public let bundlePath: String?
    /// `.regular` in AppKit terms: it has a Dock icon.
    public let hasDockIcon: Bool

    public init(pid: Int32, bundleIdentifier: String?, localizedName: String?, bundlePath: String?, hasDockIcon: Bool) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.bundlePath = bundlePath
        self.hasDockIcon = hasDockIcon
    }
}

/// One row in Headroom. A whole app, not one of its processes.
public struct RunningApp: Sendable, Identifiable, Equatable {
    /// Stable across samples: the bundle path, the bundle id, or the executable
    /// name. Never the pid, which changes when a helper respawns.
    public let id: String
    /// What the reader calls it. "Google Chrome", never "Google Chrome Helper".
    public let name: String
    public let bundleIdentifier: String?
    /// Where the icon comes from, when there is one.
    public let bundlePath: String?
    public let kind: AppKind
    /// One sentence saying what this actually is.
    public let explanation: String
    /// Where it came from, when the path says so plainly.
    public let origin: String?
    public let cpuPercent: Double
    /// Summed resident memory. Shared pages are counted once per process, so
    /// this is a footprint, not an amount that quitting would hand back.
    public let memoryBytes: UInt64
    public let processes: [ProcessSample]
    /// The pid to address a quit request to, when one of these is a real app.
    public let launchedPID: Int32?

    public var processCount: Int { processes.count }
    public var canQuit: Bool { launchedPID != nil && kind != .system }

    /// Two readings that would draw the same pixels are equal.
    ///
    /// Every process on the Mac moves by a few bytes between samples, so an
    /// exact comparison makes every row in the list different every two
    /// seconds, and the whole list redraws. Comparing at the precision the row
    /// actually shows — a tenth of a unit of memory, a whole percent of
    /// processor — lets the list redraw only the rows that visibly changed.
    public static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.kind == rhs.kind
            && lhs.launchedPID == rhs.launchedPID
            && lhs.explanation == rhs.explanation
            && lhs.origin == rhs.origin
            && lhs.processes.count == rhs.processes.count
            && displayedMemory(lhs.memoryBytes) == displayedMemory(rhs.memoryBytes)
            && Int(lhs.cpuPercent.rounded()) == Int(rhs.cpuPercent.rounded())
            && zip(lhs.processes, rhs.processes).allSatisfy { left, right in
                left.pid == right.pid
                    && displayedMemory(left.memoryBytes) == displayedMemory(right.memoryBytes)
                    && Int(left.cpuPercent.rounded()) == Int(right.cpuPercent.rounded())
            }
    }

    /// The figure a row shows, as one comparable integer: bytes scaled into
    /// their display unit, kept to one decimal place, with the unit folded in
    /// so that 2.3 MB and 2.3 GB are not mistaken for each other.
    static func displayedMemory(_ bytes: UInt64) -> Int {
        var amount = Double(bytes)
        var unit = 0
        while amount >= 1024 {
            amount /= 1024
            unit += 1
        }
        return unit * 100_000 + Int((amount * 10).rounded())
    }

    public init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        bundlePath: String?,
        kind: AppKind,
        explanation: String,
        origin: String?,
        cpuPercent: Double,
        memoryBytes: UInt64,
        processes: [ProcessSample],
        launchedPID: Int32?
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.kind = kind
        self.explanation = explanation
        self.origin = origin
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processes = processes
        self.launchedPID = launchedPID
    }
}

public enum Attribution {
    /// Groups a sample's processes into the apps a reader would recognise.
    ///
    /// Two rules do almost all of the work:
    ///
    /// 1. A helper's executable lives inside its app's bundle, so walking the
    ///    path to the *outermost* `.app` collapses every Chrome renderer onto
    ///    Google Chrome without needing a catalogue entry for any of them.
    /// 2. Anything left over is attributed to whoever started it. A `node` with
    ///    no bundle of its own belongs under the editor that launched it, which
    ///    is the honest answer to "what is this" and the actionable one.
    public static func group(processes: [ProcessSample], launched: [LaunchedApp]) -> [RunningApp] {
        let launchedByPID = Dictionary(launched.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var launchedByBundlePath: [String: LaunchedApp] = [:]
        for app in launched {
            guard let path = app.bundlePath else { continue }
            // An app with a Dock icon wins the slot: it is the one worth quitting.
            if let existing = launchedByBundlePath[path], existing.hasDockIcon { continue }
            launchedByBundlePath[path] = app
        }

        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        // Pass one: everything that can name its own bundle.
        var ownKeys: [Int32: String] = [:]
        for process in processes {
            if let key = bundleKey(for: process, launched: launchedByPID[process.pid]) {
                ownKeys[process.pid] = key
            }
        }

        // Pass two: everything else inherits from the nearest ancestor that
        // could. Stops at launchd, which started everything and explains nothing.
        var buckets: [String: [ProcessSample]] = [:]
        var order: [String] = []
        var inherited: Set<Int32> = []

        for process in processes {
            var key = ownKeys[process.pid]
            if key == nil, let ancestorKey = ancestorKey(of: process, byPID: byPID, ownKeys: ownKeys) {
                key = ancestorKey
                inherited.insert(process.pid)
            }
            let resolved = key ?? fallbackKey(for: process, launched: launchedByPID[process.pid])
            if buckets[resolved] == nil {
                buckets[resolved] = []
                order.append(resolved)
            }
            buckets[resolved]?.append(process)
        }

        return order.compactMap { key in
            guard let members = buckets[key], !members.isEmpty else { return nil }
            return assemble(
                key: key,
                members: members,
                launchedByPID: launchedByPID,
                launchedByBundlePath: launchedByBundlePath,
                inherited: inherited
            )
        }
    }

    // MARK: Bucketing

    private static func bundleKey(for process: ProcessSample, launched: LaunchedApp?) -> String? {
        if let bundlePath = launched?.bundlePath, let outer = outermostBundle(in: bundlePath) {
            return "bundle:" + outer
        }
        if let path = process.executablePath, let outer = outermostBundle(in: path) {
            return "bundle:" + outer
        }
        return nil
    }

    private static func fallbackKey(for process: ProcessSample, launched: LaunchedApp?) -> String {
        if let identifier = launched?.bundleIdentifier { return "id:" + identifier }
        // Daemons spawned per request share a name and should read as one thing.
        return "exec:" + process.name
    }

    /// Walks the parent chain. The depth limit is a guard against a cycle in a
    /// reading taken while processes were exiting, not an expected case.
    private static func ancestorKey(of process: ProcessSample, byPID: [Int32: ProcessSample], ownKeys: [Int32: String]) -> String? {
        var current = process.parentPID
        var depth = 0
        while current > 1, depth < 8 {
            if let key = ownKeys[current] { return key }
            guard let parent = byPID[current] else { return nil }
            current = parent.parentPID
            depth += 1
        }
        return nil
    }

    /// `/Applications/Chrome.app/Contents/.../Chrome Helper.app/Contents/MacOS/x`
    /// resolves to `/Applications/Chrome.app`, not to the helper bundle.
    /// A `.appex` is not an `.app`, so a component test is used rather than a
    /// substring search, which would truncate one into the other.
    static func outermostBundle(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var prefix = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            prefix += "/" + component
            if component.hasSuffix(".app") { return prefix }
        }
        return nil
    }

    // MARK: Assembly

    private static func assemble(
        key: String,
        members: [ProcessSample],
        launchedByPID: [Int32: LaunchedApp],
        launchedByBundlePath: [String: LaunchedApp],
        inherited: Set<Int32>
    ) -> RunningApp {
        let cpu = members.reduce(0.0) { $0 + $1.cpuPercent }
        let memory = members.reduce(UInt64(0)) { $0 &+ $1.memoryBytes }
        let bundlePath = key.hasPrefix("bundle:") ? String(key.dropFirst("bundle:".count)) : nil

        // The pid worth addressing: the one AppKit launched, preferring the one
        // with a Dock icon. Helpers must never receive the quit request.
        let launchedMembers = members.compactMap { launchedByPID[$0.pid] }
        let addressable = launchedMembers.first(where: { $0.hasDockIcon })
            ?? bundlePath.flatMap { launchedByBundlePath[$0] }
            ?? launchedMembers.first

        let representative = members.min(by: { $0.pid < $1.pid }) ?? members[0]
        let path = representative.executablePath

        let catalogued = Catalogue.entry(forExecutable: representative.name)
        // A bundle on disk always outranks the catalogue for the *name*: the
        // catalogue exists to explain cryptic executables, not to rename apps.
        let name = bundlePath == nil
            ? (catalogued?.name ?? displayName(bundlePath: nil, launchedName: addressable?.localizedName, fallback: representative.name))
            : displayName(bundlePath: bundlePath, launchedName: addressable?.localizedName, fallback: representative.name)
        let kind = classify(bundlePath: bundlePath, path: path, launched: addressable, name: representative.name)
        let borrowed = members.contains { inherited.contains($0.pid) }

        return RunningApp(
            id: key,
            name: name,
            bundleIdentifier: addressable?.bundleIdentifier ?? bundlePath.flatMap { launchedByBundlePath[$0]?.bundleIdentifier },
            bundlePath: bundlePath,
            kind: kind,
            explanation: explain(
                kind: kind,
                name: name,
                path: path,
                catalogued: catalogued,
                processCount: members.count,
                isLaunched: addressable != nil,
                startedSomething: borrowed
            ),
            origin: origin(bundlePath: bundlePath, path: path),
            cpuPercent: cpu,
            memoryBytes: memory,
            processes: members.sorted { $0.memoryBytes > $1.memoryBytes },
            launchedPID: addressable?.pid
        )
    }

    private static func displayName(bundlePath: String?, launchedName: String?, fallback: String) -> String {
        if let launchedName, !launchedName.isEmpty { return launchedName }
        if let bundlePath {
            var base = (bundlePath as NSString).lastPathComponent
            if base.hasSuffix(".app") { base = String(base.dropLast(4)) }
            // Some apps unpack into a version-numbered folder and name the
            // bundle after it. "2.1.308" tells the reader nothing, so the
            // nearest folder above it that is a word is used instead.
            if looksLikeVersion(base), let better = meaningfulAncestor(of: bundlePath) { return better }
            if !base.isEmpty { return base }
        }
        return fallback
    }

    /// Version numbers and build hashes are not names.
    static func looksLikeVersion(_ text: String) -> Bool {
        if text.isEmpty { return true }
        if text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) { return true }
        // A long run of hex with a digit in it is a content hash, not a word.
        // The digit is what rules out "deadbeef" and "facade", which are hex
        // and are also things somebody might legitimately call a folder.
        if text.count >= 8, text.allSatisfy(\.isHexDigit), text.contains(where: \.isNumber) { return true }
        return false
    }

    private static func meaningfulAncestor(of bundlePath: String) -> String? {
        var components = bundlePath.split(separator: "/").map(String.init)
        components.removeLast()
        while let candidate = components.popLast() {
            if ["Contents", "MacOS", "Resources", "Applications", "Library", "Application Support", "Users"].contains(candidate) { continue }
            if looksLikeVersion(candidate) { continue }
            return candidate
        }
        return nil
    }

    private static func classify(bundlePath: String?, path: String?, launched: LaunchedApp?, name: String) -> AppKind {
        if let launched, launched.hasDockIcon { return .app }
        let reference = bundlePath ?? path
        guard let reference else { return .unidentified }
        if reference.hasPrefix("/System/") || reference.hasPrefix("/usr/libexec/")
            || reference.hasPrefix("/usr/sbin/") || reference.hasPrefix("/sbin/")
            || reference.hasPrefix("/usr/bin/") || reference == "/usr/lib/dyld" {
            return .system
        }
        if Catalogue.entry(forExecutable: name)?.isSystem == true { return .system }
        if bundlePath != nil { return launched == nil ? .background : .app }
        return .background
    }

    private static func origin(bundlePath: String?, path: String?) -> String? {
        guard let reference = bundlePath ?? path else { return nil }
        if reference.hasPrefix("/System/") { return "Ships with macOS" }
        if reference.hasPrefix("/Applications/Utilities/") { return "Utilities folder" }
        if reference.hasPrefix("/Applications/") { return "Applications folder" }
        if reference.hasPrefix(NSHomeDirectory() + "/Applications/") { return "Your Applications folder" }
        if reference.hasPrefix("/usr/libexec/") || reference.hasPrefix("/usr/bin/") || reference.hasPrefix("/sbin/") {
            return "Part of the system"
        }
        if let vendor = vendorFolder(in: reference, under: "/Library/Application Support/") {
            return "Installed by \(vendor)"
        }
        if reference.hasPrefix("/opt/homebrew/") || reference.hasPrefix("/usr/local/Cellar/") {
            return "Installed by Homebrew"
        }
        if reference.hasPrefix(NSHomeDirectory()) { return "Lives in your home folder" }
        return nil
    }

    private static func vendorFolder(in path: String, under prefix: String) -> String? {
        guard let range = path.range(of: prefix) else { return nil }
        let remainder = path[range.upperBound...]
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let vendor = String(remainder[remainder.startIndex..<slash])
        return vendor.isEmpty ? nil : vendor
    }

    private static func explain(
        kind: AppKind,
        name: String,
        path: String?,
        catalogued: Catalogue.Entry?,
        processCount: Int,
        isLaunched: Bool,
        startedSomething: Bool
    ) -> String {
        if let catalogued { return catalogued.explanation }

        let tail = startedSomething ? " A few were started by it rather than shipped with it." : ""

        switch kind {
        case .app:
            if processCount > 1 {
                return "An app you opened. Its \(processCount) processes are windows, tabs and helpers, which is normal for an app built this way.\(tail)"
            }
            return "An app you opened.\(tail)"
        case .background:
            if let path, isCommandLine(path) {
                return "A command-line program: something run in a terminal, or a tool another program started on your behalf.\(tail)"
            }
            if isLaunched {
                return "Runs with no window and no Dock icon: a menu-bar agent, a sync service, or an updater.\(tail)"
            }
            return "Runs in the background with no window. Nothing opened it: either it starts itself at login, or another program started it.\(tail)"
        case .system:
            return "Part of macOS. It does its work whether or not you are using the Mac."
        case .unidentified:
            return "Headroom could not tell what this belongs to: there is no bundle on disk to trace it back to, and nothing it descends from had one either."
        }
    }

    private static func isCommandLine(_ path: String) -> Bool {
        path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/")
            || path.contains("/.local/") || path.contains("/.cargo/")
            || path.contains("/node_modules/") || path.contains("/.nvm/")
            || path.contains("/.bun/") || path.contains("/.rbenv/")
    }
}

/// The processes people actually see at the top of Activity Monitor and cannot
/// decipher. Each entry says what the thing does, in the words someone would
/// use out loud. Anything not listed falls back to a path-derived sentence
/// rather than to a guess.
enum Catalogue {
    struct Entry {
        let name: String
        let explanation: String
        var isSystem = true
    }

    static func entry(forExecutable executable: String) -> Entry? {
        entries[executable]
    }

    private static let entries: [String: Entry] = [
        "kernel_task": Entry(
            name: "macOS kernel",
            explanation: "The core of macOS. It deliberately takes CPU to keep the Mac cool, so high usage here usually means heat rather than a problem to fix."
        ),
        "WindowServer": Entry(
            name: "Window Server",
            explanation: "Draws every window on screen. It gets busy with large displays, many windows, or heavy animation."
        ),
        "launchd": Entry(
            name: "launchd",
            explanation: "Starts and supervises everything else on the Mac. It is the first process to run and the last to stop."
        ),
        "mds": Entry(
            name: "Spotlight indexing",
            explanation: "Builds the Spotlight index so search is instant later. Busy after you copy a lot of files; it settles on its own."
        ),
        "mds_stores": Entry(
            name: "Spotlight index store",
            explanation: "Writes the Spotlight index to disk. Works alongside Spotlight indexing and quiets down with it."
        ),
        "mdworker_shared": Entry(
            name: "Spotlight file reader",
            explanation: "Opens files one at a time so Spotlight can read what is inside them. Many short-lived copies is normal."
        ),
        "mdutil": Entry(name: "Spotlight control", explanation: "Turns Spotlight indexing on or off for a disk."),
        "backupd": Entry(
            name: "Time Machine",
            explanation: "Runs your Time Machine backup. Heavy while a backup is in progress, idle the rest of the time."
        ),
        "photoanalysisd": Entry(
            name: "Photos analysis",
            explanation: "Looks through your photo library for faces, places and objects. Runs when the Mac is idle and plugged in."
        ),
        "mediaanalysisd": Entry(
            name: "Media analysis",
            explanation: "Reads images and video to find text and objects in them, for Photos and Visual Look Up."
        ),
        "cloudd": Entry(
            name: "iCloud",
            explanation: "Moves iCloud data in and out of the Mac for the apps that use it."
        ),
        "bird": Entry(
            name: "iCloud Drive",
            explanation: "Syncs iCloud Drive files. Busy when files are uploading or downloading."
        ),
        "syncdefaultsd": Entry(
            name: "iCloud settings sync",
            explanation: "Keeps app settings in step across your Apple devices."
        ),
        "nsurlsessiond": Entry(
            name: "Background downloads",
            explanation: "Carries out downloads and uploads that apps asked for in the background."
        ),
        "coreaudiod": Entry(
            name: "Core Audio",
            explanation: "Handles all sound on the Mac. It has to run steadily or audio would stutter."
        ),
        "logd": Entry(name: "System log", explanation: "Collects the system log that Console reads."),
        "distnoted": Entry(name: "Notification relay", explanation: "Passes messages between apps when something they both care about changes."),
        "trustd": Entry(name: "Certificate checks", explanation: "Verifies the security certificates behind the connections apps make."),
        "softwareupdated": Entry(name: "Software Update", explanation: "Checks for and downloads macOS updates."),
        "suggestd": Entry(name: "Siri Suggestions", explanation: "Learns from what you do so Spotlight and Siri can suggest things."),
        "parsecd": Entry(name: "Spotlight suggestions", explanation: "Fetches the web results Spotlight shows beside your local ones."),
        "knowledge-agent": Entry(name: "Screen Time", explanation: "Records app and website use for Screen Time."),
        "assistantd": Entry(name: "Siri", explanation: "Listens for and answers Siri requests."),
        "corespotlightd": Entry(name: "In-app search index", explanation: "Indexes what apps put into Spotlight, such as mail and messages."),
        "AMPLibraryAgent": Entry(name: "Music library", explanation: "Keeps the Music and TV libraries up to date."),
        "AMPDeviceDiscoveryAgent": Entry(name: "Device discovery", explanation: "Watches for iPhones and iPads so Music and Finder can see them."),
        "fseventsd": Entry(name: "File change watcher", explanation: "Records which folders changed, so backups and apps know what to re-read."),
        "opendirectoryd": Entry(name: "Accounts service", explanation: "Answers questions about user accounts and groups."),
        "securityd": Entry(name: "Keychain", explanation: "Guards passwords and keys in the keychain."),
        "hidd": Entry(name: "Input devices", explanation: "Reads the keyboard, trackpad and mouse."),
        "powerd": Entry(name: "Power management", explanation: "Decides when the Mac sleeps and how it uses the battery."),
        "thermald": Entry(name: "Thermal management", explanation: "Watches temperature and asks the system to slow down before it gets too hot."),
        "sharingd": Entry(name: "Sharing", explanation: "Runs AirDrop, Handoff and Universal Clipboard."),
        "rapportd": Entry(name: "Continuity", explanation: "Connects the Mac to your other Apple devices for Handoff and unlocking."),
        "ReportCrash": Entry(name: "Crash reporter", explanation: "Writes a report when an app crashes. It runs only after something has already gone wrong."),
        "com.apple.WebKit.WebContent": Entry(
            name: "Safari page",
            explanation: "One web page, in its own process so a bad page cannot take the browser down with it.",
            isSystem: false
        ),
        "com.apple.WebKit.Networking": Entry(
            name: "Safari networking",
            explanation: "Loads data for Safari's open pages.",
            isSystem: false
        ),
        "com.apple.WebKit.GPU": Entry(
            name: "Safari graphics",
            explanation: "Draws web page content using the graphics chip.",
            isSystem: false
        ),
        "node": Entry(
            name: "Node.js",
            explanation: "A running JavaScript program: a dev server, a build watcher, or a tool an editor started.",
            isSystem: false
        ),
        "python3": Entry(name: "Python", explanation: "A running Python program. What it is doing depends on what started it.", isSystem: false),
        "ruby": Entry(name: "Ruby", explanation: "A running Ruby program.", isSystem: false),
        "java": Entry(name: "Java", explanation: "A running Java program.", isSystem: false),
        "docker": Entry(name: "Docker", explanation: "Runs containers. Its virtual machine holds memory whether or not a container is busy.", isSystem: false),
        "com.docker.backend": Entry(name: "Docker engine", explanation: "The part of Docker that actually runs your containers and their virtual machine.", isSystem: false),
        "sourcekit-lsp": Entry(name: "Swift code intelligence", explanation: "Works out Swift completions and errors for your editor.", isSystem: false),
        "SourceKitService": Entry(name: "Xcode code intelligence", explanation: "Works out Swift completions and errors for Xcode.", isSystem: false),
        "swift-frontend": Entry(name: "Swift compiler", explanation: "Compiling Swift code right now. It stops on its own when the build finishes.", isSystem: false),
        "clang": Entry(name: "C compiler", explanation: "Compiling C, C++ or Objective-C code right now.", isSystem: false),
        "rustc": Entry(name: "Rust compiler", explanation: "Compiling Rust code right now.", isSystem: false),
        "gopls": Entry(name: "Go code intelligence", explanation: "Works out Go completions and errors for your editor.", isSystem: false),
        "tsserver": Entry(name: "TypeScript language server", explanation: "Works out TypeScript completions and errors for your editor.", isSystem: false),
    ]
}
