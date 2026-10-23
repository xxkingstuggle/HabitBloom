import SwiftUI

struct DayNoteEditorView: View {
    let day: Date
    let habitName: String
    let initialNote: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(day: Date, habitName: String, initialNote: String, onSave: @escaping (String) -> Void) {
        self.day = day
        self.habitName = habitName
        self.initialNote = initialNote
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                } header: {
                    Text("\(habitName) · \(day.formatted(date: .complete, time: .omitted))")
                } footer: {
                    Text("备注只保存在本地与云端文字备份里，不上传图片。")
                }
            }
            .navigationTitle("当日备注")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
        }
    }
}
