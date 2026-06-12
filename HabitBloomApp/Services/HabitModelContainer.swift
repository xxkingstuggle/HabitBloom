import SwiftData

enum HabitModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            HabitEntity.self,
            CheckInEntity.self
        ])

        let configuration = ModelConfiguration(
            "HabitBloom",
            schema: schema,
            groupContainer: .identifier("group.com.zjx.HabitBloom")
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create HabitBloom model container: \(error)")
        }
    }()
}
