import Foundation
import HabitCore
import HabitWidgetShared

let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return value
}()

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("Smoke test failed: \(message)")
    }
}

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
        fatalError("Invalid date")
    }
    return value
}

func timestamp(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    let components = DateComponents(
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    )
    guard let value = calendar.date(from: components) else {
        fatalError("Invalid timestamp")
    }
    return value
}

let dailyHabit = Habit(name: "阅读", targetWeekdays: Set(1...7))
let today = date(2026, 6, 11)
let dailyCheckIns = [
    CheckIn(habitID: dailyHabit.id, day: today),
    CheckIn(habitID: dailyHabit.id, day: date(2026, 6, 10)),
    CheckIn(habitID: dailyHabit.id, day: date(2026, 6, 9))
]
let calculator = HabitStatsCalculator(calendar: calendar)
let dailyStats = calculator.stats(for: dailyHabit, checkIns: dailyCheckIns, today: today)
require(dailyStats.currentStreak == 3, "daily streak should be 3")
require(dailyStats.totalCompletedDays == 3, "total completed days should be 3")

let pendingStats = calculator.stats(for: dailyHabit, checkIns: dailyCheckIns, today: date(2026, 6, 12))
require(pendingStats.currentStreak == 3, "streak must survive an unchecked today")
require(pendingStats.totalCompletedDays == 3, "unchecked today must not change total days")

let weekendHabit = Habit(name: "周末", targetWeekdays: [1, 7])
let weekendCheckIns = [CheckIn(habitID: weekendHabit.id, day: date(2026, 6, 7))]
let weekendStats = calculator.stats(for: weekendHabit, checkIns: weekendCheckIns, today: date(2026, 6, 8))
require(weekendStats.currentStreak == 1, "streak on non-target day must keep counting prior target days")

let weekdayHabit = Habit(name: "运动", targetWeekdays: Set(2...6))
let weekdayCheckIns = [
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 6, 8)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 6, 5)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 5, 29)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 5, 28)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 5, 27)),
    CheckIn(habitID: weekdayHabit.id, day: date(2026, 5, 26))
]
let weekdayStats = calculator.stats(for: weekdayHabit, checkIns: weekdayCheckIns, today: date(2026, 6, 8))
require(weekdayStats.currentStreak == 2, "weekday streak should skip weekend")
require(calculator.bestStreak(for: weekdayHabit, checkIns: weekdayCheckIns) == 4, "bestStreak should find historical longest run")

let mayRate = calculator.monthCompletionRate(for: weekdayHabit, checkIns: weekdayCheckIns, in: date(2026, 5, 1))
let juneRate = calculator.monthCompletionRate(for: weekdayHabit, checkIns: weekdayCheckIns, in: date(2026, 6, 1))
require(mayRate > juneRate && mayRate > 0.15, "selected month completion rate should track the requested month")

let reminderHabit = Habit(
    name: "喝水",
    reminder: ReminderRule(isEnabled: true, hour: 19, minute: 30, activeWeekdays: [2, 4, 6])
)
let requests = ReminderPlanner().requests(for: reminderHabit)
require(requests.count == 3, "reminder count should match active weekdays")
require(requests.map(\.weekday) == [2, 4, 6], "reminder weekdays should be sorted")

let fractionalDate = WidgetJSONCodec.parseISO8601("2026-11-25T10:20:30.456Z")
let wholeSecondDate = WidgetJSONCodec.parseISO8601("2026-11-25T10:20:30Z")
require(fractionalDate != nil, "ISO-8601 parser must decode fractional seconds")
require(wholeSecondDate != nil, "ISO-8601 parser must decode whole seconds")
require(abs((fractionalDate?.timeIntervalSince1970 ?? 0) - (wholeSecondDate?.timeIntervalSince1970 ?? 0) - 0.456) < 0.002, "fractional delta should match")

