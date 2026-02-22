import SwiftUI

@main
struct PulseinatorApp: App {
    @State private var data = DataProvider()
    @State private var signoz = SigNozClient()

    var body: some Scene {
        MenuBarExtra("Ψ", systemImage: "waveform.path.ecg") {
            DashboardView()
        }
        .menuBarExtraStyle(.window)
    }
}
