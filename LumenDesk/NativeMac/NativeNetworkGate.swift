#if os(macOS)
import Darwin
import Foundation
import Network

/// Fork: limits automatic network activity to networks the user marked as home.
///
/// Off a home network LumenDesk doesn't scan on its own (no multicast, broadcast or subnet
/// sweep) and doesn't poll saved lights; a manual scan still works. Networks are recognised by
/// the Wi-Fi/Ethernet subnet and router address. That's a weak fingerprint (two networks using
/// the same private range and router address look alike), but macOS doesn't expose the router's
/// MAC address to apps.
@MainActor
final class NativeNetworkGate: ObservableObject {
    struct Network: Codable, Hashable, Identifiable {
        let subnet: String   // "192.168.0.0/24"
        let gateway: String  // "192.168.0.1"
        var id: String { "\(subnet)|\(gateway)" }
        var title: String { "\(subnet) via \(gateway)" }
    }

    @Published private(set) var current: Network?
    @Published private(set) var homes: [Network] {
        didSet {
            if let data = try? JSONEncoder().encode(homes) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }

    var isHome: Bool { current.map(homes.contains) ?? false }

    private static let key = "Native.homeNetworks.v1"
    private var monitors: [NWPathMonitor] = []
    private var paths: [NWInterface.InterfaceType: NWPath] = [:]
    private weak var manager: LightManager?
    private var wasHome = false

    init() {
        homes = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Network].self, from: $0) } ?? []
    }

    /// Starts watching the network and applies the gate to `manager`. Safe to call more than once.
    func attach(_ manager: LightManager) {
        guard self.manager == nil else { return }
        self.manager = manager
        manager.networkActivityAllowed = false
        // Watch the physical interfaces directly: with a VPN up, the default path is the tunnel.
        for type in [NWInterface.InterfaceType.wifi, .wiredEthernet] {
            let monitor = NWPathMonitor(requiredInterfaceType: type)
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in self?.update(type, path) }
            }
            monitor.start(queue: .main)
            monitors.append(monitor)
        }
    }

    func rememberCurrent() {
        guard let current, !homes.contains(current) else { return }
        homes.append(current)
        apply()
    }

    func forget(_ network: Network) {
        homes.removeAll { $0 == network }
        apply()
    }

    private func update(_ type: NWInterface.InterfaceType, _ path: NWPath) {
        paths[type] = path
        current = [NWInterface.InterfaceType.wiredEthernet, .wifi].lazy
            .compactMap { self.paths[$0] }
            .compactMap(Self.network(for:))
            .first
        apply()
    }

    private func apply() {
        let home = isHome
        manager?.networkActivityAllowed = home
        if home, !wasHome { manager?.scan() }  // arrived on a home network
        wasHome = home
    }

    private static func network(for path: NWPath) -> Network? {
        guard path.status == .satisfied, let interface = path.availableInterfaces.first,
              let gateway = path.gateways.lazy.compactMap({ endpoint -> String? in
                  if case let .hostPort(host, _) = endpoint, case let .ipv4(address) = host { return "\(address)" }
                  return nil
              }).first,
              let subnet = subnet(of: interface.name) else { return nil }
        return Network(subnet: subnet, gateway: gateway)
    }

    /// "192.168.0.0/24" for the interface's IPv4 address.
    private static func subnet(of name: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard String(cString: ifa.ifa_name) == name, let addr = ifa.ifa_addr, let mask = ifa.ifa_netmask,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let network = ip & netmask
            let octets = [24, 16, 8, 0].map { String((network >> UInt32($0)) & 0xFF) }
            return "\(octets.joined(separator: "."))/\(netmask.nonzeroBitCount)"
        }
        return nil
    }
}
#endif