let habitOneID = UUID()
let habitTwoID = UUID()
let mixedTimestampJSON = """
{
  "deviceKey": "device-test-1234",
  "updatedAt": "2026-11-25T08:00:00.250Z",
  "dayKey": "2026-11-25",
  "selectedHabitID": "\(habitOneID.uuidString)",
  "habits": [
    {
      "id": "\(habitOneID.uuidString)",
      "name": "晨跑",
      "icon": "figure.run",
      "colorName": "mint",
      "cardStyle": "soft",
      "streakDays": 5,
      "totalDays": 20,
      "completionRate": 0.75,
      "isCompletedToday": true,
      "imageFileName": null,
      "imageData": null,
      "updatedAt": "2026-11-25T08:00:00Z"
    }
  ]
}
"""
let decodedSnapshot = try WidgetJSONCodec.makeDecoder().decode(WidgetRemoteSnapshot.self, from: Data(mixedTimestampJSON.utf8))
require(decodedSnapshot.habits.count == 1 && decodedSnapshot.habits[0].isCompletedToday, "mixed ISO-8601 snapshot should decode cleanly")

let nextMorning = timestamp(2026, 11, 26, 7, 30, 0)
require(!WidgetSnapshotRollover.isSameDay(snapshot: decodedSnapshot, referenceDate: nextMorning, calendar: calendar), "previous-day snapshot must not match today")
let rolledOverSnapshot = WidgetSnapshotRollover.rolledOver(decodedSnapshot, referenceDate: nextMorning, calendar: calendar)
require(rolledOverSnapshot.dayKey == "2026-11-26", "rolled over snapshot should carry today's dayKey")
require(rolledOverSnapshot.habits[0].isCompletedToday == false, "rolled over snapshot must reset isCompletedToday")
require(rolledOverSnapshot.habits[0].streakDays == 5, "rolled over snapshot must preserve streakDays")

let pendingTodayItem = PendingWidgetCheckIn(
    habitID: habitOneID,
    isCompletedToday: true,
    day: timestamp(2026, 11, 26, 8, 0, 0),
    updatedAt: timestamp(2026, 11, 26, 8, 5, 0)
)
let pendingYesterdayItem = PendingWidgetCheckIn(
    habitID: habitOneID,
    isCompletedToday: false,
    day: timestamp(2026, 11, 25, 22, 0, 0),
    updatedAt: timestamp(2026, 11, 25, 22, 0, 0)
)
let overlaidSnapshot = WidgetSnapshotRollover.overlayPendingCheckIns(
    decodedSnapshot,
    pending: [pendingYesterdayItem, pendingTodayItem],
    referenceDate: nextMorning,
    calendar: calendar
)
require(overlaidSnapshot.habits[0].isCompletedToday == true, "overlayPendingCheckIns should apply today's pending check-in after rollover")

let arbitrationDay = timestamp(2026, 11, 26, 12, 0, 0)
let localNewerPending = PendingWidgetCheckIn(
    habitID: habitOneID,
    isCompletedToday: false,
    day: arbitrationDay,
    updatedAt: timestamp(2026, 11, 26, 10, 30, 0)
)
let localOlderPending = PendingWidgetCheckIn(
    habitID: habitTwoID,
    isCompletedToday: false,
    day: arbitrationDay,
    updatedAt: timestamp(2026, 11, 26, 9, 0, 0)
)
let remoteSameDay = WidgetRemoteSnapshot(
    deviceKey: "device-test-1234",
    updatedAt: timestamp(2026, 11, 26, 11, 0, 0),
    dayKey: "2026-11-26",
    selectedHabitID: habitOneID,
    habits: [
        WidgetHabitSnapshot(
            id: habitOneID,
            name: "晨跑",
            icon: "figure.run",
            colorName: "mint",
            cardStyle: "soft",
            streakDays: 5,
            totalDays: 20,
            completionRate: 0.75,
            isCompletedToday: true,
            updatedAt: timestamp(2026, 11, 26, 9, 45, 0)
        ),
        WidgetHabitSnapshot(
            id: habitTwoID,
            name: "阅读",
            icon: "book.fill",
            colorName: "indigo",
            cardStyle: "glass",
            streakDays: 2,
            totalDays: 10,
            completionRate: 0.5,
            isCompletedToday: true,
            updatedAt: timestamp(2026, 11, 26, 10, 45, 0)
        )
    ]
)
let reconciled = WidgetCheckInReconciler.reconcile(
    localPending: [localNewerPending, localOlderPending],
    remoteSnapshot: remoteSameDay,
    existingTodayStateByHabitID: [:],
    referenceDate: arbitrationDay,
    calendar: calendar
)
let resolvedByHabit = Dictionary(uniqueKeysWithValues: reconciled.map { ($0.habitID, $0) })
require(resolvedByHabit[habitOneID]?.source == .localQueue && resolvedByHabit[habitOneID]?.isCompleted == false, "newer local queue entry must win over older remote habit")
require(resolvedByHabit[habitTwoID]?.source == .remoteSnapshot && resolvedByHabit[habitTwoID]?.isCompleted == true, "newer remote habit entry must win over older local queue")

