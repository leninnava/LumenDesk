import Foundation

/// A scene from Govee's scene library (fork).
struct GoveeScene: Identifiable, Hashable {
    let name: String
    let category: String
    let code: UInt16
    let param: Data

    var id: String { "\(category)/\(name)" }

    var frames: [[UInt8]] { GoveeBluetoothProtocol.sceneFrames(code: code, param: param) }
}

/// Govee's per-model scene catalogue (fork). The endpoint is the one the Govee Home app uses;
/// it needs no account. Each model's catalogue is downloaded once and cached on disk, so scenes
/// keep working offline.
@MainActor
final class GoveeSceneStore: ObservableObject {
    enum Status: Equatable {
        case loading
        case loaded([GoveeScene])
        case failed(String)
    }

    @Published private(set) var status: [String: Status] = [:]  // keyed by SKU

    private let cacheDirectory: URL?
    private let maxCacheAge: TimeInterval = 7 * 24 * 3600
    /// A model's catalogue is about 30 KB; anything far larger isn't one.
    nonisolated static let maxResponseBytes = 2_000_000
    nonisolated static let maxScenes = 500

    init(cacheDirectory: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("LumenDesk/GoveeScenes", isDirectory: true)) {
        self.cacheDirectory = cacheDirectory
    }

    func scenes(for sku: String) -> [GoveeScene]? {
        if case .loaded(let scenes) = status[sku] { return scenes }
        return nil
    }

    /// Loads the model's scenes from the cache, refreshing it when it's missing or a week old.
    func load(sku: String) {
        switch status[sku] {
        case .loading?, .loaded?: return
        case .failed?, nil: break
        }

        let cached = cacheURL(sku).flatMap { url -> (data: Data, age: TimeInterval)? in
            guard let data = try? Data(contentsOf: url),
                  let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                      .contentModificationDate else { return nil }
            return (data, Date().timeIntervalSince(modified))
        }
        if let cached, let scenes = try? Self.parse(cached.data), !scenes.isEmpty {
            status[sku] = .loaded(scenes)
            if cached.age < maxCacheAge { return }
        } else {
            status[sku] = .loading
        }

        Task {
            do {
                let data = try await Self.download(sku: sku)
                let scenes = try Self.parse(data)
                status[sku] = .loaded(scenes)
                if let url = cacheURL(sku) {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                    try? data.write(to: url, options: .atomic)
                }
            } catch {
                // Keep a stale cache rather than replacing it with an error.
                if scenes(for: sku) == nil {
                    status[sku] = .failed("Couldn't download the scene list: \(error.localizedDescription)")
                }
            }
        }
    }

    private func cacheURL(_ sku: String) -> URL? {
        let safe = sku.filter { $0.isLetter || $0.isNumber }
        guard !safe.isEmpty else { return nil }
        return cacheDirectory?.appendingPathComponent("\(safe).json")
    }

    private static func download(sku: String) async throws -> Data {
        var components = URLComponents(string: "https://app2.govee.com/appsku/v1/light-effect-libraries")!
        components.queryItems = [URLQueryItem(name: "sku", value: sku)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("6.5.02", forHTTPHeaderField: "AppVersion")
        request.setValue("GoveeHome/6.5.02 (com.ihoment.GoVeeSensor; build:2; iOS 16.5.0) Alamofire/5.6.4",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard data.count <= maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    /// Parses the library response. Scenes with several effects are speed variants; the first
    /// is the default. Field names, including Govee's "scence" spelling, match the API.
    nonisolated static func parse(_ data: Data) throws -> [GoveeScene] {
        struct Response: Decodable {
            struct Body: Decodable { let categories: [Category] }
            struct Category: Decodable {
                let categoryName: String
                let scenes: [Scene]
            }
            struct Scene: Decodable {
                let sceneName: String
                let lightEffects: [Effect]
            }
            struct Effect: Decodable {
                let sceneCode: UInt16
                let scenceParam: String
            }
            let data: Body
        }
        guard data.count <= maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        let scenes = try JSONDecoder().decode(Response.self, from: data).data.categories.flatMap { category in
            category.scenes.compactMap { scene -> GoveeScene? in
                guard let effect = scene.lightEffects.first, effect.sceneCode != 0,
                      let param = Data(base64Encoded: effect.scenceParam),
                      param.count <= GoveeBluetoothProtocol.maxSceneParamBytes else { return nil }
                return GoveeScene(name: scene.sceneName, category: category.categoryName, code: effect.sceneCode,
                                  param: param)
            }
        }
        return Array(scenes.prefix(maxScenes))
    }
}
