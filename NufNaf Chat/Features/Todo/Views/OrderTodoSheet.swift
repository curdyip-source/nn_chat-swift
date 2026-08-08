//
//  OrderTodoSheet.swift
//  NufNaf Chat
//
//  Редактирование задачи заказа из карточки заказа: название, заметка, сроки,
//  ответственные. Полный набор полей (метки, подзадачи, списки) остаётся в
//  тудулисте — здесь только то, что нужно по ходу работы с заказом.
//

import SwiftUI

/// Что показывает форма задачи в карточке заказа: новую или существующую.
enum OrderTodoSheetTarget: Identifiable {
    case create(orderID: Int)
    case edit(TodoItem)

    var id: String {
        switch self {
        case let .create(orderID): return "create-\(orderID)"
        case let .edit(todo): return "edit-\(todo.id)"
        }
    }
}

struct OrderTodoSheet: View {
    let todo: TodoItem
    /// Новая задача: форма та же, но без удаления и отметки «выполнена», а «Готово»
    /// создаёт задачу. Так создание и редактирование выглядят одинаково.
    let isNew: Bool
    let participants: [ChatParticipant]
    let onSave: (TodoItem) -> Void
    let onDelete: () -> Void

    private enum Field: Hashable {
        case title
        case note
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var isDeleteConfirmPresented = false
    @FocusState private var focusedField: Field?

    init(
        todo: TodoItem,
        isNew: Bool = false,
        participants: [ChatParticipant],
        onSave: @escaping (TodoItem) -> Void,
        onDelete: @escaping () -> Void = {}
    ) {
        self.todo = todo
        self.isNew = isNew
        self.participants = participants
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: todo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $draft.title, axis: .vertical)
                        .focused($focusedField, equals: .title)
                    TextField("Заметка", text: noteBinding, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .lineLimit(1...6)
                    if !isNew {
                        Toggle("Выполнена", isOn: $draft.completed)
                    }
                }

                Section("Сроки") {
                    dateRow(title: "Когда", date: doBinding, defaultHour: 9)
                    dateRow(title: "Дедлайн", date: deadlineBinding, defaultHour: 18)
                }

                Section("Ответственные") {
                    ForEach(participants) { participant in
                        Button {
                            focusedField = nil
                            toggleAssignee(participant)
                        } label: {
                            HStack {
                                Text(participant.displayName)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if draft.assignees.contains(where: { $0.id == participant.id }) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            isDeleteConfirmPresented = true
                        } label: {
                            Label("Удалить задачу", systemImage: "trash")
                        }
                    }
                }
            }
            // Форма светлая целиком — иначе клавиатура у разных полей приходила то
            // белой, то чёрной: её вид берётся из colorScheme окружения, а карточка
            // заказа местами навязывает свой.
            .environment(\.colorScheme, .light)
            .scrollDismissesKeyboard(.immediately)
            // Тап по любому месту формы убирает клавиатуру: иначе она перекрывает
            // список ответственных и «съедает» первое касание по строке.
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
            .navigationTitle(isNew ? "Новая задача" : "Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focusedField = nil }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Создать" : "Готово") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Форма создания открывается сразу с курсором в названии.
                if isNew { focusedField = .title }
            }
            .alert("Удалить задачу?", isPresented: $isDeleteConfirmPresented) {
                Button("Удалить", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Задача пропадёт и из заказа, и из тудулиста. Удалить может только её автор.")
            }
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { draft.note ?? "" },
            set: { draft.note = $0.isEmpty ? nil : $0 }
        )
    }

    private var doBinding: Binding<Date?> {
        Binding(
            get: { draft.doMoment },
            set: { draft.doAt = TodoDay.string(from: $0) }
        )
    }

    private var deadlineBinding: Binding<Date?> {
        Binding(
            get: { draft.deadlineMoment },
            set: { draft.deadlineAt = TodoDay.string(from: $0) }
        )
    }

    @ViewBuilder
    private func dateRow(title: String, date: Binding<Date?>, defaultHour: Int) -> some View {
        if let value = date.wrappedValue {
            HStack {
                DatePicker(
                    title,
                    selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )

                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button("\(title): поставить") {
                date.wrappedValue = TodoDay.defaultMoment(hour: defaultHour)
            }
        }
    }

    private func toggleAssignee(_ participant: ChatParticipant) {
        if let index = draft.assignees.firstIndex(where: { $0.id == participant.id }) {
            draft.assignees.remove(at: index)
        } else {
            draft.assignees.append(
                TodoAssignee(
                    id: participant.id,
                    login: participant.userLogin,
                    firstName: participant.userFirstName,
                    secondName: participant.userSecondName
                )
            )
        }
    }
}
