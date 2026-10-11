//
//  NetworkLink.swift
//  GameBoyEmu
//

import Foundation
import Network

/// A link cable between two devices, over the local network.
///
/// One device hosts: it advertises itself with Bonjour and waits. The other browses for
/// hosts and joins one. After that the two are equals, each passing along whatever its
/// game puts on the cable. Devices that aren't on the same Wi-Fi network still find each
/// other, over peer-to-peer Wi-Fi.
enum NetworkLink {
    /// Also declared under NSBonjourServices in Info.plist, which Bonjour requires.
    static let serviceType = "_gblink._tcp"

    /// Advertises this device under `name` and links `emulator` with the one console that
    /// connects. Runs until it is cancelled or fails.
    ///
    /// - Parameters:
    ///   - onLinkChange: Called with `true` when a console connects and `false` when it
    ///     has gone again.
    ///   - onWaiting: Called while something is keeping the device from being found, such
    ///     as not being allowed to use the local network.
    static func host(
        name: String,
        emulator: Emulator,
        onLinkChange: @escaping @Sendable (Bool) -> Void,
        onWaiting: @escaping @Sendable (NWError) -> Void
    ) async throws {
        var name = name
        while name.utf8.count > 63 { // The longest name Bonjour allows
            name.removeLast()
        }
        try await NetworkListener(for: .bonjour(name: name, type: serviceType), using: parameters)
            .newConnectionLimit(1) // A link cable has two ends
            .onStateUpdate { _, state in
                if case .waiting(let error) = state {
                    onWaiting(error)
                }
            }
            .run { connection in
                onLinkChange(true)
                defer { onLinkChange(false) }
                try await link(emulator, over: connection)
            }
    }

    /// Looks for hosts, reporting the full list each time it changes. Runs until it is
    /// cancelled or fails.
    ///
    /// Cancel it before joining a host: browsing over peer-to-peer Wi-Fi slows the
    /// connection down.
    ///
    /// - Parameter onWaiting: Called while something is keeping it from looking, such as
    ///   not being allowed to use the local network.
    static func browse(
        onUpdate: @escaping @Sendable ([Bonjour.Endpoint]) async -> Void,
        onWaiting: @escaping @Sendable (NWError) -> Void
    ) async throws {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        try await NetworkBrowser(for: .bonjour(serviceType), using: parameters)
            .onStateUpdate { _, state in
                if case .waiting(let error) = state {
                    onWaiting(error)
                }
            }
            .run { hosts -> Void in
                await onUpdate(hosts)
            }
    }

    /// Connects to `host` and links `emulator` with its console. Runs until it is cancelled,
    /// the host goes away, or the connection fails.
    ///
    /// - Parameter onLinked: Called once the connection is up.
    static func join(
        _ host: Bonjour.Endpoint,
        emulator: Emulator,
        onLinked: @escaping @Sendable () -> Void
    ) async throws {
        try await withNetworkConnection(to: host.nwEndpoint, using: parameters) { connection in
            connection.onStateUpdate { _, state in
                if state == .ready {
                    onLinked()
                }
            }
            if connection.state == .ready {
                onLinked() // It got there before anyone was watching
            }
            try await link(emulator, over: connection)
        }
    }

    private static var parameters: NWParametersBuilder<TCP> {
        // Without noDelay, TCP holds small messages back for a while in case more follow.
        // Every message here is two bytes, and each one is holding up a game.
        NWParametersBuilder.parameters { TCP().noDelay(true) }.peerToPeerIncluded(true)
    }

    /// Plugs the connection into the emulator's serial port for as long as it lasts.
    private static func link(_ emulator: Emulator, over connection: NetworkConnection<TCP>) async throws {
        let (outgoing, continuation) = AsyncStream.makeStream(of: LinkMessage.self)
        await emulator.plugInCable { continuation.yield($0) }
        do {
            try await carry(outgoing, over: connection) { await emulator.receiveFromCable($0) }
        } catch {
            await emulator.unplugCable()
            throw error
        }
        await emulator.unplugCable()
    }

    /// Sends `outgoing` messages down the connection and delivers the ones that come up it,
    /// until either direction ends.
    static func carry(
        _ outgoing: AsyncStream<LinkMessage>,
        over connection: NetworkConnection<TCP>,
        deliver: @escaping @Sendable (LinkMessage) async -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await message in outgoing {
                    try await connection.send(message.bytes)
                }
            }
            group.addTask {
                while true {
                    let (bytes, _) = try await connection.receive(exactly: 2)
                    guard let message = LinkMessage(bytes: bytes) else {
                        throw GameBoyError.unexpected(reason: "The other device sent something that isn't link cable data.")
                    }
                    await deliver(message)
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}

/// On the wire a message is two bytes: which kind it is, then the byte it carries.
extension LinkMessage {
    var bytes: [UInt8] {
        switch self {
        case .clock(let byte): [0, byte]
        case .reply(let byte): [1, byte]
        }
    }

    init?(bytes: some Collection<UInt8>) {
        guard bytes.count == 2, let kind = bytes.first, let byte = bytes.dropFirst().first else {
            return nil
        }
        switch kind {
        case 0: self = .clock(byte)
        case 1: self = .reply(byte)
        default: return nil
        }
    }
}
