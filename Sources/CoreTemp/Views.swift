import CoreTempKit
import ServiceManagement
import SwiftUI

/// Green at 35 °C sliding to red at 95 °C.
func heatColor(_ t: Double?) -> Color {
    guard let t else { return .secondary }
    let f = min(max((t - 35) / 60, 0), 1)
    return Color(hue: 0.38 * (1 - f), saturation: 0.78, brightness: 0.82)
}

func degrees(_ t: Double?, unit: String = "") -> String { t.map { "\(Int($0.rounded()))°\(unit)" } ?? "—" }

struct PanelView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if monitor.supported {
                Header()
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        ClusterRow(cluster: .superCore)
                        ClusterRow(cluster: .performance)
                        ClusterRow(cluster: .efficiency)
                    }
                }
                HStack(spacing: 8) {
                    Stat(title: "CPU avg", symbol: "cpu", value: monitor.cpuAverage)
                    Stat(title: "GPU", symbol: "square.stack.3d.up", value: monitor.gpu)
                    Stat(title: "SSD", symbol: "internaldrive", value: monitor.ssd)
                }
                Card { FanSection() }
            } else {
                Text("CoreTemp only supports the Mac mini with M6 (Mac18,5).\nThis Mac is \(SensorMap.model).")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Footer()
        }
        .padding(14)
        .frame(width: 340)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Header: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac mini").font(.headline)
                    Text("Apple M6 · hottest core").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(degrees(monitor.hottest, unit: "C"))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(heatColor(monitor.hottest))
            }
            Sparkline(values: monitor.history, capacity: Monitor.historyCapacity, color: heatColor(monitor.hottest))
                .frame(height: 34)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let capacity: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = (values.min() ?? 30) - 3
            let hi = max((values.max() ?? 40) + 3, lo + 12)
            let points = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i + capacity - values.count) / CGFloat(capacity - 1),
                        y: geo.size.height * CGFloat(1 - (v - lo) / (hi - lo)))
            }
            if let first = points.first, let last = points.last {
                Path { p in
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct ClusterRow: View {
    @EnvironmentObject var monitor: Monitor
    let cluster: Cluster

    private var title: LocalizedStringKey {
        switch cluster {
        case .superCore: return "SUPER"
        case .performance: return "PERFORMANCE"
        case .efficiency: return "EFFICIENCY"
        }
    }

    var body: some View {
        let cores = monitor.cores.filter { $0.sensor.cluster == cluster }
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold)).kerning(0.6).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(cores) { CoreTile(core: $0) }
            }
        }
    }
}

struct CoreTile: View {
    let core: CoreReading

    private var tooltip: LocalizedStringKey {
        let load = "\(Int((core.usage * 100).rounded()))%"
        return core.sensor.estimated
            ? "cpu\(core.sensor.cpu) · \(load) load · no dedicated sensor, efficiency-cluster average"
            : "cpu\(core.sensor.cpu) · \(load) load · \(core.sensor.keys.joined(separator: ", "))"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(core.sensor.label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Text((core.sensor.estimated ? "≈" : "") + degrees(core.temperature))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heatColor(core.temperature))
                .lineLimit(1).minimumScaleFactor(0.7)
            Bar(fraction: core.usage, color: .secondary).frame(height: 3)
        }
        .padding(.horizontal, 5).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(tooltip)
    }
}

struct Bar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
    }
}

struct Stat: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
                Text(degrees(value, unit: "C"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(heatColor(value))
            }
        }
    }
}

struct FanSection: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        if let fan = monitor.fans.first {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Fan", systemImage: "fan").font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(Int(fan.actual.rounded())))
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("RPM").font(.caption).foregroundStyle(.secondary)
                }
                Bar(fraction: fan.actual / fan.max, color: .accentColor).frame(height: 5)

                if monitor.helperInstalled {
                    Picker("Mode", selection: $monitor.fanMode) {
                        ForEach(FanMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    switch monitor.fanMode {
                    case .auto:
                        EmptyView()
                    case .manual:
                        LabeledSlider(title: "Speed", value: $monitor.manualRPM, range: fan.min...fan.max,
                                      text: "\(Int(monitor.manualRPM))")
                    case .curve:
                        LabeledSlider(title: "Ramp from", value: $monitor.curveStart, range: 35...75,
                                      text: "\(Int(monitor.curveStart))°")
                        LabeledSlider(title: "Full speed", value: $monitor.curveEnd, range: 60...100,
                                      text: "\(Int(monitor.curveEnd))°")
                    }
                } else {
                    HStack {
                        Text("Changing fan speed needs a small root helper.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Enable…") { monitor.installHelper() }.controlSize(.small)
                    }
                    if let error = monitor.installError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        } else {
            Text("No fan found").foregroundStyle(.secondary)
        }
    }
}

struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let text: String

    var body: some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Slider(value: $value, in: range).controlSize(.small)
            Text(text).font(.caption).monospacedDigit().frame(width: 36, alignment: .trailing)
        }
    }
}

struct Footer: View {
    @EnvironmentObject var monitor: Monitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            Spacer()
            Button("Quit") {
                monitor.restoreAuto()
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}
