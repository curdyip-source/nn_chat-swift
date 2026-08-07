//
//  TodoBoardView.swift
//  NufNaf Chat
//
//  Экран «Задачи» — менеджер задач в духе Things, адаптированный под телефон:
//  боковая панель разделов превращена в горизонтальную ленту чипсов над списком
//  (смарт-списки, затем пользовательские), карточка задачи раскрывается прямо в
//  списке, порядок меняется удержанием и перетаскиванием.
//

import SwiftUI

struct TodoBoardView: View {
    /// Пока лента разделов едет, пейджер экранов выключается: иначе, упёршись в
    /// край, лента передаёт остаток жеста ему (scroll chaining) и экран дёргается
    /// в сторону соседней страницы.
    @Binding var isSectionBarScrolling: Bool

    @EnvironmentObject private var session: AppSession
    @StateObject private var store = TodoStore()

    @State private var selectedSection: TodoSection = .smart(.today)
    /// Раскрытая задача и её редактируемая копия: правки применяются к копии и
    /// сохраняются при сворачивании карточки.
    @State private var draft: TodoItem?
    @State private var isQuickAddPresented = false
    @State private var quickAddTitle = ""
    @FocusState private var isQuickAddFocused: Bool
    @State private var listEditor: TodoListEditor?

    // Перетаскивание: порядок текущего раздела «на лету» + смещение поднятой строки.
    @State private var draggingID: Int?
    @State private var dragOrder: [Int] = []
    @State private var dragOffset: CGFloat = 0
    @State private var dragBaseline: CGFloat = 0
    @State private var rowHeights: [Int: CGFloat] = [:]

