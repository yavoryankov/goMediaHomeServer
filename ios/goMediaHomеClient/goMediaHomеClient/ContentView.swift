import AVKit
import AVFoundation
import Combine
import SwiftUI
import UIKit

private let defaultServerBaseURL = URL(string: "http://YOUR-IMAC-IP:8095/api/v1")!

struct MediaItem: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int64
    let modified: String
    let mime: String
    let keywords: String

    private enum CodingKeys: String, CodingKey {
        case name, path, size, modified, mime, keywords
        case isDir = "is_dir"
    }

    var id: String { path }
    var tags: [String] { keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    func streamURL(baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        return components?.url
    }
}

private struct DirectoryResponse: Codable { let path: String; let items: [MediaItem] }
private struct SearchResponse: Codable { let query: String; let items: [MediaItem] }

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var currentPath = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published private(set) var recentItems: [MediaItem] = []
    @Published private(set) var favoriteItems: [MediaItem] = []
    @Published private(set) var hasCheckedConnection = false
    @Published var apiAddress: String {
        didSet { UserDefaults.standard.set(apiAddress, forKey: "gomedia.apiAddress") }
    }

    init() {
        apiAddress = UserDefaults.standard.string(forKey: "gomedia.apiAddress") ?? defaultServerBaseURL.absoluteString
        recentItems = Self.loadStoredItems(key: "gomedia.recentItems")
        favoriteItems = Self.loadStoredItems(key: "gomedia.favoriteItems")
    }

    private static func loadStoredItems(key: String) -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([MediaItem].self, from: data) else { return [] }
        return items
    }

    private func store(_ items: [MediaItem], key: String) {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    fileprivate var baseURL: URL { URL(string: apiAddress.trimmingCharacters(in: .whitespacesAndNewlines)) ?? defaultServerBaseURL }
    var serverHost: String { baseURL.host ?? "Invalid address" }
    var isConnected: Bool { hasCheckedConnection && errorMessage == nil }

    var pathParts: [String] { currentPath.split(separator: "/").map(String.init) }

    func load(path: String = "") async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "path", value: path)]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(DirectoryResponse.self, from: data)
            items = decoded.items
            currentPath = decoded.path
            hasCheckedConnection = true
        } catch {
            hasCheckedConnection = true
            errorMessage = "\(error.localizedDescription)\n\nURL: \(baseURL.absoluteString)"
        }
    }

    func open(_ item: MediaItem) async { if item.isDir { await load(path: item.path) } }
    func goHome() async { await load() }
    func goUp() async { await load(path: pathParts.dropLast().joined(separator: "/")) }
    func goToBreadcrumb(index: Int) async { await load(path: pathParts.prefix(index + 1).joined(separator: "/")) }

    func recordOpened(_ item: MediaItem) {
        recentItems.removeAll { $0.path == item.path }
        recentItems.insert(item, at: 0)
        recentItems = Array(recentItems.prefix(6))
        store(recentItems, key: "gomedia.recentItems")
    }

    func isFavorite(_ item: MediaItem) -> Bool { favoriteItems.contains { $0.path == item.path } }

    func toggleFavorite(_ item: MediaItem) {
        if isFavorite(item) { favoriteItems.removeAll { $0.path == item.path } }
        else { favoriteItems.insert(item, at: 0) }
        store(favoriteItems, key: "gomedia.favoriteItems")
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { await load(path: currentPath); return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            items = try JSONDecoder().decode(SearchResponse.self, from: data).items
            currentPath = ""
        } catch {
            errorMessage = "The search could not be completed."
        }
    }
}

