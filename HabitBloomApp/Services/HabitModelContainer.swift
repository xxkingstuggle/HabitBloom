import Foundation
import SwiftData

enum HabitModelContainer {
    private static let appGroupIdentifier = WidgetSharedDefaults.appGroupIdentifier

    static let shared: ModelContainer = {
        let schema = Schema([
            HabitEntity.self,
            CheckInEntity.self
        ])

        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil {
            let groupConfiguration = ModelConfiguration(
                "HabitBloom",
                schema: schema,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .none
            )
            if let container = try? ModelContainer(for: schema, configurations: [groupConfiguration]) {
                return container
            }
            print("[HabitBloomModel] App Group ModelContainer unavailable; falling back to local Application Support store.")
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let storeDirectory = appSupport.appendingPathComponent("HabitBloom", isDirectory: true)
            try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let storeURL = storeDirectory.appendingPathComponent("HabitBloom.store")
            let localConfiguration = ModelConfiguration(
                "HabitBloomLocal",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
                return container
            }
            print("[HabitBloomModel] Local Application Support ModelContainer unavailable; falling back to in-memory store.")
        }

        do {
            let memoryConfiguration = ModelConfiguration(
                "HabitBloomMemory",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            fatalError("Unable to create HabitBloom model container: \(error)")
        }
    }()
}