    private let rowSpacing: CGFloat = 10

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                TodoSectionChipBar(
                    selection: $selectedSection,
                    isScrolling: $isSectionBarScrolling,
                    lists: store.lists,
                    openCount: { store.openCount(in: $0) },
                    onAddList: { listEditor = TodoListEditor(mode: .create) },
                    onRenameList: { list in listEditor = TodoListEditor(mode: .rename(list)) },
                    onDeleteList: { list in
                        Task { await store.deleteList(accessToken: session.currentAccessToken, listID: list.id) }
                    }
                )
                taskList
            }
            .padding(.top, 12)

            addButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if isQuickAddPresented {
                quickAddOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isQuickAddPresented)
        .sheet(item: $listEditor) { editor in
            TodoListEditorSheet(editor: editor) { name in
                Task {
                    switch editor.mode {
                    case .create:
                        await store.addList(accessToken: session.currentAccessToken, name: name)
                    case let .rename(list):
                        await store.renameList(accessToken: session.currentAccessToken, listID: list.id, name: name)
                    }
                }
            }
        }
        .task { await store.loadIfNeeded(accessToken: session.currentAccessToken) }
        .onChange(of: selectedSection) { _, _ in
            dismissKeyboard()
            collapseCard()
        }
    }

    /// Поля живут внутри карточки и оверлея быстрого добавления, каждое со своим
    /// фокусом, поэтому снимаем первого ответчика глобально — как это делает
    /// HomeView на старте свайпа между экранами.
    private func dismissKeyboard() {
        isQuickAddFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Список задач

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: rowSpacing) {
                if let errorMessage = store.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.dangerText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if store.isLoading && store.items.isEmpty {
                    Text("Загружаем задачи...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else if visibleItems.isEmpty {
                    Text(emptyStateTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    ForEach(visibleItems) { item in
                        row(for: item)
                    }
                }
            }
            .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            .padding(.top, 4)
            // Запас снизу, чтобы последняя задача не пряталась под круглой кнопкой.
            .padding(.bottom, 110)
            // Подложка под строками: тап мимо карточки сворачивает её и сохраняет правки.
            // Именно подложкой, а не жестом на всём списке — иначе тап по полю внутри
            // карточки закрывал бы её же.
            .background(
                Color.black.opacity(0.0001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                        collapseCard()
                    }
            )
            .animation(.easeOut(duration: 0.22), value: store.items)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(draggingID != nil)
        // Свайп по списку убирает клавиатуру — как в чате и СРМ.
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "todoRows")
    }

    @ViewBuilder
    private func row(for item: TodoItem) -> some View {
        let isExpanded = draft?.id == item.id
        Group {
            if isExpanded, let binding = draftBinding {
                TodoTaskCard(
                    item: binding,
                    lists: store.lists,
                    onToggleCompleted: { toggleCompleted(item) },
                    onDelete: {
                        collapseCard(save: false)
                        Task { await store.delete(accessToken: session.currentAccessToken, item: item) }
                    }
                )
            } else {
                TodoTaskRow(
                    item: item,
                    listName: item.listID.flatMap { store.listName(for: $0) },
                    showsListName: selectedSection.listID == nil,
                    isDragging: draggingID == item.id,
                    onToggleCompleted: { toggleCompleted(item) },
                    onOpen: { expandCard(item) }
                )
                .gesture(dragGesture(for: item))
            }
        }
        // Карточки задач — светлые, как карточки заказов в СРМ: на чёрном фоне
        // страницы они так отделяются друг от друга.
        .environment(\.colorScheme, .light)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TodoRowHeightKey.self, value: [item.id: proxy.size.height])
            }
        )
        .offset(y: draggingID == item.id ? dragOffset : 0)
        .zIndex(draggingID == item.id ? 1 : 0)
        .onPreferenceChange(TodoRowHeightKey.self) { heights in
            rowHeights.merge(heights) { _, new in new }
        }
    }

    private var draftBinding: Binding<TodoItem>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? TodoItem(id: 0, listID: nil, title: "", note: nil, doAt: nil, deadlineAt: nil, someday: false, tags: [], completed: false, archived: false, position: 0, subtasks: []) },
            set: { draft = $0 }
        )
    }

    private var visibleItems: [TodoItem] {
        let items = store.items(in: selectedSection)
        guard draggingID != nil, !dragOrder.isEmpty else { return items }
        // Во время перетаскивания порядок берём из локальной копии.
        return dragOrder.compactMap { id in items.first(where: { $0.id == id }) }
    }

    private var emptyStateTitle: String {
        switch selectedSection {
        case .smart(.inbox): return "Во «Входящих» пусто — быстро добавьте задачу кнопкой «+»"
        case .smart(.today): return "На сегодня задач нет"
        case .smart(.planned): return "Ничего не запланировано"
        case .smart(.someday): return "Список «Когда-нибудь» пуст"
        case .smart(.archive): return "Архив пуст"
        case .list: return "В этом списке пока нет задач"
        }
    }

    // MARK: - Карточка

    private func expandCard(_ item: TodoItem) {
        if let draft, draft.id != item.id {
            persist(draft)
        }
        withAnimation(.easeOut(duration: 0.18)) {
            draft = item
        }
    }

    private func collapseCard(save: Bool = true) {
        guard let current = draft else { return }
        if save { persist(current) }
        withAnimation(.easeOut(duration: 0.18)) {
            draft = nil
        }
    }

    private func persist(_ item: TodoItem) {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await store.save(accessToken: session.currentAccessToken, item: item) }
    }

    // MARK: - Выполнение

    private func toggleCompleted(_ item: TodoItem) {
        let completed = !item.completed
        if draft?.id == item.id {
            draft?.completed = completed
        }
        Task {
            await store.setCompleted(accessToken: session.currentAccessToken, item: item, completed: completed)
            guard completed else { return }
            // Пара секунд зачёркнутой задачи на месте — и она уезжает в архив.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let fresh = store.items.first(where: { $0.id == item.id }), fresh.completed, !fresh.archived else { return }
            if draft?.id == item.id { collapseCard(save: false) }
            await store.archive(accessToken: session.currentAccessToken, item: fresh)
        }
    }

    // MARK: - Перетаскивание

    private func dragGesture(for item: TodoItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.32)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("todoRows")))
            .onChanged { value in
                switch value {
                case .first:
                    break
                case let .second(_, drag):
                    if draggingID == nil {
                        beginDrag(item)
                    }
                    guard let drag else { return }
                    updateDrag(translation: drag.translation.height)
                }
            }
            .onEnded { _ in endDrag() }
    }

    private func beginDrag(_ item: TodoItem) {
        dismissKeyboard()
        collapseCard()
        dragOrder = store.items(in: selectedSection).map(\.id)
        draggingID = item.id
        dragBaseline = 0
        dragOffset = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateDrag(translation: CGFloat) {
        guard let draggingID, let index = dragOrder.firstIndex(of: draggingID) else { return }
        dragOffset = translation - dragBaseline

        // Пересекли половину соседней строки — меняемся с ней местами, а базовую
        // точку сдвигаем на её высоту, чтобы строка осталась «приклеена» к пальцу.
        if dragOffset > 0, index + 1 < dragOrder.count {
            let neighbour = dragOrder[index + 1]
            let step = (rowHeights[neighbour] ?? 64) + rowSpacing
            if dragOffset > step * 0.6 {
                withAnimation(.easeInOut(duration: 0.16)) {
                    dragOrder.swapAt(index, index + 1)
                }
                dragBaseline += step
                dragOffset = translation - dragBaseline
            }
        } else if dragOffset < 0, index > 0 {
            let neighbour = dragOrder[index - 1]
            let step = (rowHeights[neighbour] ?? 64) + rowSpacing
            if -dragOffset > step * 0.6 {
                withAnimation(.easeInOut(duration: 0.16)) {
                    dragOrder.swapAt(index, index - 1)
                }
                dragBaseline -= step
                dragOffset = translation - dragBaseline
            }
        }
    }

    private func endDrag() {
        guard draggingID != nil else { return }
        let order = dragOrder
        withAnimation(.easeOut(duration: 0.18)) {
            draggingID = nil
            dragOffset = 0
            dragBaseline = 0
        }
        Task { await store.applyReorder(accessToken: session.currentAccessToken, sectionOrder: order) }
    }

    // MARK: - Быстрое добавление

    private var addButton: some View {
        Button {
            collapseCard()
            isQuickAddPresented = true
            isQuickAddFocused = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.primaryButtonText)
                .frame(width: 58, height: 58)
                .background(AppTheme.primaryButtonBackground, in: Circle())
                .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 28)
        .opacity(isQuickAddPresented ? 0 : 1)
    }

    private var quickAddOverlay: some View {
        VStack(spacing: 0) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { closeQuickAdd() }

            HStack(spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))

                TextField(
                    "",
                    text: $quickAddTitle,
                    prompt: Text("Новая задача").foregroundStyle(Color.white.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isQuickAddFocused)
                .submitLabel(.done)
                .onSubmit { submitQuickAdd() }

                Button {
                    closeQuickAdd()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func submitQuickAdd() {
        let title = quickAddTitle
        quickAddTitle = ""
        // Поле остаётся открытым: несколько задач подряд вводятся без лишних касаний.
        isQuickAddFocused = true
        Task { await store.createTask(accessToken: session.currentAccessToken, title: title, section: selectedSection) }
    }

    private func closeQuickAdd() {
        let leftover = quickAddTitle
        quickAddTitle = ""
        isQuickAddFocused = false
        isQuickAddPresented = false
        guard !leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await store.createTask(accessToken: session.currentAccessToken, title: leftover, section: selectedSection) }
    }
}