struct ContentView: View {
    @StateObject private var library = LibraryViewModel()
    @State private var playerItem: MediaItem?
    @State private var selectedTab: AppTab = .types
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .types:
                        typesPage
                    case .directories:
                        directoriesPage
                    case .search:
                        searchPage
                    case .favoriteFiles:
                        favoritesPage(isFolder: false)
                    case .favoriteFolders:
                        favoritesPage(isFolder: true)
                    case .settings:
                        settingsPage
                    }
                }
                bottomBar
            }
            .navigationTitle(selectedTab.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && library.hasCheckedConnection {
                    Task { await library.load(path: library.currentPath) }
                }
            }
            .toolbar {
                if selectedTab == .directories {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Task { await library.goUp() } } label: { Image(systemName: "arrow.left") }
                            .disabled(library.currentPath.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await library.load(path: library.currentPath) } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .task { await library.load() }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .fullScreenCover(item: $playerItem) { item in
                PlayerScreen(item: item, library: library)
            }
        }
    }

    private var directoriesPage: some View {
        VStack(spacing: 0) {
            breadcrumb
            content
        }
    }

    private var typesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Browse by type").font(.headline)
                Text("Choose a category to find content quickly.").font(.subheadline).foregroundStyle(.secondary)
                TypeButton(title: "Video", subtitle: "Movies and recordings", icon: "play.rectangle.fill", color: .purple) {
                    selectedTab = .search; library.searchText = ".mp4"; Task { await library.search() }
                }
                TypeButton(title: "Music", subtitle: "Audio and music files", icon: "music.note", color: .blue) {
                    selectedTab = .search; library.searchText = ".mp3"; Task { await library.search() }
                }
                TypeButton(title: "Documents", subtitle: "PDF, text and office files", icon: "doc.fill", color: .orange) {
                    selectedTab = .search; library.searchText = ".pdf"; Task { await library.search() }
                }
            }
            .padding()
        }
    }

    private var searchPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("File name or keyword", text: $library.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { Task { await library.search() } } label: { Image(systemName: "arrow.right.circle.fill") }
                    .disabled(library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            Text("Results").font(.headline).padding(.horizontal)
            if library.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.items.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Search by file name or keyword."))
            } else {
                List(library.items) { item in
                    MediaRow(item: item) {
                        if item.isDir { Task { await library.open(item) } }
                        else if item.streamURL(baseURL: library.baseURL) != nil { library.recordOpened(item); playerItem = item }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 46, height: 46)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connection")
                            .font(.title3.bold())
                        Text("Configure and test your media server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                connectionPanel
                Button { Task { await library.load(path: library.currentPath) } } label: {
                    Label("Test connection", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top, 18)
        }
    }

    private func favoritesPage(isFolder: Bool) -> some View {
            List {
            Section("Recently opened") {
                if library.recentItems.isEmpty {
                    Text("No recently opened files.").foregroundStyle(.secondary)
                } else {
                    ForEach(library.recentItems.prefix(6)) { item in
                        MediaRow(item: item) {
                            if item.streamURL(baseURL: library.baseURL) != nil {
                                library.recordOpened(item)
                                playerItem = item
                            }
                        }
                    }
                }
            }
            Section(isFolder ? "Favorite folders" : "Favorite files") {
                let favorites = library.favoriteItems.filter { isFolder ? $0.isDir : !$0.isDir }
                if favorites.isEmpty {
                    Text(isFolder ? "No favorite folders yet." : "No favorite files yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(favorites) { item in
                        HStack {
                            MediaRow(item: item) {
                                if item.isDir { Task { await library.open(item) } }
                                else if item.streamURL(baseURL: library.baseURL) != nil { playerItem = item }
                            }
                            Button { library.toggleFavorite(item) } label: {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isFolder ? "Favorite Folders" : "Favorite Files")
    }

    private var bottomBar: some View {
        HStack {
            tabButton(.types, icon: "square.grid.2x2.fill", title: "Types")
            tabButton(.directories, icon: "folder.fill", title: "Folders")
            tabButton(.search, icon: "magnifyingglass", title: "Search")
            tabButton(.favoriteFiles, icon: "star.square.fill", title: "Favorite files")
            tabButton(.favoriteFolders, icon: "folder.fill.badge.plus", title: "Favorite folders")
            tabButton(.settings, icon: "gearshape.fill", title: "Settings")
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func tabButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button { selectedTab = tab } label: {
            Image(systemName: icon).font(.title3)
            .foregroundStyle(selectedTab == tab ? .blue : .secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Server connection", systemImage: library.isConnected ? "checkmark.circle.fill" : "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(library.isConnected ? .green : .orange)
                Spacer()
                Text("LAN: \(library.serverHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
                            TextField("http://YOUR-IMAC-IP:8095/api/v1", text: $library.apiAddress)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await library.load(path: library.currentPath) } }
            HStack {
                Text("API address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(library.isConnected ? "Available" : "Offline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(library.isConnected ? .green : .red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button("Library") { Task { await library.goHome() } }
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(library.pathParts.enumerated()), id: \.offset) { index, part in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    Button(part) { Task { await library.goToBreadcrumb(index: index) } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder private var content: some View {
        if library.isLoading {
            ProgressView("Loading...").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = library.errorMessage {
            ContentUnavailableView("No connection", systemImage: "wifi.exclamationmark", description: Text(error))
                .overlay(alignment: .bottom) { Button("Try again") { Task { await library.load(path: library.currentPath) } }.buttonStyle(.borderedProminent).padding(.bottom, 30) }
        } else if library.items.isEmpty {
            ContentUnavailableView("Empty folder", systemImage: "folder", description: Text("There are no files in this folder."))
        } else {
            List(library.items) { item in
                HStack(spacing: 8) {
                    MediaRow(item: item) {
                        if item.isDir { Task { await library.open(item) } }
                        else if item.streamURL(baseURL: library.baseURL) != nil { library.recordOpened(item); playerItem = item }
                    }
                    if item.isDir {
                        Button { library.toggleFavorite(item) } label: {
                            Image(systemName: library.isFavorite(item) ? "folder.fill.badge.star" : "folder")
                                .foregroundStyle(library.isFavorite(item) ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct PlayerScreen: View {
    let item: MediaItem
    @ObservedObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var audioController: AudioEQController?
    @State private var audioLoading = false
    @State private var showEqualizer = false
    @State private var equalizerBands = Array(repeating: 0.0, count: 12)

    private let frequencies = ["10", "30", "50", "75", "100", "125", "1k", "2k", "4k", "10k", "16k", "20k"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else if item.mime.hasPrefix("audio/") {
                VStack(spacing: 18) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 76, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    if audioLoading { ProgressView().tint(.white) }
                }
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 54, height: 54).background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Button { library.toggleFavorite(item) } label: {
                        Image(systemName: library.isFavorite(item) ? "star.fill" : "star")
                            .font(.title2.weight(.semibold)).foregroundStyle(library.isFavorite(item) ? .yellow : .white)
                            .frame(width: 54, height: 54).background(.ultraThinMaterial, in: Circle())
                    }
                    if item.mime.hasPrefix("audio/") {
                        Button { withAnimation(.easeInOut(duration: 0.2)) { showEqualizer.toggle() } } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title2.weight(.semibold)).foregroundStyle(.white)
                                .frame(width: 54, height: 54).background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                Spacer()
            }

            if showEqualizer {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rock").font(.headline)
                            Text("Equalizer").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") { equalizerBands = Array(repeating: 0.0, count: 12) }
                            .font(.caption.weight(.semibold))
                        Button { withAnimation { showEqualizer = false } } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(frequencies.indices, id: \.self) { index in
                            VStack(spacing: 5) {
                                Text(frequencies[index]).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                                VerticalBandSlider(value: $equalizerBands[index])
                                Text(index < 6 ? "L" : "H").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    HStack { Text("+12 dB"); Spacer(); Text("0"); Spacer(); Text("−12 dB") }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .foregroundStyle(.white)
                .background(Color(red: 0.08, green: 0.10, blue: 0.13), in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 10)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            guard let url = item.streamURL(baseURL: library.baseURL) else { return }
            if item.mime.hasPrefix("audio/") {
                audioLoading = true
                Task {
                    do {
                        let (localURL, _) = try await URLSession.shared.download(from: url)
                        let controller = try AudioEQController(fileURL: localURL, gains: equalizerBands)
                        controller.play()
                        audioController = controller
                    } catch {
                        audioLoading = false
                    }
                    audioLoading = false
                }
            } else {
                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                newPlayer.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            audioController?.stop()
            audioController = nil
        }
        .onChange(of: equalizerBands) { _, values in
            audioController?.setGains(values)
        }
    }

}

@MainActor
private final class AudioEQController {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 12)
    private let frequencies: [Float] = [10, 30, 50, 75, 100, 125, 1000, 2000, 4000, 10000, 16000, 20000]

    init(fileURL: URL, gains: [Double]) throws {
        engine.attach(player)
        engine.attach(equalizer)
        engine.connect(player, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 1.0
            band.gain = Float(gains[index])
            band.bypass = false
        }
        let file = try AVAudioFile(forReading: fileURL)
        player.scheduleFile(file, at: nil)
    }

    func play() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
        try? engine.start()
        player.play()
    }

    func setGains(_ gains: [Double]) {
        for (index, gain) in gains.enumerated() where index < equalizer.bands.count {
            equalizer.bands[index].gain = Float(gain)
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct VerticalBandSlider: View {
    @Binding var value: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)).frame(width: 8)
            Slider(value: $value, in: -12...12, step: 1)
                .tint(.red)
                .frame(width: 132)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 132)
    }
}

private enum AppTab {
    case types, directories, search, favoriteFiles, favoriteFolders, settings

    var title: String {
        switch self {
        case .types: return "Media Types"
        case .directories: return "Directories"
        case .search: return "Search"
        case .favoriteFiles: return "Favorite Files"
        case .favoriteFolders: return "Favorite Folders"
        case .settings: return "Settings"
        }
    }
}

private struct TypeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 34)).foregroundStyle(color).frame(width: 58, height: 58).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.bold()).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct MediaRow: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: item.isDir ? "folder.fill" : iconName).font(.title2).foregroundStyle(item.isDir ? .blue : .teal).frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(item.isDir ? "Folder" : formattedSize).font(.caption).foregroundStyle(.secondary)
                    if !item.tags.isEmpty { Text(item.tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption2).foregroundStyle(.teal).lineLimit(1) }
                }
                Spacer()
                Image(systemName: item.isDir ? "chevron.right" : "play.circle").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var formattedSize: String { ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file) }
    private var iconName: String {
        switch item.mime {
        case let value where value.hasPrefix("audio/"): return "music.note"
        case let value where value.hasPrefix("video/"): return "play.rectangle.fill"
        case let value where value.hasPrefix("image/"): return "photo"
        case "application/pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

