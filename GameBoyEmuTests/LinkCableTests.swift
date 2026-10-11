import Foundation
import Network
import Testing
@testable import GameBoyEmu

// MARK: - Serial port

@Test func aTransferWithNoCableFinishesAndReceivesAllOnes() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0

    memory[0xFF01] = 0x42
    memory[0xFF02] = 0x81 // Start a transfer, providing the clock

    memory.tickClock(cycles: 4092)
    #expect(memory[0xFF02] & 0x80 != 0) // Still going: 8 bits take 4096 cycles
    #expect(memory[0xFF0F] & 0x08 == 0)

    memory.tickClock(cycles: 4)
    #expect(memory[0xFF01] == 0xFF)
    #expect(memory[0xFF02] & 0x80 == 0)
    #expect(memory[0xFF0F] & 0x08 != 0) // The serial interrupt
}

@Test func aConsoleWaitingForTheOtherClockWaitsForever() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0

    memory[0xFF01] = 0x42
    memory[0xFF02] = 0x80 // Start a transfer, but let the other console provide the clock

    memory.tickClock(cycles: 100_000)
    #expect(memory[0xFF01] == 0x42)
    #expect(memory[0xFF02] & 0x80 != 0)
    #expect(memory[0xFF0F] & 0x08 == 0)
}

// MARK: - Link cable

@Test func linkedConsolesSwapABytePerTransfer() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    let cable = LinkCable(first, second)
    first.memory[0xFF0F] = 0
    second.memory[0xFF0F] = 0

    second.memory[0xFF01] = 0x34
    second.memory[0xFF02] = 0x80 // Waits for the clock
    first.memory[0xFF01] = 0x12
    first.memory[0xFF02] = 0x81 // Provides it

    try cable.run(cycles: 4200)

    #expect(first.memory[0xFF01] == 0x34)
    #expect(second.memory[0xFF01] == 0x12)
    for memory in [first.memory, second.memory] {
        #expect(memory[0xFF02] & 0x80 == 0)
        #expect(memory[0xFF0F] & 0x08 != 0)
    }
}

@Test func aConsoleThatIsNotListeningIsLeftAlone() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    let cable = LinkCable(first, second)
    second.memory[0xFF0F] = 0

    second.memory[0xFF01] = 0x34 // No transfer set up on this side
    first.memory[0xFF01] = 0x12
    first.memory[0xFF02] = 0x81

    try cable.run(cycles: 4200)

    #expect(first.memory[0xFF01] == 0xFF)
    #expect(second.memory[0xFF01] == 0x34)
    #expect(second.memory[0xFF0F] & 0x08 == 0)
}

@Test func linkedConsolesStayInStep() throws {
    // Each console counts in RAM as fast as it can: INC (HL) in a loop, with HL = 0xC000
    let program: [UInt8] = [0x21, 0x00, 0xC0, 0x34, 0x18, 0xFD]
    let first = try makeGameBoy(program: program)
    let second = try makeGameBoy(program: program)
    let cable = LinkCable(first, second)

    try cable.run(cycles: 100_000)

    // Having run the same program for the same time, they must have got equally far
    #expect(first.memory[0xC000] == second.memory[0xC000])
    #expect(first.cpu.pc == second.cpu.pc)
}

@Test func unpluggingTheCableLeavesBothConsolesOnTheirOwn() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    do {
        _ = LinkCable(first, second)
    }
    #expect(first.memory.serial.cable == nil)
    #expect(second.memory.serial.cable == nil)
}

// MARK: - A cable with a delay, as over a network

@Test func aTransferStaysOpenUntilTheAnswerArrives() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0
    var sent: [LinkMessage] = []
    memory.serial.cable = { sent.append($0) }

    memory[0xFF01] = 0x12
    memory[0xFF02] = 0x81
    memory.tickClock(cycles: 4096)
    #expect(sent == [.clock(0x12)])

    memory.tickClock(cycles: 100_000) // However long the answer takes
    #expect(sent.count == 1)
    #expect(memory[0xFF02] & 0x80 != 0)
    #expect(memory[0xFF0F] & 0x08 == 0)

    memory.serial.receive(.reply(0x34))
    memory.tickClock(cycles: 4)
    #expect(memory[0xFF01] == 0x34)
    #expect(memory[0xFF02] & 0x80 == 0)
    #expect(memory[0xFF0F] & 0x08 != 0)
}

@Test func unpluggingTheCableEndsATransferThatIsWaitingForItsAnswer() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0
    memory.serial.cable = { _ in }

    memory[0xFF01] = 0x12
    memory[0xFF02] = 0x81
    memory.tickClock(cycles: 4096)
    memory.serial.cable = nil
    memory.tickClock(cycles: 4)

    #expect(memory[0xFF01] == 0xFF)
    #expect(memory[0xFF02] & 0x80 == 0)
    #expect(memory[0xFF0F] & 0x08 != 0)
}

@Test func linkMessagesSurviveTheTripOverTheWire() {
    for message in [LinkMessage.clock(0x00), .clock(0xFF), .reply(0x12)] {
        #expect(LinkMessage(bytes: message.bytes) == message)
    }
    #expect(LinkMessage(bytes: [2, 0x12]) == nil) // Not a kind of message
    #expect(LinkMessage(bytes: [0]) == nil)
}

@Test(.timeLimit(.minutes(1))) func linkMessagesCrossARealConnection() async throws {
    // A listener on this machine, on whichever port is free, that reports what it receives
    let (ports, portFound) = AsyncStream.makeStream(of: NWEndpoint.Port.self)
    let (received, deliver) = AsyncStream.makeStream(of: LinkMessage.self)
    let listener = try NetworkListener { TCP() }
        .onStateUpdate { listener, state in
            if state == .ready, let port = listener.port {
                portFound.yield(port)
            }
        }
    let host = Task {
        try await listener.run { connection in
            try await NetworkLink.carry(AsyncStream { _ in }, over: connection) { deliver.yield($0) }
        }
    }
    defer { host.cancel() }

    let port = try #require(await ports.first { _ in true })
    let (outgoing, send) = AsyncStream.makeStream(of: LinkMessage.self)
    let guest = Task {
        try await withNetworkConnection(to: .hostPort(host: "127.0.0.1", port: port), using: { TCP() }) { connection in
            try await NetworkLink.carry(outgoing, over: connection) { _ in }
        }
    }
    defer { guest.cancel() }

    send.yield(.clock(0x12))
    send.yield(.reply(0x34))

    var messages: [LinkMessage] = []
    for await message in received.prefix(2) {
        messages.append(message)
    }
    #expect(messages == [.clock(0x12), .reply(0x34)])
}