// MARK: - Лента разделов

private struct TodoSectionChipBar: View {
    @Binding var selection: TodoSection
    @Binding var isScrolling: Bool
    let lists: [TodoListItem]
    let openCount: (TodoSection) -> Int
    let onAddList: () -> Void
    let onRenameList: (TodoListItem) -> Void
    let onDeleteList: (TodoListItem) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TodoSmartList.allCases) { smart in
                    chip(
                        title: smart.title,
                        icon: smart.icon,
                        count: openCount(.smart(smart)),
                        isSelected: selection == .smart(smart)
                    ) {
                        selection = .smart(smart)
                    }
                }

                ForEach(lists) { list in
                    chip(
                        title: list.name,
                        icon: "list.bullet",
                        count: openCount(.list(list.id)),
                        isSelected: selection == .list(list.id)
                    ) {
                        selection = .list(list.id)
                    }
                    .contextMenu {
                        Button {
                            onRenameList(list)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            if selection == .list(list.id) { selection = .smart(.inbox) }
                            onDeleteList(list)
                        } label: {
                            Label("Удалить список", systemImage: "trash")
                        }
                    }
                }

                Button(action: onAddList) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.secondaryButtonText)
                        .frame(width: 38, height: 34)
                        .background(AppTheme.secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Новый список")
            }
            .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            // Лента всегда пружинит по горизонтали: упёршись в край, она сама
            // отрабатывает жест и не отдаёт его пейджеру экранов.
            .background(TodoChipScrollPagerGuard())
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .horizontal)
        // Сам скролл и сообщает, когда он в работе: флаг снимается самой лентой,
        // застрять во включённом состоянии он не может.
        .onScrollPhaseChange { _, phase in
            isScrolling = phase != .idle
        }
    }

    private func chip(title: String, icon: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.primaryButtonText.opacity(0.6) : AppTheme.secondaryButtonText.opacity(0.6))
                }
            }
            .foregroundStyle(isSelected ? AppTheme.primaryButtonText : AppTheme.secondaryButtonText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                (isSelected ? AppTheme.primaryButtonBackground : AppTheme.secondaryButtonBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Свёрнутая строка задачи

private struct TodoTaskRow: View {
    let item: TodoItem
    let listName: String?
    let showsListName: Bool
    let isDragging: Bool
    let onToggleCompleted: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TodoCheckbox(isOn: item.completed, action: onToggleCompleted)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.completed ? Color.secondary : Color.primary)
                    .strikethrough(item.completed, color: Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !metaChips.isEmpty || !item.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(metaChips) { chip in
                            HStack(spacing: 4) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(chip.tint)
                                if let text = chip.text {
                                    Text(text)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(chip.tint)
                                }
                            }
                        }

                        ForEach(item.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(isDragging ? 0.5 : 0.28), lineWidth: 1)
        )
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: Color.black.opacity(isDragging ? 0.45 : 0), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private struct MetaChip: Identifiable {
        let id: String
        let icon: String
        let text: String?
        let tint: Color
    }

    private var metaChips: [MetaChip] {
        var chips: [MetaChip] = []

        if item.isToday {
            // Жёлтая звёздочка — «сегодня». Оттенок притемнён: чистый yellow на светлой
            // карточке почти не читается.
            chips.append(MetaChip(id: "today", icon: "star.fill", text: nil, tint: TodoPalette.today))
        } else if let doDay = item.doMoment {
            chips.append(MetaChip(id: "do", icon: "calendar", text: TodoDay.shortTitle(for: doDay), tint: Color.secondary))
        }

        if let deadline = item.deadlineMoment {
            chips.append(
                MetaChip(
                    id: "deadline",
                    icon: "flag.fill",
                    text: TodoDay.shortTitle(for: deadline),
                    tint: item.isDeadlineOverdue ? Color.red : Color.secondary
                )
            )
        }

        if !item.subtasks.isEmpty {
            chips.append(
                MetaChip(
                    id: "subtasks",
                    icon: "checklist",
                    text: "\(item.doneSubtaskCount)/\(item.subtasks.count)",
                    tint: Color.secondary
                )
            )
        }

        if item.hasNote {
            chips.append(MetaChip(id: "note", icon: "text.alignleft", text: nil, tint: Color.secondary))
        }

        if showsListName, let listName {
            chips.append(MetaChip(id: "list", icon: "list.bullet", text: listName, tint: Color.secondary))
        }

        return chips
    }
}

