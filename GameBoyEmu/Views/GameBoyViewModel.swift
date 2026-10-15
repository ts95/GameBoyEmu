//
//  GameBoyViewModel.swift
//  GameBoyEmu
//

import Foundation
import GameController
import Network
import Observation

/// The UI's side of the emulator: the picture to show and the buttons being held.
///
/// Everything here lives on the main actor, like the views that use it. The emulation itself
/// runs on the `Emulator` actor, and the two only exchange copies of values.
@MainActor
@Observable
final class GameBoyViewModel {
    /// The last completed frame, one pixel (red, green, blue and an unused byte) per element.
    private(set) var frame: [UInt32] = Array(repeating: blankPixel, count: displayBufferWidth * displayBufferHeight)

    /// Which buttons are held down. Changes are forwarded to the emulator.
    var joypad = JoypadState() {
        didSet {
            guard joypad != oldValue else { return }
            // The whole state is sent rather than the one button that changed, so the
            // emulator always ends up with what the UI shows
            Task { [emulator, joypad] in
                await emulator.setJoypad(joypad)
            }
        }
    }

    /// What the game controller held at the last look, to tell when it changes.
    private var controllerJoypad = JoypadState()

    /// Set while something other than the game has the controller's attention, such as a
    /// menu, so that finding one's way around it doesn't press buttons in the game.
    var ignoresController = false

    /// Goes up each time a shoulder button on the controller is pressed, which asks for
    /// the game's menu where there is one.
    private(set) var menuRequests = 0
    private var wasAskingForMenu = false
    private var wasAskingForFaster = false
    private var wasAskingForSlower = false

    /// Whether a game controller is connected. Looked for once a frame, like what it holds.
    private(set) var isGamepadConnected = false

    /// Takes over the buttons whenever the game controller's change. Until then, whatever
    /// the screen or the keyboard last set stands, so the three can be mixed.
    ///
    /// ponytail: looked at once a frame rather than on the controller's own events, which
    /// also covers one connecting or going away. A press shorter than a frame is missed.
    private func readController() {
        // The Apple TV remote also counts as a controller, but not as one with enough
        // buttons to play with
        let pad = GCController.current?.extendedGamepad ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
        if isGamepadConnected != (pad != nil) {
            isGamepadConnected = pad != nil
        }

        var held = JoypadState()
        if let pad, !ignoresController {
            held = JoypadState(pad)
            // A Game Boy has no shoulder buttons, so they are free to ask for the menu
            let isAskingForMenu = pad.leftShoulder.isPressed || pad.rightShoulder.isPressed
            if isAskingForMenu && !wasAskingForMenu {
                menuRequests += 1
            }
            wasAskingForMenu = isAskingForMenu

            // Nor has it an X or a Y, which step the speed up and down. They go by the
            // letters printed on them, which sit differently on an Xbox controller than on
            // a Nintendo one; without letters, the top button is faster and the left slower.
            let leftIsLabelledX = pad.buttonX.sfSymbolsName?.hasPrefix("x.") ?? false
            let isAskingForFaster = (leftIsLabelledX ? pad.buttonX : pad.buttonY).isPressed
            let isAskingForSlower = (leftIsLabelledX ? pad.buttonY : pad.buttonX).isPressed
            if linkState == .unplugged {
                if isAskingForFaster && !wasAskingForFaster {
                    speed = min(speed + 1, Self.speeds.upperBound)
                }
                if isAskingForSlower && !wasAskingForSlower {
                    speed = max(speed - 1, Self.speeds.lowerBound)
                }
            }
            wasAskingForFaster = isAskingForFaster
            wasAskingForSlower = isAskingForSlower
        }
        if held != controllerJoypad {
            controllerJoypad = held
            joypad = held
        }
    }

    /// Whether the sound is switched off. Changes are forwarded to the emulator.
    var isMuted = false {
        didSet {
            guard isMuted != oldValue else { return }
            Task { [emulator, isMuted] in
                await emulator.setMuted(isMuted)
            }
        }
    }

    /// How many times faster than a real Game Boy the player wants the game to run.
    var speed = 1 {
        didSet {
            sendSpeed()
        }
    }

    static let speeds = 1...4

    /// The speed the game runs at. With a link cable in, or on its way in, that is always
    /// the real one: two consoles only understand each other while they keep the same time.
    var effectiveSpeed: Int {
        linkState == .unplugged ? speed : 1
    }

    /// Moves on to the next speed, and from the fastest back to the real one.
    func cycleSpeed() {
        speed = speed == Self.speeds.upperBound ? Self.speeds.lowerBound : speed + 1
    }

    private func sendSpeed() {
        Task { [emulator, effectiveSpeed] in
            await emulator.setSpeed(effectiveSpeed)
        }
    }

    private let emulator = Emulator()

    /// The problem to tell the player about, if any. Set back to `nil` once it has been shown.
    var error: GameBoyError?

    /// Whether the game stopped because of an error it can't continue from.
    private(set) var hasFailed = false

    // MARK: - Link cable

    enum LinkState: Equatable {
        case unplugged
        /// Advertising this device and waiting for another one to join.
        case hosting
        /// Connecting to a host.
        case joining
        case linked
    }

