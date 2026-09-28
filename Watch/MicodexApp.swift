import SwiftUI
import WatchKit
import MicodexCore

@main
struct MicodexApp: App {
    @StateObject private var connection = WatchLink()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(connection: connection)
                .onChange(of: scenePhase) { connection.setActive($0 == .active) }
        }
    }
}

private struct ContentView: View {
    @ObservedObject var connection: WatchLink
    @State private var showingConnection = false
    var body: some View {
        Group {
            if connection.connected && !showingConnection {
                RemoteView(connection: connection, showingConnection: $showingConnection)
            } else {
                ConnectionView(connection: connection, showingConnection: $showingConnection)
            }
        }.tint(MicodexStyle.accent)
    }
}
