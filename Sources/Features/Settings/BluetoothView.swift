import SwiftUI

/// Discover and connect to Bluetooth devices. Built for future NutriWear
/// hardware (a wearable camera/sensor); today it pairs with any nearby BLE
/// device so the flow is real.
struct BluetoothView: View {
    @EnvironmentObject var model: AppModel
    private var bt: BluetoothService { model.bluetooth }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                if let connected = bt.connectedDevice {
                    connectedCard(connected)
                }

                scanCard
                deviceList
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .nutriBackground()
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { bt.stopScan() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.carbs)
            Text("Connect a device")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pair your NutriWear wearable or another Bluetooth device. More NutriWear hardware is coming — this is where you'll connect it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func connectedCard(_ device: BluetoothDevice) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.positive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Connected")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.positive)
                }
                Spacer()
                Button { bt.disconnect() } label: {
                    Text("Disconnect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 8).padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
                }
            }
        }
    }

    private var scanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let msg = bt.statusMessage {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(bt.state == .ready || bt.isScanning ? Theme.textSecondary : Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    bt.isScanning ? bt.stopScan() : bt.startScan()
                } label: {
                    HStack(spacing: 8) {
                        if bt.isScanning { ProgressView().tint(.black) }
                        Text(bt.isScanning ? "Stop scanning" : "Scan for devices")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(bt.state == .unsupported || bt.state == .poweredOff || bt.state == .unauthorized)
            }
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        if !bt.devices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nearby")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(bt.devices) { device in
                    Button { bt.connect(device) } label: {
                        deviceRow(device)
                    }
                    .disabled(device.isConnected)
                }
            }
        }
    }

    private func deviceRow(_ device: BluetoothDevice) -> some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: signalIcon(device.rssi))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.carbs)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Signal \(device.rssi) dBm")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if device.isConnected {
                    Text("Connected").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.positive)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func signalIcon(_ rssi: Int) -> String {
        if rssi > -55 { return "wifi" }
        if rssi > -75 { return "wifi.exclamationmark" }
        return "wifi.slash"
    }
}
