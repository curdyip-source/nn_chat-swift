//
//  TodoStore.swift
//  NufNaf Chat
//
//  Состояние тудулиста. Задачи личные и их немного, поэтому доска (списки + все
//  задачи) грузится целиком одним запросом, а раскладка по умным спискам считается
//  здесь же. Изменения применяем оптимистично: интерфейс не ждёт сеть, при ошибке
//  перечитываем доску с сервера.
//

import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var lists: [TodoListItem] = []
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: HomeAPIClient
    private var hasLoadedOnce = false

    // Клиент создаём в теле init, а не значением по умолчанию: дефолтное выражение
    // вычисляется в контексте вызывающего, а инициализатор HomeAPIClient изолирован
    // главным актором (как в HomeStore).
    init(client: HomeAPIClient? = nil) {
        self.client = client ?? HomeAPIClient()
    }

    // MARK: - Загрузка

    func loadIfNeeded(accessToken: String?) async {
        guard !hasLoadedOnce else { return }
        await load(accessToken: accessToken)
    }

    func load(accessToken: String?) async {
        guard let accessToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let board = try await client.getTodoBoard(accessToken: accessToken)
            apply(board)
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    // MARK: - Выборки

    func items(in section: TodoSection) -> [TodoItem] {
        items.filter { (item: TodoItem) -> Bool in
            switch section {
            case .smart(.archive):
                return item.archived
            case .smart(.inbox):
                return !item.archived && item.listID == nil && item.doAt == nil && !item.someday
            case .smart(.today):
                return !item.archived && item.isToday
            case .smart(.planned):
                return !item.archived && item.isPlanned
            case .smart(.someday):
                return !item.archived && item.someday
            case let .list(listID):
                return !item.archived && item.listID == listID
            }
        }
    }

    func openCount(in section: TodoSection) -> Int {
        items(in: section).filter { !$0.completed }.count
    }

    func listName(for listID: Int) -> String? {
        lists.first(where: { $0.id == listID })?.name
    }

    // MARK: - Задачи

    func createTask(accessToken: String?, title: String, section: TodoSection) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let accessToken else { return }
        do {
            let created = try await client.createTodo(accessToken: accessToken, title: trimmed, listID: section.listID)
            var item = created
            // Новая задача сразу попадает в тот раздел, где её завели: для «Сегодня» это
            // дата на сегодня, для «Когда-нибудь» — соответствующий флаг.
            if let adjusted = try await adjustNewTask(accessToken: accessToken, item: created, section: section) {
                item = adjusted
            }
            items.append(item)
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    func save(accessToken: String?, item: TodoItem) async {
        replaceLocally(item)
        guard let accessToken else { return }
        let request = TodoUpdateRequest(
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            listID: item.listID,
            note: item.note,
            doAt: item.doAt,
            deadlineAt: item.deadlineAt,
            someday: item.someday,
            tags: item.tags,
            subtasks: item.subtasks.map { TodoSubtaskRequest(title: $0.title, done: $0.done) }
        )
        do {
            let updated = try await client.updateTodo(accessToken: accessToken, todoID: item.id, request: request)
            replaceLocally(updated)
        } catch {
            errorMessage = resolveActionError(error)
            await load(accessToken: accessToken)
        }
    }

    func setCompleted(accessToken: String?, item: TodoItem, completed: Bool) async {
        var local = item
        local.completed = completed
        if !completed { local.archived = false }
        replaceLocally(local)
        guard let accessToken else { return }
        do {
            let updated = try await client.setTodoCompleted(accessToken: accessToken, todoID: item.id, completed: completed)
            replaceLocally(updated)
        } catch {
            errorMessage = resolveActionError(error)
            await load(accessToken: accessToken)
        }
    }

    func archive(accessToken: String?, item: TodoItem) async {
        var local = item
        local.archived = true
        replaceLocally(local)
        guard let accessToken else { return }
        do {
            let updated = try await client.setTodoArchived(accessToken: accessToken, todoID: item.id, archived: true)
            replaceLocally(updated)
        } catch {
            errorMessage = resolveActionError(error)
            await load(accessToken: accessToken)
        }
    }

    func delete(accessToken: String?, item: TodoItem) async {
        items.removeAll { $0.id == item.id }
        guard let accessToken else { return }
        do {
            try await client.deleteTodo(accessToken: accessToken, todoID: item.id)
        } catch {
            errorMessage = resolveActionError(error)
            await load(accessToken: accessToken)
        }
    }

    /// Новый порядок задач раздела после перетаскивания. Позиции сквозные по всей
    /// доске, поэтому переставляем задачи раздела по занятым ими местам (остальные
    /// не двигаются) и отправляем весь список в новом порядке.
    func applyReorder(accessToken: String?, sectionOrder: [Int]) async {
        let moved = Set(sectionOrder)
        var queue = sectionOrder.compactMap { id in items.first(where: { $0.id == id }) }
        guard !queue.isEmpty else { return }
        items = items.map { item in
            guard moved.contains(item.id) else { return item }
            return queue.removeFirst()
        }
        guard let accessToken else { return }
        do {
            let board = try await client.reorderTodos(accessToken: accessToken, order: items.map(\.id))
            apply(board)
        } catch {
            errorMessage = resolveActionError(error)
            await load(accessToken: accessToken)
        }
    }

    // MARK: - Списки

    func addList(accessToken: String?, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let accessToken else { return }
        do {
            let created = try await client.createTodoList(accessToken: accessToken, name: trimmed)
            lists.append(created)
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    func renameList(accessToken: String?, listID: Int, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let accessToken else { return }
        do {
            let updated = try await client.renameTodoList(accessToken: accessToken, listID: listID, name: trimmed)
            if let index = lists.firstIndex(where: { $0.id == listID }) {
                lists[index] = updated
            }
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    func deleteList(accessToken: String?, listID: Int) async {
        guard let accessToken else { return }
        do {
            try await client.deleteTodoList(accessToken: accessToken, listID: listID)
            lists.removeAll { $0.id == listID }
            // Задачи удалённого списка возвращаются во «Входящие» — как на бэкенде.
            for index in items.indices where items[index].listID == listID {
                items[index].listID = nil
            }
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    // MARK: - Внутреннее

    private func apply(_ board: TodoBoardResponse) {
        lists = board.lists.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        items = board.items.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    private func replaceLocally(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    /// Задача, созданная в «Сегодня» или «Когда-нибудь», должна там и остаться:
    /// дописываем ей дату/флаг сразу после создания.
    private func adjustNewTask(accessToken: String, item: TodoItem, section: TodoSection) async throws -> TodoItem? {
        guard case let .smart(smart) = section else { return nil }
        var doAt: String? = nil
        var someday = false
        switch smart {
        case .today:
            // Заведённая в «Сегодня» задача получает сегодняшнее утро — чтобы там и осталась.
            doAt = TodoDay.string(from: TodoDay.defaultMoment(hour: 9))
        case .someday:
            someday = true
        case .inbox, .planned, .archive:
            return nil
        }
        let request = TodoUpdateRequest(
            title: item.title,
            listID: item.listID,
            note: item.note,
            doAt: doAt,
            deadlineAt: item.deadlineAt,
            someday: someday,
            tags: item.tags,
            subtasks: []
        )
        return try await client.updateTodo(accessToken: accessToken, todoID: item.id, request: request)
    }
}
