#if os(macOS)
import Darwin
import Foundation
import Network
import SystemConfiguration

/// Fork: limits automatic network activity to networks the user marked as home.
///
/// Off a home network LumenDesk doesn't scan on its own (no multicast, broadcast or subnet
/// sweep) and doesn't poll saved lights; a manual scan still works. Networks are recognised by
/// the Wi-Fi/Ethernet subnet, router address and the router's MAC address. The kernel hides ARP
/// entries from apps (they read back as 02:00:00:00:00:00), but configd publishes the MAC it
/// resolved for the router in `State:/Network/Service/<id>/IPv4`, which a sandboxed app can read
/// without Location access. Networks saved before the MAC was read match on subnet and router
/// address and take the MAC the first time they match.
@MainActor
final class NativeNetworkGate: ObservableObject {
    struct Network: Codable, Hashable, Identifiable {
        let subnet: String   // "192.168.0.0/24"
        let gateway: String  // "192.168.0.1"
        /// The router's MAC ("aa:bb:cc:dd:ee:ff"), or nil when configd hasn't resolved one, or
        /// for a home saved before LumenDesk read it.
        var router: String?

        var id: String { "\(subnet)|\(gateway)|\(router ?? "")" }
        var title: String {
            let base = "\(subnet) via \(gateway)"
            return router.map { "\(base) (\($0))" } ?? base
        }

        /// Whether `current` is this saved network: subnet and router address must agree, and
        /// once this entry knows the router's MAC, `current` must report the same one (a network
        /// whose MAC isn't readable yet doesn't count as home).
        func matches(_ current: Network) -> Bool {
            guard subnet == current.subnet, gateway == current.gateway else { return false }
            guard let router else { return true }
            return current.router == router
        }

        /// Saved homes with any entry that has no MAC yet upgraded to `current`'s, if it matches.
        static func upgrading(_ homes: [Network], with current: Network?) -> [Network] {
            guard let current, let mac = current.router else { return homes }
            return homes.map { home in
                guard home.router == nil, home.matches(current) else { return home }
                return Network(subnet: home.subnet, gateway: home.gateway, router: mac)
            }
        }

        /// The router MAC configd resolved for `gateway` on `interface`, from the values of
        /// `State:/Network/Service/*/IPv4`, normalised to lowercase two-digit octets.
        static func routerMAC(in services: [[String: Any]], interface: String, gateway: String) -> String? {
            for service in services {
                let names = ["InterfaceName", "ConfirmedInterfaceName"].compactMap { service[$0] as? String }
                guard names.contains(interface), service["ARPResolvedIPAddress"] as? String == gateway,
                      let raw = service["ARPResolvedHardwareAddress"] as? String,
                      let mac = normalizedMAC(raw) else { continue }
                return mac
            }
            return nil
        }

        /// "98:3:8e:…" as "98:03:8e:…". Nil for anything that isn't a unicast MAC, and for the
        /// placeholder 02:00:00:00:00:00 that macOS returns in place of a hidden one.
        static func normalizedMAC(_ raw: String) -> String? {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 6 else { return nil }
            var octets: [UInt8] = []
            for part in parts {
                guard (1...2).contains(part.count), let octet = UInt8(part, radix: 16) else { return nil }
                octets.append(octet)
            }
            guard octets[0] & 1 == 0, octets != [2, 0, 0, 0, 0, 0], octets.contains(where: { $0 != 0 }) else { return nil }
            return octets.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
    }

    @Published private(set) var current: Network?
    @Published private(set) var homes: [Network] {
        didSet {
            if let data = try? JSONEncoder().encode(homes) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }

    var isHome: Bool {
        guard let current else { return false }
        return homes.contains { $0.matches(current) }
    }

    private static let key = "Native.homeNetworks.v1"
    private var monitors: [NWPathMonitor] = []
    private var paths: [NWInterface.InterfaceType: NWPath] = [:]
    private weak var manager: LightManager?
    private var wasHome = false
    /// Tells the gate when configd resolves (or loses) a router's MAC after the path changed.
    private var store: SCDynamicStore?

    /// How the configd callback reaches the gate, weakly.
    private final class StoreObserver {
        weak var gate: NativeNetworkGate?
    }

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
        watchServices()
    }

    private func watchServices() {
        let observer = StoreObserver()
        observer.gate = self
        // Retained for the life of the app, like the store it serves; it only holds the gate weakly.
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passRetained(observer).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "LumenDesk" as CFString, { _, _, info in
            guard let info else { return }
            let observer = Unmanaged<StoreObserver>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in observer.gate?.recompute() }
        }, &context) else { return }
        SCDynamicStoreSetNotificationKeys(store, nil, [Self.servicePattern] as CFArray)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
    }

    func rememberCurrent() {
        guard let current, !isHome else { return }
        homes.append(current)
        apply()
    }

    func forget(_ network: Network) {
        homes.removeAll { $0 == network }
        apply()
    }

    private func update(_ type: NWInterface.InterfaceType, _ path: NWPath) {
        paths[type] = path
        recompute()
    }

    private func recompute() {
        let next = [NWInterface.InterfaceType.wiredEthernet, .wifi].lazy
            .compactMap { self.paths[$0] }
            .compactMap(Self.network(for:))
            .first
        if next != current { current = next }
        apply()
    }

    private func apply() {
        let upgraded = Network.upgrading(homes, with: current)
        if upgraded != homes { homes = upgraded }
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
        return Network(subnet: subnet, gateway: gateway, router: routerMAC(interface: interface.name, gateway: gateway))
    }

    private static let servicePattern = "State:/Network/Service/[^/]+/IPv4"

    private static func routerMAC(interface: String, gateway: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "LumenDesk" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, servicePattern as CFString) as? [String] else { return nil }
        let services = keys.compactMap { SCDynamicStoreCopyValue(store, $0 as CFString) as? [String: Any] }
        return Network.routerMAC(in: services, interface: interface, gateway: gateway)
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
