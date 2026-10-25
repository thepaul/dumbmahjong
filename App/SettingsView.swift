import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.showTimer) private var showTimer = false
    @AppStorage(SettingsKey.dimBlocked) private var dimBlocked = false
    @AppStorage(SettingsKey.tableColor) private var tableColor = TableColor.felt
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sidewaysInPortrait) private var sidewaysInPortrait = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Timer", isOn: $showTimer)
                    Toggle("Dim Blocked Tiles", isOn: $dimBlocked)
                } footer: {
                    Text("Dimming blocked tiles makes the free ones easier to spot.")
                }
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Section {
                        Toggle("Turn Board Sideways in Portrait", isOn: $sidewaysInPortrait)
                    } footer: {
                        Text("Tiles are much bigger, but the faces read sideways unless you turn the phone.")
                    }
                }
                Section("Table") {
                    Picker("Table Color", selection: $tableColor) {
                        ForEach(TableColor.allCases) { table in
                            Label {
                                Text(table.name)
                            } icon: {
                                Circle().fill(table.color).frame(width: 22, height: 22)
                            }
                            .tag(table)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Haptics", isOn: $haptics)
                } footer: {
                    Text("A light tap when a pair is removed.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