    private(set) var linkState = LinkState.unplugged {
        didSet {
            sendSpeed()
        }
    }
    /// The hosts found while browsing.
    private(set) var nearbyHosts: [Bonjour.Endpoint] = []
    /// Why hosting or browsing is getting nowhere, if the system has said so.
    private(set) var linkProblem: String?

    private var linkTask: Task<Void, Never>?
    private var browseTask: Task<Void, Never>?

    /// Makes this device visible to others under `name`, and links with the first to join.
    func hostLink(as name: String) {
        unplugLink()
        linkState = .hosting
        linkTask = Task { [weak self, emulator] in
            do {
                try await NetworkLink.host(name: name, emulator: emulator) { isLinked in
                    Task { @MainActor in
                        self?.hostLinkChanged(isLinked)
                    }
                } onWaiting: { error in
                    Task { @MainActor in
                        self?.linkProblem = error.localizedDescription
                    }
                }
                self?.linkEnded(nil)
            } catch {
                self?.linkEnded(error)
            }
        }
    }

    /// Starts keeping `nearbyHosts` up to date.
    func startBrowsing() {
        stopBrowsing()
        browseTask = Task { [weak self] in
            try? await NetworkLink.browse { hosts in
                await MainActor.run {
                    self?.nearbyHosts = hosts
                }
            } onWaiting: { error in
                Task { @MainActor in
                    self?.linkProblem = error.localizedDescription
                }
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
        nearbyHosts = []
    }

    func joinLink(_ host: Bonjour.Endpoint) {
        unplugLink()
        stopBrowsing() // Browsing on would slow the connection down
        linkState = .joining
        linkTask = Task { [weak self, emulator] in
            do {
                try await NetworkLink.join(host, emulator: emulator) {
                    Task { @MainActor in
                        if self?.linkState == .joining {
                            self?.linkState = .linked
                        }
                    }
                }
                self?.linkEnded(nil)
            } catch {
                self?.linkEnded(error)
            }
        }
    }

    /// Ends the link, or the attempt to set one up.
    func unplugLink() {
        linkTask?.cancel()
        linkTask = nil
        linkState = .unplugged
        linkProblem = nil
    }

    private func hostLinkChanged(_ isLinked: Bool) {
        if isLinked, linkState == .hosting {
            linkState = .linked
        } else if !isLinked, linkState == .linked {
            // The other console has gone, and a host only ever takes one
            unplugLink()
            error = .linkLost
        }
    }

    /// Called when the link's task finishes by itself.
    private func linkEnded(_ error: (any Error)?) {
        guard !Task.isCancelled else {
            return // Unplugged from this end, which has dealt with it
        }
        let wasLinked = linkState == .linked
        unplugLink()
        self.error = wasLinked ? .linkLost : .linkFailed(reason: error?.localizedDescription ?? "")
    }

    // MARK: - Running

    /// Runs a game, updating `frame` as frames arrive, until the calling task is cancelled.
    /// Anything that goes wrong ends up in `error` rather than being thrown, because this is
    /// where errors turn into something the player sees.
    ///
    /// The first call starts the game. Later calls on the same model carry on from where the
    /// previous one was cancelled, because the emulator keeps the machine's state in memory.
    func run(_ game: Game) async {
        joypad = JoypadState() // Nothing is held when coming (back) to the game

        do {
            let rom: Data
            do {
                rom = try Data(contentsOf: game.romURL)
            } catch {
                throw GameBoyError.romNotReadable(name: game.title, reason: error.localizedDescription)
            }

            let frames = emulator.run(rom: rom, saveURL: game.saveURL) { [weak self] warning in
                Task { @MainActor in
                    self?.error = warning
                }
            }
            for try await frame in frames {
                self.frame = frame
                readController()
            }
        } catch let error as GameBoyError {
            self.error = error
            hasFailed = true
        } catch {
            self.error = .unexpected(reason: error.localizedDescription)
            hasFailed = true
        }
    }
}

/// The games that have been started since the app launched.
///
/// Leaving a game doesn't end it: its model, and with it the emulator and the entire state of
/// the machine, stays here, frozen, until the player comes back. Nothing is written to disk
/// for this, so it lasts only as long as the app does. After that, the game's own save data
/// is what remains.
@MainActor
@Observable
final class GameSessions {
    private var models: [Game.ID: GameBoyViewModel] = [:]

    /// The model of a game's session, starting a new one if there is none.
    func model(for game: Game) -> GameBoyViewModel {
        if let model = models[game.id] {
            return model
        }
        let model = GameBoyViewModel()
        models[game.id] = model
        return model
    }

    /// Whether a game has been started and can be carried on from where it was left.
    func isInProgress(_ game: Game) -> Bool {
        models[game.id].map { !$0.hasFailed } ?? false
    }

    /// Forgets a game's session, so that it starts from the beginning next time.
    func end(_ game: Game) {
        models[game.id] = nil
    }

    /// Forgets a game's session if it stopped with an error, since it can't be continued.
    func endIfFailed(_ game: Game) {
        if models[game.id]?.hasFailed == true {
            end(game)
        }
    }
}
