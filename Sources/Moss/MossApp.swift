import AppKit

@main
@MainActor
struct MossApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MossFonts.registerBundledFonts()
        MossTaskStore.shared.startRemindersSync()
        let controller = PetWindowController()
        petController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
