import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    var closeAction: (() -> Void)?

    @State private var mode = IconPickerMode.emoji
    @State private var query = ""
    @State private var customIcon = ""
    @State private var selectedCategoryID: String?

    private let mobileColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    init(selection: Binding<String>, closeAction: (() -> Void)? = nil) {
        _selection = selection
        self.closeAction = closeAction
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("图标类型", selection: $mode) {
                    ForEach(IconPickerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                #if targetEnvironment(macCatalyst)
                desktopContent
                #else
                mobileContent
                #endif
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索图标、中文、英文名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: close)
                }
            }
            .onAppear(perform: selectFirstCategoryIfNeeded)
            .onChange(of: mode) {
                query = ""
                customIcon = ""
                selectedCategoryID = categories.first?.id
            }
        }
    }

    private var mobileContent: some View {
        List {
            customInputSection
                .iconPickerListRow()

            if visibleCategories.isEmpty {
                emptySearchView
                    .iconPickerListRow()
            } else {
                ForEach(visibleCategories) { category in
                    IconCategorySection(
                        category: category,
                        selection: selection,
                        columns: mobileColumns,
                        choose: choose
                    )
                    .iconPickerListRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.visible)
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    #if targetEnvironment(macCatalyst)
    private var desktopContent: some View {
        VStack(spacing: 0) {
            customInputSection
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            Divider()

            HStack(spacing: 0) {
                categorySidebar
                    .frame(width: 176)

                Divider()

                List {
                    Section {
                        ForEach(desktopCandidates) { candidate in
                            desktopCandidateRow(candidate)
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(desktopSectionTitle)
                            Spacer()
                            Text("\(desktopCandidates.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if desktopCandidates.isEmpty {
                        emptySearchView
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.visible)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var categorySidebar: some View {
        List(categories) { category in
            Button {
                query = ""
                selectedCategoryID = category.id
            } label: {
                HStack {
                    Text(category.title)
                        .lineLimit(1)
                    Spacer()
                    Text("\(category.candidates.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedCategoryID == category.id && query.isEmpty
                    ? Color.accentColor.opacity(0.16)
                    : Color.clear
            )
        }
        .listStyle(.plain)
        .scrollIndicators(.visible)
    }

    private func desktopCandidateRow(_ candidate: IconCandidate) -> some View {
        Button {
            choose(candidate.value)
        } label: {
            HStack(spacing: 14) {
                HabitIconGlyph(icon: candidate.value, size: candidate.value.isEmojiIcon ? 30 : 23)
                    .foregroundStyle(selection == candidate.value ? Color.accentColor : .primary)
                    .frame(width: 42, height: 42)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.body.weight(.medium))
                    if candidate.mode == .symbol {
                        Text(candidate.value)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selection == candidate.value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.name)
    }

    private var desktopCandidates: [IconCandidate] {
        if !normalizedQuery.isEmpty {
            return categories.flatMap(\.candidates).filter { $0.matches(query) }
        }

        return categories.first(where: { $0.id == selectedCategoryID })?.candidates
            ?? categories.first?.candidates
            ?? []
    }

    private var desktopSectionTitle: String {
        if !normalizedQuery.isEmpty { return "搜索结果" }
        return categories.first(where: { $0.id == selectedCategoryID })?.title
            ?? categories.first?.title
            ?? mode.title
    }
    #endif

    private var categories: [IconCategory] {
        IconCatalog.categories(for: mode)
    }

    private var visibleCategories: [IconCategory] {
        categories.compactMap { category in
            let candidates = category.candidates.filter { $0.matches(query) }
            guard !candidates.isEmpty else { return nil }
            return IconCategory(title: category.title, mode: category.mode, candidates: candidates)
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptySearchView: some View {
        ContentUnavailableView(
            "没有找到图标",
            systemImage: "magnifyingglass",
            description: Text("换个关键词，或者使用上面的自定义输入。")
        )
        .padding(.top, 32)
    }

    private var trimmedCustomIcon: String {
        customIcon.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customValidationMessage: String? {
        guard !trimmedCustomIcon.isEmpty else { return nil }

        switch mode {
        case .emoji:
            return trimmedCustomIcon.isEmojiIcon ? nil : "请输入一个表情，例如 📚 或 🏃。"
        case .symbol:
            return isRenderableSystemSymbol(trimmedCustomIcon) ? nil : "这个 SF Symbol 名称不可用。"
        }
    }

    private var canUseCustomIcon: Bool {
        !trimmedCustomIcon.isEmpty && customValidationMessage == nil
    }

    private var customInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义")
                .font(.headline.weight(.bold))

            HStack(spacing: 10) {
                TextField(mode.customPlaceholder, text: $customIcon)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    choose(trimmedCustomIcon)
                } label: {
                    Label("使用", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canUseCustomIcon)
            }

            HStack(spacing: 8) {
                if !trimmedCustomIcon.isEmpty {
                    HabitIconGlyph(icon: trimmedCustomIcon, size: trimmedCustomIcon.isEmojiIcon ? 28 : 22)
                        .foregroundStyle(canUseCustomIcon ? .primary : .secondary)
                        .frame(width: 38, height: 38)
                        .background(Color.secondary.opacity(0.10), in: Circle())
                }

                Text(customValidationMessage ?? helperText)
                    .font(.footnote)
                    .foregroundStyle(customValidationMessage == nil ? Color.secondary : Color.red)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var helperText: String {
        switch mode {
        case .emoji: "可以直接粘贴 iPhone 自带表情。"
        case .symbol: "可输入 Apple SF Symbols 名称，例如 book.closed.fill。"
        }
    }

    private func selectFirstCategoryIfNeeded() {
        guard categories.contains(where: { $0.id == selectedCategoryID }) else {
            selectedCategoryID = categories.first?.id
            return
        }
    }

    private func choose(_ icon: String) {
        selection = icon
        close()
    }

    private func close() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }
}

private extension View {
    func iconPickerListRow() -> some View {
        listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct IconCategorySection: View {
    let category: IconCategory
    let selection: String
    let columns: [GridItem]
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(.headline.weight(.bold))
                Text("\(category.candidates.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            IconCandidateGrid(
                candidates: category.candidates,
                selection: selection,
                columns: columns,
                choose: choose
            )
        }
    }
}

private struct IconCandidateGrid: View {
    let candidates: [IconCandidate]
    let selection: String
    let columns: [GridItem]
    let choose: (String) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(candidates) { candidate in
                Button {
                    choose(candidate.value)
                } label: {
                    VStack(spacing: 5) {
                        HabitIconGlyph(icon: candidate.value, size: candidate.value.isEmojiIcon ? 28 : 22)
                            .foregroundStyle(selection == candidate.value ? Color.accentColor : .primary)
                            .frame(height: 29)
                        Text(candidate.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(selection == candidate.value ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selection == candidate.value ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.name)
            }
        }
    }
}

private func isRenderableSystemSymbol(_ name: String) -> Bool {
    #if canImport(UIKit)
    return UIImage(systemName: name) != nil
    #else
    return !name.isEmpty
    #endif
}
