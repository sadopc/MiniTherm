import SwiftUI

@main
struct CoreTempApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(monitor)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "thermometer.medium")
                Text(monitor.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
