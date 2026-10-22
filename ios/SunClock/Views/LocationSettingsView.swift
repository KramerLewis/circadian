import CoreLocation
import SunCore
import SwiftUI

/// Choose between the device location and a saved manual location.
struct LocationSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var useManual = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Location", selection: $useManual) {
                        Text("Current").tag(false)
                        Text("Manual").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("The manual location is also used whenever your current location isn't available.")
                }

                Section("Current location") {
                    currentLocationRow
                }

                Section {
                    TextField("Name", text: $name)
                    TextField("Latitude (e.g. 47.61)", text: $latitude)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude (e.g. -122.33)", text: $longitude)
                        .keyboardType(.numbersAndPunctuation)
                    if let live = locationService.location {
                        Button("Fill In Current Coordinates") {
                            latitude = String(format: "%.4f", live.coordinate.latitude)
                            longitude = String(format: "%.4f", live.coordinate.longitude)
                        }
                    }
                } header: {
                    Text("Manual location")
                } footer: {
                    if !manualFieldsAreEmpty && parsedCoordinate == nil {
                        Text("Latitude must be between -90 and 90, longitude between -180 and 180. Use negative numbers for south and west.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var currentLocationRow: some View {
        if locationService.isDenied {
            Text("Location access is off for SunClock.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } else if !locationService.isAuthorized {
            Button("Allow Location Access") { locationService.requestAccess() }
        } else if let live = locationService.location {
            let c = live.coordinate
            Text(Coordinate(latitude: c.latitude, longitude: c.longitude).formatted)
        } else {
            Text("Finding your location…").foregroundStyle(.secondary)
        }
    }

    private var manualFieldsAreEmpty: Bool {
        latitude.trimmingCharacters(in: .whitespaces).isEmpty && longitude.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parsedCoordinate: Coordinate? {
        guard
            let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
            let lon = Double(longitude.trimmingCharacters(in: .whitespaces)),
            (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    private var canSave: Bool {
        if manualFieldsAreEmpty { return !useManual }
        return parsedCoordinate != nil
    }

    private func load() {
        useManual = settings.useManualLocation
        name = settings.manualName
        latitude = settings.manualLatitude.map { String($0) } ?? ""
        longitude = settings.manualLongitude.map { String($0) } ?? ""
    }

    private func save() {
        settings.useManualLocation = useManual
        settings.manualName = name.trimmingCharacters(in: .whitespaces)
        let coordinate = parsedCoordinate
        settings.manualLatitude = coordinate?.latitude
        settings.manualLongitude = coordinate?.longitude
        settings.updatedAt = .now
        dismiss()
    }
}