/// Акценты светлых карточек задач.
private enum TodoPalette {
    static let today = Color(red: 0.85, green: 0.62, blue: 0.05)
    static let checked = Color(red: 0.96, green: 0.44, blue: 0.27)
}

private struct TodoCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(isOn ? 0 : 0.32), lineWidth: 1.6)
                    .frame(width: 22, height: 22)

                if isOn {
                    Circle()
                        .fill(TodoPalette.checked)
                        .frame(width: 22, height: 22)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Раскрытая карточка задачи

private struct TodoTaskCard: View {
    @Binding var item: TodoItem
    let lists: [TodoListItem]
    let onToggleCompleted: () -> Void
    let onDelete: () -> Void

    @State private var newTagText = ""
    @State private var newSubtaskText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TodoCheckbox(isOn: item.completed, action: onToggleCompleted)

                TextField("", text: $item.title, prompt: Text("Название").foregroundStyle(Color.secondary), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }

            TextField("", text: noteBinding, prompt: Text("Заметка").foregroundStyle(Color.secondary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.86))
                .lineLimit(1...6)

            divider

            dateRow(
                title: "Когда",
                icon: "calendar",
                tint: item.isToday ? TodoPalette.today : Color.secondary,
                defaultHour: 9,
                date: doDateBinding
            )

            dateRow(
                title: "Дедлайн",
                icon: "flag.fill",
                tint: item.isDeadlineOverdue ? Color.red : Color.secondary,
                defaultHour: 18,
                date: deadlineBinding
            )

            HStack(spacing: 10) {
                Toggle(isOn: $item.someday) {
                    Label("Когда-нибудь", systemImage: "moon.zzz")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.86))
                }
                .toggleStyle(.switch)
                .tint(TodoPalette.checked)
            }

            listPicker

            divider

            tagsEditor

            divider

            subtasksEditor

            Button(role: .destructive, action: onDelete) {
                Label("Удалить задачу", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.dangerText)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.34))
            .frame(height: 1)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { item.note ?? "" },
            set: { item.note = $0.isEmpty ? nil : $0 }
        )
    }

    private var doDateBinding: Binding<Date?> {
        Binding(
            get: { item.doMoment },
            set: { item.doAt = TodoDay.string(from: $0) }
        )
    }

    private var deadlineBinding: Binding<Date?> {
        Binding(
            get: { item.deadlineMoment },
            set: { item.deadlineAt = TodoDay.string(from: $0) }
        )
    }

    @ViewBuilder
    private func dateRow(title: String, icon: String, tint: Color, defaultHour: Int, date: Binding<Date?>) -> some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.86))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }

            Spacer(minLength: 0)

            if let value = date.wrappedValue {
                DatePicker(
                    "",
                    selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.colorScheme, .light)

                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    date.wrappedValue = TodoDay.defaultMoment(hour: defaultHour)
                } label: {
                    Text("Поставить")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var listPicker: some View {
        HStack(spacing: 10) {
            Label {
                Text("Список")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.86))
            } icon: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 0)

            Menu {
                Button("Без списка") { item.listID = nil }
                ForEach(lists) { list in
                    Button(list.name) { item.listID = list.id }
                }
            } label: {
                Text(currentListName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }

    private var currentListName: String {
        guard let listID = item.listID, let list = lists.first(where: { $0.id == listID }) else {
            return "Без списка"
        }
        return list.name
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Метки")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)

            if !item.tags.isEmpty {
                TodoFlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primary.opacity(0.86))

                            Button {
                                item.tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
            }

            TextField("", text: $newTagText, prompt: Text("Добавить метку").foregroundStyle(Color.secondary.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.primary)
                .submitLabel(.done)
                .onSubmit {
                    let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
                    newTagText = ""
                    guard !tag.isEmpty, !item.tags.contains(tag) else { return }
                    item.tags.append(tag)
                }
        }
    }

    private var subtasksEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подзадачи")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)

            ForEach(Array(item.subtasks.enumerated()), id: \.offset) { index, subtask in
                HStack(spacing: 10) {
                    Button {
                        item.subtasks[index].done.toggle()
                    } label: {
                        Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(subtask.done ? TodoPalette.checked : Color.primary.opacity(0.3))
                    }
                    .buttonStyle(.plain)

                    TextField("", text: Binding(
                        get: { item.subtasks[index].title },
                        set: { item.subtasks[index].title = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(subtask.done ? Color.secondary : Color.primary)
                    .strikethrough(subtask.done, color: Color.secondary)

                    Button {
                        item.subtasks.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))

                TextField("", text: $newSubtaskText, prompt: Text("Новая подзадача").foregroundStyle(Color.secondary.opacity(0.7)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .submitLabel(.done)
                    .onSubmit {
                        let title = newSubtaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                        newSubtaskText = ""
                        guard !title.isEmpty else { return }
                        // id локальной подзадачи не важен: бэкенд переписывает список целиком.
                        item.subtasks.append(TodoSubtask(id: -(item.subtasks.count + 1), title: title, done: false, position: item.subtasks.count))
                    }
            }
        }
    }
}

// MARK: - Списки: добавление и переименование

private struct TodoListEditor: Identifiable {
    enum Mode {
        case create
        case rename(TodoListItem)
    }

    let id = UUID()
    let mode: Mode

    var title: String {
        switch mode {
        case .create: return "Новый список"
        case .rename: return "Переименовать список"
        }
    }

    var initialName: String {
        switch mode {
        case .create: return ""
        case let .rename(list): return list.name
        }
    }
}

private struct TodoListEditorSheet: View {
    let editor: TodoListEditor
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editor.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TextField("", text: $name, prompt: Text("Название").foregroundStyle(Color.white.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: submit) {
                Text("Сохранить")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.height(230)])
        .presentationBackground(Color.black)
        .onAppear {
            name = editor.initialName
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}

// MARK: - Вспомогательное

/// Лента разделов — горизонтальный скролл внутри горизонтального пейджера экранов.
/// По умолчанию UIKit на краю ленты передаёт жест пейджеру, и экран дёргается в
/// сторону соседней страницы. Находим оба скролла (ближайший вверх — лента,
/// следующий — пейджер) и требуем от пейджера дождаться отказа ленты: жест,
/// начатый на ленте, страницу больше не листает. Свайп с любого другого места
/// экрана работает как раньше — зависимость действует только на те касания,
/// которые получила лента.
private struct TodoChipScrollPagerGuard: UIViewRepresentable {
    final class Coordinator {
        var applied = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async { Self.apply(from: view, coordinator: context.coordinator) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard !context.coordinator.applied else { return }
        DispatchQueue.main.async { Self.apply(from: uiView, coordinator: context.coordinator) }
    }

    private static func apply(from view: UIView, coordinator: Coordinator) {
        guard !coordinator.applied else { return }

        var scrollViews: [UIScrollView] = []
        var candidate = view.superview
        while let current = candidate, scrollViews.count < 2 {
            if let scrollView = current as? UIScrollView {
                scrollViews.append(scrollView)
            }
            candidate = current.superview
        }
        guard scrollViews.count == 2 else { return }

        let chipScroll = scrollViews[0]
        let pager = scrollViews[1]
        // Лента должна пружинить, а не упираться: пружина = жест обработан ею самой.
        chipScroll.bounces = true
        chipScroll.alwaysBounceHorizontal = true
        pager.panGestureRecognizer.require(toFail: chipScroll.panGestureRecognizer)
        coordinator.applied = true
    }
}

private struct TodoRowHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Метки переносятся на следующую строку, когда не помещаются в ширину карточки.
private struct TodoFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
