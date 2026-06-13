import Foundation
import SwiftData

enum HabitModelContainer {
    private static let appGroupIdentifier = "group.com.zjx.HabitBloom"

    static let shared: ModelContainer = {
        let schema = Schema([
            HabitEntity.self,
            CheckInEntity.self
        ])

        let configuration: ModelConfiguration
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil {
            configuration = ModelConfiguration(
                "HabitBloom",
                schema: schema,
                groupContainer: .identifier(appGroupIdentifier)
            )
        } else {
            configuration = ModelConfiguration("HabitBloom", schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create HabitBloom model container: \(error)")
        }
    }()
}