let staleOnlyReconciled = WidgetCheckInReconciler.reconcile(
    localPending: [],
    remoteSnapshot: decodedSnapshot,
    existingTodayStateByHabitID: [:],
    referenceDate: arbitrationDay,
    calendar: calendar
)
require(staleOnlyReconciled.isEmpty, "previous-day remote snapshot must be ignored during reconciliation")

let appNewerReconciled = WidgetCheckInReconciler.reconcile(
    localPending: [localOlderPending],
    remoteSnapshot: remoteSameDay,
    existingTodayStateByHabitID: [
        habitTwoID: LocalTodayCheckInState(isCompleted: false, updatedAt: timestamp(2026, 11, 26, 11, 30, 0))
    ],
    referenceDate: arbitrationDay,
    calendar: calendar
)
require(appNewerReconciled.contains(where: { $0.habitID == habitTwoID }) == false, "newer local app state must not be overwritten by older widget state")

let untouchedHabitID = UUID()
let untouchedHabitRemoteSnapshot = WidgetRemoteSnapshot(
    deviceKey: "device-test-1234",
    updatedAt: timestamp(2026, 11, 26, 11, 15, 0),
    dayKey: "2026-11-26",
    selectedHabitID: untouchedHabitID,
    habits: [
        WidgetHabitSnapshot(
            id: untouchedHabitID,
            name: "站立拉伸",
            icon: "figure.cooldown",
            colorName: "teal",
            cardStyle: "soft",
            streakDays: 3,
            totalDays: 12,
            completionRate: 0.6,
            isCompletedToday: true,
            updatedAt: timestamp(2026, 11, 26, 10, 50, 0)
        )
    ]
)
let untouchedHabitReconciled = WidgetCheckInReconciler.reconcile(
    localPending: [],
    remoteSnapshot: untouchedHabitRemoteSnapshot,
    existingTodayStateByHabitID: [
        untouchedHabitID: LocalTodayCheckInState(isCompleted: false, updatedAt: timestamp(2026, 11, 20, 8, 0, 0))
    ],
    referenceDate: arbitrationDay,
    calendar: calendar
)
require(
    untouchedHabitReconciled.first(where: { $0.habitID == untouchedHabitID })?.isCompleted == true
        && untouchedHabitReconciled.first(where: { $0.habitID == untouchedHabitID })?.source == .remoteSnapshot,
    "untouched habit with older updatedAt must not block newer remote widget check-in"
)

