import SwiftData
import SwiftUI
import WidgetKit

extension Notification.Name {
    static let habitBloomRequestNewHabit = Notification.Name("habitBloomRequestNewHabit")
    static let habitBloomSelectTab = Notification.Name("habitBloomSelectTab")
}

@main
struct HabitBloomApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme.colorScheme)
                .task {
                    let context = HabitModelContainer.shared.mainContext
                    await StartupSyncCoordinator.shared.ensureInitialSync(using: context)
                }
        }
        .modelContainer(HabitModelContainer.shared)
        #if os(macOS)
        .defaultSize(width: 1080, height: 760)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建目标") {
                    NotificationCenter.default.post(name: .habitBloomRequestNewHabit, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("视图") {
                Button("首页") {
                    NotificationCenter.default.post(name: .habitBloomSelectTab, object: 0)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("统计") {
                    NotificationCenter.default.post(name: .habitBloomSelectTab, object: 1)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("设置") {
                    NotificationCenter.default.post(name: .habitBloomSelectTab, object: 2)
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
