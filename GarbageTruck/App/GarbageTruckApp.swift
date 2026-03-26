import SwiftUI

@main
struct GarbageTruckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    private let presentationCoordinator = AppPresentationCoordinator()

    var body: some Scene {
        Window("Garbage Truck", id: "main") {
            MainView(presentationCoordinator: presentationCoordinator)
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

        Settings {
            SettingsView()
                .environment(appState)
        }

    }
}