let existingHabit = RemoteBackupHabit(
    id: habitOneID,
    name: "晨跑",
    icon: "figure.run",
    colorName: "mint",
    cardStyle: "soft",
    targetWeekdayMask: 127,
    reminderEnabled: false,
    reminderHour: 20,
    reminderMinute: 0,
    reminderWeekdayMask: 127,
    sortOrder: 0,
    createdAt: date(2026, 1, 1),
    checkIns: [
        RemoteBackupCheckIn(day: date(2026, 11, 24), isCompleted: true, note: "本地备注", createdAt: timestamp(2026, 11, 24, 9, 0))
    ]
)
let importedArchive = RemoteBackupArchive(
    version: 1,
    deviceKey: "device-test-1234",
    exportedAt: timestamp(2026, 11, 25, 12, 0),
    habits: [
        RemoteBackupHabit(
            id: habitOneID,
            name: "晨跑 5km",
            icon: "figure.run",
            colorName: "teal",
            cardStyle: "soft",
            targetWeekdayMask: 127,
            reminderEnabled: true,
            reminderHour: 7,
            reminderMinute: 30,
            reminderWeekdayMask: 127,
            sortOrder: 0,
            createdAt: date(2026, 1, 1),
            checkIns: [
                RemoteBackupCheckIn(day: timestamp(2026, 11, 24, 8, 0), isCompleted: false, note: "旧同日记录", createdAt: timestamp(2026, 11, 24, 8, 0)),
                RemoteBackupCheckIn(day: timestamp(2026, 11, 24, 21, 0), isCompleted: false, note: "备份覆盖备注", createdAt: timestamp(2026, 11, 24, 21, 0)),
                RemoteBackupCheckIn(day: date(2026, 11, 25), isCompleted: true, note: "新增日", createdAt: timestamp(2026, 11, 25, 8, 0))
            ]
        ),
        RemoteBackupHabit(
            id: habitTwoID,
            name: "冥想",
            icon: "brain.head.profile",
            colorName: "indigo",
            cardStyle: "glass",
            targetWeekdayMask: 127,
            reminderEnabled: false,
            reminderHour: 21,
            reminderMinute: 0,
            reminderWeekdayMask: 127,
            sortOrder: 1,
            createdAt: date(2026, 11, 20),
            checkIns: [
                RemoteBackupCheckIn(day: date(2026, 11, 25), isCompleted: true, note: "", createdAt: timestamp(2026, 11, 25, 9, 0))
            ]
        )
    ]
)

let importPlan = BackupImportPlanner.makePlan(existingHabits: [existingHabit], importedArchive: importedArchive, calendar: calendar)
require(importPlan.newHabitCount == 1, "import plan should detect 1 new habit")
require(importPlan.updatedHabitCount == 1, "import plan should detect 1 updated habit")
require(importPlan.newCheckInCount == 2, "import plan should count 2 net new check-ins")
require(importPlan.deduplicatedImportedCheckInCount == 1, "import plan should collapse 1 duplicate same-day check-in")
require(importPlan.conflictCount == 1, "import plan should detect 1 same-day conflict")

let keepLocalMerged = BackupImportPlanner.merge(
    existingHabits: [existingHabit],
    importedArchive: importedArchive,
    strategy: .keepLocal,
    calendar: calendar
)
let keepLocalHabitOne = keepLocalMerged.first(where: { $0.id == habitOneID })
require(keepLocalHabitOne?.name == "晨跑", "keepLocal strategy must preserve local habit name")
require(keepLocalHabitOne?.checkIns.count == 2, "keepLocal strategy must merge missing day while keeping unique days")
require(keepLocalHabitOne?.checkIns.first(where: { calendar.isDate($0.day, inSameDayAs: date(2026, 11, 24)) })?.note == "本地备注", "keepLocal strategy must preserve local conflict record")

let overwriteMerged = BackupImportPlanner.merge(
    existingHabits: [existingHabit],
    importedArchive: importedArchive,
    strategy: .overwriteWithImported,
    calendar: calendar
)
let overwriteHabitOne = overwriteMerged.first(where: { $0.id == habitOneID })
require(overwriteHabitOne?.name == "晨跑 5km", "overwrite strategy must update habit metadata")
require(overwriteHabitOne?.checkIns.first(where: { calendar.isDate($0.day, inSameDayAs: date(2026, 11, 24)) })?.note == "备份覆盖备注", "overwrite strategy must apply deduplicated imported conflict record")

let fingerprintA = widgetImageFingerprint(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01]))
let fingerprintB = widgetImageFingerprint(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x02]))
require(fingerprintA.count == 16 && fingerprintA != fingerprintB, "image fingerprint should be 16 hex chars and sensitive to byte changes")

print("HabitCore and HabitWidgetShared smoke tests passed")
