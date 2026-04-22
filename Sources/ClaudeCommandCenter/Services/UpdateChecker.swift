import Foundation
import Combine

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(ReleaseInfo)
    case downloading(progress: Double)
    case ready(ReleaseInfo, stagedAppURL: URL)
    case installing
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var state: UpdateState = .idle
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }

    private static let autoCheckKey = "ClaudeCommandCenter.autoCheckForUpdates"
    private static let periodicInterval: TimeInterval = 6 * 3600  // 6h
    private let githubRepo = "starc007/claude-command-center"

    private var periodicTimer: Timer?

    private init() {
        self.autoCheckEnabled = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    // MARK: - Public

    /// Kicks off auto-checking: one check on launch + a repeating timer.
    func startAutoCheck() {
        guard autoCheckEnabled else { return }
        periodicTimer?.invalidate()
        Task { [weak self] in await self?.check(silently: true) }
        periodicTimer = Timer.scheduledTimer(withTimeInterval: Self.periodicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(silently: true) }
        }
    }

    /// Manual "Check for updates" — surfaces the "up to date" state to the UI.
    func checkNow() {
        Task { await check(silently: false) }
    }

    // MARK: - Core check

    private func check(silently: Bool) async {
        if case .downloading = state { return }
        if case .installing  = state { return }

        if !silently { state = .checking }

        do {
            let latest = try await fetchLatestRelease()
            let current = AppVersion.current
            if latest.version > current {
                state = .available(latest)
            } else if !silently {
                state = .upToDate(checkedAt: .now)
            } else if case .checking = state {
                state = .upToDate(checkedAt: .now)
            }
        } catch {
            if !silently {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - GitHub API

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeCommandCenter", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "UpdateChecker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GitHub returned \((response as? HTTPURLResponse)?.statusCode ?? -1)"]
            )
        }

        struct APIResponse: Decodable {
            let tag_name: String
            let html_url: String
            let published_at: String?
            let body: String?
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let version = AppVersion(decoded.tag_name) else {
            throw NSError(
                domain: "UpdateChecker", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unparseable tag: \(decoded.tag_name)"]
            )
        }
        guard let zipAsset = decoded.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let zipURL = URL(string: zipAsset.browser_download_url) else {
            throw NSError(
                domain: "UpdateChecker", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Release has no .zip asset"]
            )
        }

        let published = decoded.published_at.flatMap(iso.date(from:))

        return ReleaseInfo(
            version: version,
            tagName: decoded.tag_name,
            releaseURL: URL(string: decoded.html_url) ?? zipURL,
            zipDownloadURL: zipURL,
            publishedAt: published,
            body: decoded.body ?? ""
        )
    }

    nonisolated(unsafe) private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Download + install

    func downloadAndStage() {
        guard case .available(let release) = state else { return }
        state = .downloading(progress: 0)
        Task { [weak self] in
            do {
                let staged = try await Updater.downloadAndStage(release: release) { progress in
                    Task { @MainActor in
                        if case .downloading = self?.state {
                            self?.state = .downloading(progress: progress)
                        }
                    }
                }
                await MainActor.run {
                    self?.state = .ready(release, stagedAppURL: staged)
                }
            } catch {
                await MainActor.run {
                    self?.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func installStagedUpdate() {
        guard case .ready(_, let stagedURL) = state else { return }
        state = .installing
        do {
            try Updater.installAndRelaunch(stagedAppURL: stagedURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
