//
//  TodoModels.swift
//  NufNaf Chat
//
//  Тудулист: пользовательские списки, задачи и подзадачи. Умные списки (Входящие,
//  Сегодня, Запланировано, Когда-нибудь, Архив) бэкенд не хранит — они выводятся из
//  полей задачи здесь же, на клиенте.
//

import Foundation

struct TodoBoardResponse: Codable {
    let lists: [TodoListItem]
    let items: [TodoItem]
}

struct TodoListItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id = "todo_list_id"
        case name = "todo_list_name"
        case position = "todo_list_position"
    }
}

struct TodoSubtask: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var done: Bool
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id = "todo_subtask_id"
        case title = "todo_subtask_title"
        case done = "todo_subtask_done"
        case position = "todo_subtask_position"
    }
}

struct TodoItem: Codable, Identifiable, Hashable {
    let id: Int
    var listID: Int?
    var title: String
    var note: String?
    var doAt: String?
    var deadlineAt: String?
    var someday: Bool
    var tags: [String]
    var completed: Bool
    var archived: Bool
    var position: Int
    var subtasks: [TodoSubtask]

    enum CodingKeys: String, CodingKey {
        case id = "todo_id"
        case listID = "todo_list_id"
        case title = "todo_title"
        case note = "todo_note"
        case doAt = "todo_do_at"
        case deadlineAt = "todo_deadline_at"
        case someday = "todo_someday"
        case tags = "todo_tags"
        case completed = "todo_completed"
        case archived = "todo_archived"
        case position = "todo_position"
        case subtasks
    }

    var doMoment: Date? { TodoDay.parse(doAt) }
    var deadlineMoment: Date? { TodoDay.parse(deadlineAt) }

    /// Задача на сегодня (и просроченная — она тоже требует внимания сегодня).
    var isToday: Bool {
        guard let doMoment else { return false }
        return Calendar.current.startOfDay(for: doMoment) <= TodoDay.today
    }

    var isPlanned: Bool {
        guard let doMoment else { return false }
        return Calendar.current.startOfDay(for: doMoment) > TodoDay.today
    }

    /// Срок уже прошёл — рисуем красный флажок. У выполненной задачи не горит.
    /// Сравниваем с точностью до минуты: у дедлайна теперь есть время.
    var isDeadlineOverdue: Bool {
        guard !completed, let deadlineMoment else { return false }
        return deadlineMoment < Date()
    }

    var doneSubtaskCount: Int { subtasks.filter(\.done).count }

    var hasNote: Bool {
        guard let note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Сроки задач — момент (дата со временем). Бэкенд отдаёт ISO-8601 в UTC, на
/// экране показываем в локальной зоне.
enum TodoDay {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// Разбор — общим парсером дат бэкенда (он терпит и дробные секунды).
    static func parse(_ value: String?) -> Date? {
        HomeMessageDateParser.parse(value)
    }

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        return isoFormatter.string(from: date)
    }

    /// Подпись срока для строки задачи: «Сегодня 09:00», «Завтра 18:30», «7 авг 12:00».
    static func shortTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return "Сегодня \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра \(time)" }
        if calendar.isDateInYesterday(date) { return "Вчера \(time)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy")
        return "\(formatter.string(from: date)) \(time)"
    }

    /// Срок по умолчанию, когда его только ставят: ближайший рабочий момент —
    /// сегодня в 9 утра для «Когда» и в 18:00 для дедлайна.
    static func defaultMoment(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()
}

/// Умные списки слева в Things — у нас чипсы в шапке экрана.
enum TodoSmartList: String, CaseIterable, Identifiable, Hashable {
    case inbox
    case today
    case planned
    case someday
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Входящие"
        case .today: return "Сегодня"
        case .planned: return "Запланировано"
        case .someday: return "Когда-нибудь"
        case .archive: return "Архив"
        }
    }

    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .today: return "star"
        case .planned: return "calendar"
        case .someday: return "moon.zzz"
        case .archive: return "archivebox"
        }
    }
}

enum TodoSection: Hashable {
    case smart(TodoSmartList)
    case list(Int)

    var listID: Int? {
        if case let .list(id) = self { return id }
        return nil
    }

    var isArchive: Bool {
        if case .smart(.archive) = self { return true }
        return false
    }
}

// MARK: - Запросы

struct TodoCreateRequest: Encodable {
    let title: String
    let listID: Int?

    enum CodingKeys: String, CodingKey {
        case title = "todo_title"
        case listID = "todo_list_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(listID, forKey: .listID)
    }
}

/// Сохранение карточки целиком: поля пишем всегда, в том числе явными null —
/// так снимаются дата, дедлайн и список. Бэкенд отличает «не прислали» от «null».
struct TodoUpdateRequest: Encodable {
    let title: String
    let listID: Int?
    let note: String?
    let doAt: String?
    let deadlineAt: String?
    let someday: Bool
    let tags: [String]
    let subtasks: [TodoSubtaskRequest]

    enum CodingKeys: String, CodingKey {
        case title = "todo_title"
        case listID = "todo_list_id"
        case note = "todo_note"
        case doAt = "todo_do_at"
        case deadlineAt = "todo_deadline_at"
        case someday = "todo_someday"
        case tags = "todo_tags"
        case subtasks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(listID, forKey: .listID)
        try container.encode(note, forKey: .note)
        try container.encode(doAt, forKey: .doAt)
        try container.encode(deadlineAt, forKey: .deadlineAt)
        try container.encode(someday, forKey: .someday)
        try container.encode(tags, forKey: .tags)
        try container.encode(subtasks, forKey: .subtasks)
    }
}

struct TodoSubtaskRequest: Encodable {
    let title: String
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case title = "todo_subtask_title"
        case done = "todo_subtask_done"
    }
}

struct TodoCompletionRequest: Encodable {
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case completed = "todo_completed"
    }
}

struct TodoArchiveRequest: Encodable {
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case archived = "todo_archived"
    }
}

struct TodoReorderRequest: Encodable {
    let items: [Item]

    struct Item: Encodable {
        let id: Int
        let position: Int

        enum CodingKeys: String, CodingKey {
            case id = "todo_id"
            case position = "todo_position"
        }
    }
}

struct TodoListNameRequest: Encodable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "todo_list_name"
    }
}
