import DiscordBM
import GitHubAPI

struct ProjectBoardHandler {
    let context: HandlerContext
    let action: Issue.Action
    let issue: Issue
    let repo: Repository
    var event: GHEvent {
        self.context.event
    }

    /// Yes, send the raw url as the "note" of the card. GitHub will take care of properly showing it.
    /// If you send customized text instead, the card won't be recognized as an issue-card.
    var note: String {
        self.issue.htmlUrl
    }

    init(context: HandlerContext, action: Issue.Action, issue: Issue) throws {
        self.context = context
        self.action = action
        self.issue = issue
        self.repo = try self.context.event.repository.requireValue()
    }

    func handle() async throws {
        /// Ignore events on closed issues, if the even isn't the closed-event itself.
        if self.issue.isClosed && self.action != .closed { return }

        switch self.action {
        case .labeled:
            try await self.onLabeled()
        case .unlabeled:
            try await self.onUnlabeled()
        case .assigned:
            try await self.onAssigned()
        case .unassigned:
            try await self.onUnassigned()
        case .closed:
            try await self.onClosed()
        case .reopened:
            try await self.onReopened()
        default: break
        }
    }

    func onLabeled() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        try await self.moveOrCreateInToDoOrInProgress(relatedProjects: relatedProjects)
    }

    func onUnlabeled() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        let possibleUnlabeledProjects = Project.allCases.filter { !relatedProjects.contains($0) }
        for project in Set(possibleUnlabeledProjects) {
            for column in Project.Column.allCases {
                let cards = try await self.getCards(in: project.columnID(of: column))
                if let card = cards.firstCard(note: note) {
                    try await self.delete(cardID: card.id)
                }
            }
        }
    }

    func onAssigned() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        for project in Set(relatedProjects) {
            try await self.moveOrCreate(targetColumn: .inProgress, in: project)
        }
    }

    func onUnassigned() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        try await self.moveOrCreateInToDoOrInProgress(relatedProjects: relatedProjects)
    }

    func onClosed() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        if self.issue.stateReason == .notPlanned {
            for project in Set(relatedProjects) {
                try await self.deleteCard(in: project)
            }
        } else {
            for project in Set(relatedProjects) {
                try await self.moveOrCreate(targetColumn: .done, in: project)
            }
        }
    }

    func onReopened() async throws {
        let relatedProjects = self.issue.knownLabels.compactMap(Project.init(label:))
        try await self.moveOrCreateInToDoOrInProgress(relatedProjects: relatedProjects)
    }

    private func moveOrCreateInToDoOrInProgress(relatedProjects: [Project]) async throws {
        for project in Set(relatedProjects) {
            let targetColumn: Project.Column = issue.hasAssignees ? .inProgress : .toDo
            try await self.moveOrCreate(targetColumn: targetColumn, in: project)
        }
    }

    func createCard(columnID: Int) async throws {
        _ = try await self.context.githubClient.projectsCreateCard(
            path: .init(columnId: columnID),
            body: .json(.case1(.init(note: self.note)))
        ).created
    }

    func move(toColumnID columnID: Int, cardID: Int64) async throws {
        _ = try await self.context.githubClient.projectsMoveCard(
            path: .init(cardId: Int(cardID)),
            body: .json(.init(position: "top", columnId: columnID))
        ).created
    }

    func delete(cardID: Int64) async throws {
        _ = try await self.context.githubClient.projectsDeleteCard(
            path: .init(cardId: Int(cardID))
        ).noContent
    }

    func getCards(in columnID: Int) async throws -> [ProjectCard] {
        try await self.context.githubClient.projectsListCards(
            path: .init(columnId: columnID)
        ).ok.body.json
    }

    private func moveOrCreate(targetColumn: Project.Column, in project: Project) async throws {
        func cards(column: Project.Column) async throws -> [ProjectCard] {
            try await self.getCards(in: project.columnID(of: column))
        }

        func move(cardID: Int64) async throws {
            try await self.move(toColumnID: project.columnID(of: targetColumn), cardID: cardID)
        }

        let otherColumns = Project.Column.allCases.filter { $0 != targetColumn }

        var alreadyMoved = false
        for column in otherColumns {
            let cards = try await cards(column: column)
            if let card = cards.firstCard(note: note) {
                if alreadyMoved {
                    try await self.delete(cardID: card.id)
                } else {
                    try await move(cardID: card.id)
                    alreadyMoved = true
                }
            }
        }

        if alreadyMoved {
            return
        }

        let cards = try await cards(column: targetColumn)
        if !cards.containsCard(note: self.note) {
            try await self.createCard(columnID: project.columnID(of: targetColumn))
        }
    }

    private func deleteCard(in project: Project) async throws {
        for column in Project.Column.allCases {
            let cards = try await self.getCards(in: project.columnID(of: column))
            if let card = cards.firstCard(note: note) {
                try await self.delete(cardID: card.id)
            }
        }
    }
}

private enum Project: String, CaseIterable {
    case helpWanted
    case beginner

    enum Column: CaseIterable {
        case toDo
        case inProgress
        case done
    }

    var id: Int {
        switch self {
        case .helpWanted:
            return 14_402_911
        case .beginner:
            return 14_183_112
        }
    }

    func columnID(of column: Column) -> Int {
        switch self {
        case .helpWanted:
            switch column {
            case .toDo:
                return 18_549_893
            case .inProgress:
                return 18_549_894
            case .done:
                return 18_549_895
            }
        case .beginner:
            switch column {
            case .toDo:
                return 17_909_684
            case .inProgress:
                return 17_909_685
            case .done:
                return 17_909_686
            }
        }
    }

    init?(label: Issue.KnownLabel) {
        switch label {
        case .helpWanted:
            self = .helpWanted
        case .goodFirstIssue:
            self = .beginner
        default:
            return nil
        }
    }
}

extension [ProjectCard] {
    private func areNotesEqual(_ element: Self.Element, _ note: String) -> Bool {
        element.contentUrl == note || element.note == note
    }

    fileprivate func containsCard(note: String) -> Bool {
        self.contains { areNotesEqual($0, note) }
    }

    fileprivate func firstCard(note: String) -> Self.Element? {
        self.first { areNotesEqual($0, note) }
    }
}

extension Issue {
    fileprivate var isClosed: Bool {
        self.state == "closed"
    }

    fileprivate var hasAssignees: Bool {
        !(self.assignees ?? []).isEmpty
    }
}
