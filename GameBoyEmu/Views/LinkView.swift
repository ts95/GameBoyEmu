//
//  LinkView.swift
//  GameBoyEmu
//

import SwiftUI

/// The link cable's sheet: sets up a link with a nearby device, or unplugs the one there is.
///
/// One player hosts and the other joins. It doesn't matter to the games which is which.
struct LinkView: View {
    let model: GameBoyViewModel
    /// What this device is called in the other player's list when it hosts.
    let hostName: String

    @Environment(\.dismiss) private var dismiss
    @State private var isBrowsing = false

    var body: some View {
        NavigationStack {
            List {
                switch model.linkState {
                case .unplugged where isBrowsing:
                    nearbyHosts
                case .unplugged:
                    choices
                case .hosting:
                    progress("Waiting for another player to join…", cancelTitle: "Stop Hosting")
                case .joining:
                    progress("Connecting…", cancelTitle: "Cancel")
                case .linked:
                    linked
                }
            }
            .navigationTitle("Link Cable")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        #if os(iOS)
        // Opaque: a half-height sheet is glass by default, and the game shows through it
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        #endif
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
        .onChange(of: model.linkState) { _, state in
            if state == .linked {
                dismiss() // Back to the game
            }
        }
        .onDisappear {
            // Hosting carries on behind the sheet, but browsing has no one to show its list to
            model.stopBrowsing()
        }
    }

    var choices: some View {
        Section {
            Button("Host", systemImage: "antenna.radiowaves.left.and.right") {
                model.hostLink(as: hostName)
            }
            Button("Join", systemImage: "magnifyingglass") {
                isBrowsing = true
                model.startBrowsing()
            }
        } footer: {
            Text("Link with a nearby device to trade or battle. One player hosts and the other joins. Both need to be in a game.")
        }
    }

    var nearbyHosts: some View {
        Section {
            ForEach(model.nearbyHosts) { host in
                Button(host.name) {
                    model.joinLink(host)
                }
            }
            if model.nearbyHosts.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for hosts…")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Cancel", role: .cancel) {
                isBrowsing = false
                model.stopBrowsing()
            }
        } header: {
            Text("Nearby")
        } footer: {
            problem
        }
    }

    func progress(_ title: LocalizedStringKey, cancelTitle: LocalizedStringKey) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(title)
            }
            Button(cancelTitle, role: .destructive) {
                model.unplugLink()
            }
        } footer: {
            problem
        }
    }

    var linked: some View {
        Section {
            Label("Linked", systemImage: "cable.connector")
            Button("Unplug", role: .destructive) {
                model.unplugLink()
            }
        }
    }

    /// What the system says is in the way, if anything. Most often it is the app not being
    /// allowed to use the local network.
    @ViewBuilder
    var problem: some View {
        if let problem = model.linkProblem {
            Text("Other devices can't be reached. Check that Game Boy Emu is allowed under Local Network in Settings, and that Wi-Fi is on. (\(problem))")
        }
    }
}

// Nothing is hosting or joining here: the preview only shows the choices
#Preview {
    LinkView(model: GameBoyViewModel(), hostName: "Pokémon Red")
}
