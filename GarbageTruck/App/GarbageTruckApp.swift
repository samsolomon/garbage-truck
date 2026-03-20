import SwiftUI

@main
struct GarbageTruckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Delete") {
                    appState.undoLastDeletion()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(appState.deletionHistory.isEmpty)
            }
        }
    }
}
