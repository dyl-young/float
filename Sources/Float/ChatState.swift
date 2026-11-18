import AppKit
import FloatCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable, Equatable {
    var id: String
    let runId: String?
    let position: Int
    let isUser: Bool
    var text: String
    let date: Date?
    let previews: [Data]
}

enum NoticeKind {
    case input
    case connection
    case run
}

@MainActor
final class ChatState: ObservableObject {
    @Published var draft: String {
        didSet {
            defaults.set(draft, forKey: "draft")
            if noticeKind == .input { clearNotice() }
        }
    }
    @Published private(set) var images: [ImageAttachment] = []
    @Published private(set) var reference: ThreadReference?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var title: String?
    @Published private(set) var status: RunStatus = .idle {
        didSet {
            if oldValue != status {
                dismissedStatusNotice = nil
                if status == .running && !submitting { thinkingStartedAt = .now }
            }
        }
    }
    @Published private(set) var thinkingStartedAt: Date?
    @Published private(set) var submitting = false
    @Published private(set) var stopping = false
    @Published private(set) var stopAcknowledged = false
    @Published private(set) var loading = false
    @Published private(set) var hasOlderMessages = false
    @Published private(set) var loadingOlder = false
    @Published private(set) var notice: String?
    @Published private(set) var noticeTitle: String?
    @Published private(set) var noticeKind: NoticeKind?
    @Published private(set) var noticeDetail: String?
    @Published private(set) var needsT3 = false
    @Published private(set) var canLaunchT3 = false
    @Published private(set) var pendingQuestion: T3PendingQuestionRequest?
    @Published private(set) var questionIndex = 0
    @Published private(set) var questionDrafts: [String: T3QuestionDraft] = [:]
    @Published private(set) var questionError: String?
    @Published private(set) var answeringQuestion = false
    @Published private(set) var answeredQuestionSummary: String?
    @Published private(set) var focusRequest = 0
    @Published private(set) var modelPickerRequest = 0
    @Published private(set) var projectPickerRequest = 0
    @Published private(set) var machinePickerRequest = 0
    @Published private(set) var models: [T3Model] = []
    @Published private(set) var modelProviders: [T3ModelProvider] = []
    @Published private(set) var favouriteModelKeys: Set<T3ModelKey> = []
    @Published private(set) var loadingModels = false
    @Published private(set) var modelCatalogFailed = false
    @Published private(set) var projects: [T3Project] = []
    @Published private(set) var loadingProjects = false
    @Published private(set) var projectCatalogFailed = false
    @Published private(set) var selectedProjectID: String?
    @Published private(set) var threadProjectID: String?
    @Published private(set) var machines: [T3Machine] = []
    @Published private(set) var loadingMachines = false
    @Published private(set) var selectedMachineID: String?
    @Published private var threadModel: T3ModelSelection?
    @Published private var nextModel: T3ModelSelection?
    @Published private var savedModel: T3ModelSelection?
    @Published private var dismissedStatusNotice: RunStatus?
    @Published private(set) var failureReason: String?
    @Published private(set) var failureDetail: String?

    private let defaults: UserDefaults
    private let client: T3Client
    private let favouritesStore: T3ModelFavouritesStore
    private var modelEfforts: [String: String]
    private var watcher: Task<Void, Never>?
    private var previews: [String: [Data]] = [:]
    private var earliest: Int?
    private var receivedFirstPage = false
    private var generation = 0
    private var visible = false
    private var expandedText: [String: (timestamp: String, text: String)] = [:]
    private var pendingMessage: ChatMessage?
    private var activeRunId: String?
    private var retrySendAfterLaunch = false

    init(
        client: T3Client, defaults: UserDefaults = .standard,
        favouritesStore: T3ModelFavouritesStore? = nil
    ) {
        self.defaults = defaults
        self.client = client
        self.favouritesStore = favouritesStore ?? T3ModelFavouritesStore(
            settingsURL: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".t3/userdata/settings.json")
        )
        modelEfforts = defaults.dictionary(forKey: "modelEfforts") as? [String: String] ?? [:]
        draft = defaults.string(forKey: "draft") ?? ""
        selectedProjectID = defaults.string(forKey: "preferredProjectID")
        selectedMachineID = defaults.string(forKey: "preferredMachineID")
        if let data = defaults.data(forKey: "preferredModel") {
            savedModel = try? JSONDecoder().decode(T3ModelSelection.self, from: data)
        }
        if let data = defaults.data(forKey: "thread"),
            let stored = try? JSONDecoder().decode(ThreadReference.self, from: data) {
            reference = stored
            if let encoded = defaults.data(forKey: "previews") {
                previews = (try? PropertyListDecoder().decode([String: [Data]].self, from: encoded)) ?? [:]
            }
        }
    }

    var hasConversation: Bool { reference != nil || submitting }
    var hasTrayNotice: Bool { notice != nil && noticeKind != .input }
    var statusNoticeDismissed: Bool { dismissedStatusNotice == status }
    var activeQuestion: T3Question? {
        guard let questions = pendingQuestion?.questions, questions.indices.contains(questionIndex) else {
            return nil
        }
        return questions[questionIndex]
    }
    var questionCanAdvance: Bool {
        guard let question = activeQuestion else { return false }
        return T3QuestionAnswerBuilder.resolve(question, draft: questionDrafts[question.id]) != nil
    }
    var isLastQuestion: Bool {
        guard let count = pendingQuestion?.questions.count else { return true }
        return questionIndex >= count - 1
    }
    var composerText: String {
        guard let question = activeQuestion else { return draft }
        guard question.allowsCustom else { return "" }
        return questionDrafts[question.id]?.customAnswer ?? ""
    }
    var composerPlaceholder: String {
        if let question = activeQuestion {
            return question.allowsCustom ? "Or type your own answer…" : "Pick an answer above…"
        }
        return hasConversation ? "Ask a follow-up…" : "Ask anything, or paste a screenshot…"
    }
    var composerEditable: Bool { activeQuestion?.allowsCustom != false }
    var showsStop: Bool { submitting || (status == .running && !stopAcknowledged) || stopping }
    var canStop: Bool { showsStop && !stopping }
    var canSend: Bool {
        !submitting && !stopping && !loading && status != .running && status != .waiting &&
            (reference != nil || !loadingProjects) &&
            (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var selectedModel: T3ModelSelection? {
        if reference != nil { return nextModel ?? threadModel }
        return T3Model.preferred(in: models, saved: savedModel)?.selection
    }

    var defaultModel: T3Model? { T3Model.preferred(in: models) }

    var usesDefaultModel: Bool {
        savedModel == nil && defaultModel?.selection.matches(selectedModel) == true
    }

    var selectedCatalogModel: T3Model? { models.first { $0.selection.matches(selectedModel) } }

    var modelLabel: String {
        selectedCatalogModel?.label
            ?? selectedModel?.fallbackLabel
            ?? "Choose model"
    }

    var canChooseModel: Bool {
        !submitting && !loading && status != .running && status != .waiting
    }

    var selectedProject: T3Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var projectLabel: String { selectedProject?.title ?? "No project" }

    var threadProject: T3Project? {
        projects.first { $0.id == threadProjectID }
    }

    var hasThreadProject: Bool { threadProject != nil || reference?.projectName != nil }

    var threadProjectLabel: String {
        threadProject?.title ?? reference?.projectName ?? "No project"
    }

    var threadMachineName: String? { reference?.machineName }

    var threadSubtitle: String {
        guard let threadMachineName else { return threadProjectLabel }
        return "\(threadProjectLabel) · \(threadMachineName)"
    }

    var canChooseProject: Bool {
        reference == nil && !submitting && !loading
    }

    var selectedMachine: T3Machine? {
        machines.first { $0.id == selectedMachineID } ?? machines.first(where: \.isLocal)
    }

    var machineLabel: String { selectedMachine?.name ?? "This Mac" }

    var showsMachinePicker: Bool { machines.count > 1 }

    var selectedMachineEnvironmentID: String? {
        guard let machine = selectedMachine, !machine.isLocal else { return nil }
        return machine.id
    }

    var canChooseMachine: Bool {
        reference == nil && !submitting && !loading && !loadingMachines && !loadingProjects
    }

    func requestModelPicker() {
        if canChooseModel { modelPickerRequest += 1 }
    }

    func requestProjectPicker() {
        if canChooseProject { projectPickerRequest += 1 }
    }

    func requestMachinePicker() {
        if canChooseMachine, showsMachinePicker { machinePickerRequest += 1 }
    }

    func reloadModels() {
        guard !loadingModels else { return }
        loadingModels = true
        modelCatalogFailed = false
        Task {
            defer { loadingModels = false }
            do {
                let catalogue = try await client.modelCatalogue()
                modelProviders = catalogue.providers
                models = catalogue.available
                await reloadFavourites()
            } catch {
                modelCatalogFailed = true
            }
        }
    }

    func selectModel(_ model: T3Model?) {
        guard canChooseModel, let selection = (model ?? defaultModel)?.selection else { return }
        savedModel = model?.selection
        if reference != nil { nextModel = selection.matches(threadModel) ? nil : selection }
        defaults.set(savedModel.flatMap { try? JSONEncoder().encode($0) }, forKey: "preferredModel")
        focusRequest += 1
    }

    func reloadProjects() {
        guard !loadingProjects else { return }
        let environmentID = selectedMachineEnvironmentID
        let machineID = selectedMachine?.id
        loadingProjects = true
        projectCatalogFailed = false
        Task {
            defer { loadingProjects = false }
            do {
                let loaded = try await client.projects(environmentID: environmentID)
                guard selectedMachine?.id == machineID else { return }
                projects = loaded
                selectedProjectID = T3MachinePicker.projectIDAfterSwitch(
                    selectedProjectID, projectsOnSelectedMachine: projects
                )
                defaults.set(selectedProjectID, forKey: "preferredProjectID")
            } catch {
                projects = []
                projectCatalogFailed = true
            }
        }
    }

    func selectProject(_ project: T3Project?) {
        guard canChooseProject else { return }
        selectedProjectID = project?.id
        defaults.set(selectedProjectID, forKey: "preferredProjectID")
        focusRequest += 1
    }

    func reloadMachines() {
        guard !loadingMachines else { return }
        loadingMachines = true
        Task {
            defer { loadingMachines = false }
            do {
                machines = try await client.machines()
            } catch {
                machines = [
                    T3Machine(
                        id: "__float_local__", name: "This Mac", kind: .local,
                        status: .reachable
                    ),
                ]
            }
            selectedMachineID = T3MachinePicker.resolvedID(
                selectedMachineID, machines: machines
            )
            defaults.set(selectedMachineID, forKey: "preferredMachineID")
            projects = []
            reloadProjects()
        }
    }

    func selectMachine(_ machine: T3Machine) {
        guard canChooseMachine, machine.isOnline else { return }
        selectedMachineID = machine.id
        defaults.set(machine.id, forKey: "preferredMachineID")
        projects = []
        projectCatalogFailed = false
        reloadProjects()
        focusRequest += 1
    }

    func restoreComposerFocus() {
        focusRequest += 1
    }

    func isFavourite(_ model: T3Model) -> Bool {
        favouriteModelKeys.contains(T3ModelKey(model.selection))
    }

    func toggleFavourite(_ model: T3Model) {
        let key = T3ModelKey(model.selection)
        let wasFavourite = favouriteModelKeys.contains(key)
        if wasFavourite {
            favouriteModelKeys.remove(key)
        } else {
            favouriteModelKeys.insert(key)
        }
        Task {
            do {
                favouriteModelKeys = try await favouritesStore.setFavourite(!wasFavourite, key: key)
            } catch {
                if wasFavourite {
                    favouriteModelKeys.insert(key)
                } else {
                    favouriteModelKeys.remove(key)
                }
            }
        }
    }

    func effort(for model: T3Model) -> String? {
        guard let option = model.effortOption else { return nil }
        let saved = modelEfforts[T3ModelKey(model.selection).storageKey]
        if let saved, option.stringValues.contains(saved) { return saved }
        return option.defaultString ?? option.stringValues.first
    }

    func setEffort(_ value: String, for model: T3Model) {
        guard model.effortOption?.stringValues.contains(value) == true else { return }
        modelEfforts[T3ModelKey(model.selection).storageKey] = value
        defaults.set(modelEfforts, forKey: "modelEfforts")
    }

    func searchModelProviders(_ query: String) async -> [T3ModelProvider] {
        do {
            return try await client.modelCatalogue(search: T3ModelSearch.serverQuery(query)).providers
        } catch {
            return modelProviders
        }
    }

    func revealed() {
        visible = true
        focusRequest += 1
        if models.isEmpty {
            reloadModels()
        } else {
            Task { await reloadFavourites() }
        }
        if machines.isEmpty {
            reloadMachines()
        } else if projects.isEmpty {
            reloadProjects()
        }
        if let reference { refresh(reference, force: watcher == nil) }
    }

    func hidden() { visible = false }

    func newChat() {
        guard !submitting else { return }
        generation += 1
        watcher?.cancel()
        watcher = nil
        draft = ""
        images = []
        reference = nil
        threadProjectID = nil
        threadModel = nil
        nextModel = nil
        messages = []
        title = nil
        status = .idle
        stopping = false
        stopAcknowledged = false
        activeRunId = nil
        clearNotice()
        dismissedStatusNotice = nil
        failureReason = nil
        failureDetail = nil
        resetQuestion()
        answeredQuestionSummary = nil
        needsT3 = false
        canLaunchT3 = false
        loading = false
        hasOlderMessages = false
        loadingOlder = false
        pendingMessage = nil
        earliest = nil
        receivedFirstPage = false
        expandedText = [:]
        previews = [:]
        persist()
        focusRequest += 1
    }

    func openThread() {
        guard let url = reference?.desktopURL else { return }
        if !NSWorkspace.shared.open(url) {
            needsT3 = true
            setNotice(
                "Float couldn't open the thread in T3 Code.", title: "Can't open T3",
                kind: .connection
            )
        }
    }

    func openProviderSettings(_ instanceId: String) {
        let encoded = instanceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? instanceId
        if let url = URL(string: "t3code://app/settings/providers?instanceId=\(encoded)"),
            NSWorkspace.shared.open(url) {
            return
        }
        launchT3()
    }

    func openMachineSettings() {
        if let url = URL(string: "t3code://app/settings/connections"),
            NSWorkspace.shared.open(url) {
            return
        }
        launchT3()
    }

    func launchT3() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.t3tools.t3code") else {
            needsT3 = true
            setNotice(
                "Download it from t3.codes.", title: "T3 Code isn't installed",
                kind: .connection
            )
            return
        }
        let shouldSend = retrySendAfterLaunch
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message {
                    self.needsT3 = true
                    self.setNotice(
                        "Try launching it directly, then send again.", title: "Couldn't launch T3 Code",
                        kind: .connection, detail: message, canLaunchT3: true
                    )
                } else {
                    await self.waitForT3AndResume(shouldSend: shouldSend)
                }
            }
        }
        needsT3 = false
        clearNotice()
    }

    private func waitForT3AndResume(shouldSend: Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while clock.now < deadline {
            do {
                let catalogue = try await client.modelCatalogue()
                modelProviders = catalogue.providers
                models = catalogue.available
                modelCatalogFailed = false
                needsT3 = false
                if shouldSend {
                    retrySendAfterLaunch = false
                    send()
                } else if let reference {
                    refresh(reference, force: watcher == nil)
                }
                return
            } catch {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        needsT3 = true
        setNotice(
            "T3 didn't start in time.", title: "T3 Code isn't running",
            kind: .connection, detail: T3Error.serverUnavailable.localizedDescription, canLaunchT3: true
        )
    }

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf16.count <= 120_000 else {
            setNotice("T3 accepts up to 120,000 characters per message.", kind: .input)
            return
        }
        let launchMachine = reference == nil ? selectedMachine : nil
        let environmentID = reference?.environmentID
            ?? (launchMachine?.isLocal == false ? launchMachine?.id : nil)
        if environmentID != nil, !images.isEmpty {
            setNotice("Attachments can't be sent to a linked machine yet.", kind: .input)
            return
        }
        let attachments = images
        let request = UUID()
        let target = reference
        let projectID = target == nil ? selectedProject?.id : nil
        let selection = selectedModel.map(selectionForSend)
        clearNotice()
        answeredQuestionSummary = nil
        needsT3 = false
        retrySendAfterLaunch = false
        thinkingStartedAt = .now
        submitting = true
        stopAcknowledged = false
        watcher?.cancel()
        watcher = nil

        Task {
            do {
                let receipt = try await client.send(
                    text, images: attachments, thread: target, requestId: request,
                    modelSelection: selection, projectID: projectID,
                    environmentID: environmentID,
                    machineName: launchMachine?.isLocal == false ? launchMachine?.name : nil,
                    projectName: target == nil ? selectedProject?.title : nil
                )
                reference = receipt.reference
                if target == nil { threadProjectID = receipt.projectID }
                threadModel = receipt.modelSelection ?? threadModel
                nextModel = nil
                if !attachments.isEmpty {
                    previews[receipt.runId] = attachments.compactMap { Self.thumbnail($0.data) }
                }
                let message = ChatMessage(
                    id: request.uuidString, runId: receipt.runId, position: .max, isUser: true, text: text, date: .now,
                    previews: previews[receipt.runId] ?? []
                )
                pendingMessage = message
                messages.append(message)
                status = receipt.status
                activeRunId = receipt.runId
                retrySendAfterLaunch = false
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
                let sent = Set(attachments.map(\.id))
                images.removeAll { sent.contains($0.id) }
                persist()
                if stopping {
                    await interrupt(receipt.reference, runId: receipt.runId, version: generation)
                } else {
                    refresh(receipt.reference, force: true)
                }
            } catch {
                stopping = false
                if case T3Error.serverUnavailable = error { retrySendAfterLaunch = true }
                showError(error)
                if case T3Error.uncertainDelivery = error, let target { refresh(target, force: true) }
            }
            submitting = false
            focusRequest += 1
        }
    }

    func stop() {
        guard canStop else { return }
        stopping = true
        // A first send may not have a thread or run ID until T3 acknowledges delivery.
        guard !submitting, let reference else { return }
        let version = generation
        let runId = activeRunId
        Task { await interrupt(reference, runId: runId, version: version) }
    }

    func isQuestionOptionSelected(_ option: T3Question.Option) -> Bool {
        guard let question = activeQuestion else { return false }
        return questionDrafts[question.id]?.selectedOptionValues.contains(option.answerValue) == true
    }

    func selectQuestionOption(_ option: T3Question.Option) {
        guard let question = activeQuestion, !answeringQuestion else { return }
        var draft = questionDrafts[question.id] ?? T3QuestionDraft()
        let value = option.answerValue
        if question.allowsMultiple {
            if let index = draft.selectedOptionValues.firstIndex(of: value) {
                draft.selectedOptionValues.remove(at: index)
            } else {
                draft.selectedOptionValues.append(value)
            }
        } else {
            draft.selectedOptionValues = [value]
        }
        draft.customAnswer = ""
        questionDrafts[question.id] = draft
        questionError = nil
        focusRequest += 1
    }

    func selectQuestionOption(at index: Int) -> Bool {
        guard composerText.isEmpty, let question = activeQuestion,
            question.options.indices.contains(index) else { return false }
        selectQuestionOption(question.options[index])
        return true
    }

    func setComposerText(_ text: String) {
        guard let question = activeQuestion else {
            draft = text
            return
        }
        guard question.allowsCustom, !answeringQuestion else { return }
        var answer = questionDrafts[question.id] ?? T3QuestionDraft()
        answer.customAnswer = text
        if question.initialAnswer != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answer.selectedOptionValues = []
        }
        questionDrafts[question.id] = answer
        questionError = nil
    }

    func confirmOrSend() {
        if activeQuestion != nil {
            confirmQuestion()
        } else {
            send()
        }
    }

    func confirmQuestion() {
        guard !answeringQuestion, let request = pendingQuestion, let question = activeQuestion else {
            return
        }
        guard T3QuestionAnswerBuilder.resolve(
            question, draft: questionDrafts[question.id]
        ) != nil else {
            questionError = "Pick an answer to continue."
            return
        }
        if !isLastQuestion {
            questionIndex += 1
            questionError = nil
            focusRequest += 1
            return
        }
        guard let answers = T3QuestionAnswerBuilder.build(
            questions: request.questions, drafts: questionDrafts
        ), let reference else { return }
        let summary = Self.questionSummary(request.questions, drafts: questionDrafts)
        answeringQuestion = true
        questionError = nil
        Task {
            do {
                try await client.answer(request, answers: answers, thread: reference)
                answeredQuestionSummary = summary
                resetQuestion()
                status = .running
                dismissedStatusNotice = nil
                focusRequest += 1
                refresh(reference, force: true)
            } catch {
                answeringQuestion = false
                questionError = "Float couldn't send that answer. Try again."
            }
        }
    }

    private func interrupt(_ reference: ThreadReference, runId: String?, version: Int) async {
        do {
            let accepted = try await client.stop(reference, runId: runId)
            guard generation == version else { return }
            stopAcknowledged = accepted && status == .running
        } catch {
            guard generation == version else { return }
            showError(error)
        }
        stopping = false
        refresh(reference, force: true)
    }

    func loadOlder() {
        guard let reference, let before = earliest, !loadingOlder else { return }
        let version = generation
        loadingOlder = true
        Task {
            defer { if generation == version { loadingOlder = false } }
            do {
                let page = try await client.read(reference, before: before)
                try await expandLongMessages(page, reference: reference, generation: version)
                guard generation == version else { return }
                earliest = page.earlierPosition
                hasOlderMessages = earliest != nil
                merge(page)
            } catch {
                guard generation == version else { return }
                showError(error)
            }
        }
    }

    func addImageFiles(_ urls: [URL]) {
        for url in urls {
            guard images.count < ImageAttachment.maxCount else {
                setNotice("Attach up to eight images per message.", kind: .input)
                break
            }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ImageAttachment.maxBytes else {
                    setNotice("Images must be 10 MB or smaller.", kind: .input)
                    continue
                }
                addImage(try Data(contentsOf: url), name: url.lastPathComponent)
            } catch {
                setNotice("Float couldn't open \(url.lastPathComponent).", kind: .input)
            }
        }
    }

    func pasteImages(_ pasteboard: NSPasteboard) -> Bool {
        if let files = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !files.isEmpty {
            let imageFiles = files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            if !imageFiles.isEmpty {
                addImageFiles(imageFiles)
                return true
            }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, .init("public.jpeg"),
            .init("com.compuserve.gif"), .init("org.webmproject.webp")] {
            if let data = pasteboard.data(forType: type) {
                addImage(data, name: "Pasted image")
                return true
            }
        }
        return false
    }

    func removeImage(_ id: UUID) {
        images.removeAll { $0.id == id }
        if noticeKind == .input { clearNotice() }
    }

    func dismissNotice() {
        retrySendAfterLaunch = false
        clearNotice()
        if status == .waiting || status == .failed { dismissedStatusNotice = status }
    }

    func close() async { await client.close() }

    private func refresh(_ reference: ThreadReference, force: Bool) {
        guard force else { return }
        watcher?.cancel()
        if messages.isEmpty { loading = true }
        let version = generation
        watcher = Task {
            var connectionFailures = 0
            defer {
                if generation == version && !Task.isCancelled {
                    watcher = nil
                    loading = false
                }
            }
            repeat {
                do {
                    let page = try await client.read(reference)
                    try Task.checkCancellation()
                    try await expandLongMessages(page, reference: reference, generation: version)
                    guard generation == version, !Task.isCancelled else { return }
                    merge(page)
                    if !receivedFirstPage {
                        receivedFirstPage = true
                        earliest = page.earlierPosition
                        hasOlderMessages = earliest != nil
                    }
                    try await updateQuestion(from: page, thread: reference)
                    status = page.thread.pendingRequestCount > 0 ? .waiting : page.thread.status
                    activeRunId = page.recentRuns?.first { $0.status == .running }?.runId
                    updateFailure(from: page)
                    if status != .running { stopAcknowledged = false }
                    title = page.thread.title
                    threadProjectID = page.thread.projectId
                    threadModel = page.thread.modelSelection ?? threadModel
                    loading = false
                    connectionFailures = 0
                    if needsT3 || noticeKind == .connection {
                        clearNotice()
                        needsT3 = false
                    }
                    if status != .running && status != .waiting { return }
                } catch {
                    guard generation == version && !Task.isCancelled else { return }
                    showError(error)
                    loading = false
                    let serverUnavailable: Bool
                    if case T3Error.serverUnavailable = error {
                        serverUnavailable = true
                    } else {
                        serverUnavailable = false
                    }
                    guard serverUnavailable || Self.isRemoteMachineUnavailable(error) else { return }
                    connectionFailures += 1
                    if connectionFailures >= 10 && status != .running && status != .waiting { return }
                }
                let delay: Duration
                if !visible || connectionFailures > 0 {
                    delay = .seconds(3)
                } else {
                    delay = status == .running ? .milliseconds(400) : .milliseconds(850)
                }
                try? await Task.sleep(for: delay)
            } while !Task.isCancelled
        }
    }

    private func merge(_ snapshot: ThreadSnapshot) {
        var merged = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for item in snapshot.items where item.type == "user_message" || item.type == "assistant_message" {
            let isUser = item.type == "user_message"
            let expanded = expandedText[item.id]
            let text = expanded?.timestamp == item.updatedAt ? expanded?.text ?? "" : item.text ?? ""
            let attachments = isUser ? item.runId.flatMap { previews[$0] } ?? [] : []
            guard !text.isEmpty || !attachments.isEmpty else { continue }
            if isUser, let pending = pendingMessage, pending.runId == item.runId {
                merged.removeValue(forKey: pending.id)
                pendingMessage = nil
            }
            merged[item.id] = ChatMessage(
                id: item.id, runId: item.runId, position: item.position, isUser: isUser, text: text,
                date: item.date, previews: attachments
            )
        }
        let updated = merged.values.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id < $1.id
        }
        if updated != messages { messages = updated }
    }

    private func updateQuestion(
        from snapshot: ThreadSnapshot, thread: ThreadReference
    ) async throws {
        guard snapshot.thread.pendingRequestCount > 0 else {
            resetQuestion()
            return
        }
        let question = try await client.pendingQuestion(thread)
        guard question?.requestId != pendingQuestion?.requestId else { return }
        guard let question else {
            resetQuestion()
            return
        }
        pendingQuestion = question
        questionIndex = 0
        questionDrafts = Dictionary(uniqueKeysWithValues: question.questions.map {
            ($0.id, T3QuestionDraft(customAnswer: $0.allowsCustom ? $0.initialAnswer : nil))
        })
        questionError = nil
        focusRequest += 1
    }

    private func resetQuestion() {
        pendingQuestion = nil
        questionIndex = 0
        questionDrafts = [:]
        questionError = nil
        answeringQuestion = false
    }

    private static func questionSummary(
        _ questions: [T3Question], drafts: [String: T3QuestionDraft]
    ) -> String {
        let values = questions.compactMap { question -> String? in
            let draft = drafts[question.id]
            let custom = draft?.customAnswer
            let usesCustom = question.allowsCustom && (
                question.initialAnswer != nil && custom != nil
                    || custom?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            )
            if usesCustom {
                return custom.map(compactAnswer)
            }
            let labels = (draft?.selectedOptionValues ?? []).compactMap { value in
                question.options.first(where: { $0.answerValue == value })?.label
            }
            if !labels.isEmpty { return labels.joined(separator: ", ") }
            return question.isRequired ? nil : "Skipped"
        }
        return values.joined(separator: " · ")
    }

    private static func compactAnswer(_ answer: String) -> String {
        answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func expandLongMessages(
        _ snapshot: ThreadSnapshot, reference: ThreadReference, generation version: Int
    ) async throws {
        for item in snapshot.items where item.textTruncated && expandedText[item.id]?.timestamp != item.updatedAt {
            let text = try await client.readRemainder(reference, item: item)
            guard generation == version, !Task.isCancelled else { return }
            expandedText[item.id] = (item.updatedAt, text)
        }
    }

    private func showError(_ error: Error) {
        let detail = error.localizedDescription
        if Self.isRemoteMachineUnavailable(error),
            let machine = reference?.machineName
                ?? selectedMachine.flatMap({ $0.isLocal ? nil : $0.name }) {
            needsT3 = false
            setNotice(
                "Reconnect it in T3 Code to continue.",
                title: "\(machine) is offline", kind: .connection, detail: detail
            )
        } else if case T3Error.serverUnavailable = error {
            needsT3 = true
            setNotice(
                retrySendAfterLaunch
                    ? "Your draft is saved. Launch T3 and Float sends it."
                    : "Launch T3 to reconnect Float.",
                title: "T3 Code isn't running", kind: .connection, detail: detail, canLaunchT3: true
            )
        } else if case T3Error.cliUnavailable = error {
            needsT3 = true
            setNotice(
                "Float couldn't find the local T3 command.", title: "Can't reach T3",
                kind: .connection, detail: detail, canLaunchT3: true
            )
        } else if case T3Error.authorization = error {
            setNotice(
                "T3 Code couldn't authorize Float.", title: "Can't reach T3",
                kind: .connection, detail: detail
            )
        } else if case T3Error.localAddressRequired = error {
            setNotice(
                "T3 Code's local server address isn't valid.", title: "Can't reach T3",
                kind: .connection, detail: detail
            )
        } else if case T3Error.uncertainDelivery = error {
            setNotice("T3 Code may have received that message. Check the thread before sending again.",
                kind: .run, detail: detail)
        } else if Self.isProjectUnavailable(error) {
            setNotice(
                "That project is no longer available in T3. Choose another project or No project and send again.",
                title: "Project unavailable", kind: .run, detail: detail
            )
            reloadProjects()
        } else {
            setNotice(Self.friendlyError(detail), kind: .run, detail: detail)
        }
    }

    private static func isProjectUnavailable(_ error: Error) -> Bool {
        guard case T3Error.tool(let message) = error else { return false }
        let lower = message.lowercased()
        return lower.contains("project was not found")
            || lower.contains("project is missing")
            || (lower.contains("workspace") && lower.contains("does not exist"))
    }

    private static func isRemoteMachineUnavailable(_ error: Error) -> Bool {
        guard case T3Error.tool(let message) = error else { return false }
        let lower = message.lowercased()
        return lower.contains("did not answer")
            || lower.contains("stopped answering")
            || lower.contains("link to") && lower.contains("expired")
            || lower.contains("is not linked")
            || lower.contains("no longer accepts this link")
            || lower.contains("linked environment") && lower.contains("turned off")
    }

    private func updateFailure(from snapshot: ThreadSnapshot) {
        guard status == .failed else {
            failureReason = nil
            failureDetail = nil
            return
        }
        let failedRun = snapshot.recentRuns?.first { $0.status == .failed }
        let raw = failedRun?.failureReason ?? snapshot.items.reversed().first(where: {
            $0.type == "error" && (failedRun == nil || $0.runId == failedRun?.runId)
        })?.text
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failureReason = nil
            failureDetail = nil
            return
        }
        failureReason = Self.friendlyFailure(raw)
        failureDetail = raw
    }

    private static func friendlyError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("provider instance \"claudeagent\" is disabled") {
            return "Claude Code is disabled in T3 Code. Enable it in T3 Settings → Providers."
        }
        if lower.contains("enable a supported provider") || lower.contains("no enabled models") {
            return "No supported model is enabled in T3 Code."
        }
        if lower.contains("rate limit") || lower.contains("too many requests") {
            return "The model provider is rate-limited. Try again shortly."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "T3 Code timed out waiting for the model."
        }
        if lower.contains("sign in") || lower.contains("authentication") || lower.contains("unauthorized") {
            return "T3 Code needs you to sign in again."
        }
        return "Something went wrong in T3 Code."
    }

    private static func friendlyFailure(_ raw: String) -> String {
        let friendly = friendlyError(raw)
        if friendly != "Something went wrong in T3 Code." { return friendly }
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = compact.lowercased()
        let looksLikeEnvelope = compact.hasPrefix("{") || compact.hasPrefix("[")
            || lower.contains("\"jsonrpc\"") || lower.contains("mcp error")
            || lower.contains("structuredcontent") || lower.contains("\nat ")
            || lower.contains("traceback") || lower.contains("stack trace")
        if !looksLikeEnvelope, compact.count <= 240, !compact.contains("\n") {
            return compact
        }
        return "T3 Code reported an internal error."
    }

    private func setNotice(
        _ text: String, title: String? = nil, kind: NoticeKind, detail: String? = nil,
        canLaunchT3: Bool = false
    ) {
        notice = text
        noticeTitle = title
        noticeKind = kind
        noticeDetail = detail == text ? nil : detail
        self.canLaunchT3 = canLaunchT3
    }

    private func clearNotice() {
        notice = nil
        noticeTitle = nil
        noticeKind = nil
        noticeDetail = nil
        canLaunchT3 = false
    }

    private func persist() {
        defaults.set(reference.flatMap { try? JSONEncoder().encode($0) }, forKey: "thread")
        defaults.set(previews.isEmpty ? nil : try? PropertyListEncoder().encode(previews), forKey: "previews")
    }

    private func selectionForSend(_ selection: T3ModelSelection) -> T3ModelSelection {
        guard let model = modelProviders.flatMap(\.models).first(where: {
            $0.selection.matches(selection)
        })
        else {
            return T3ModelSelection(instanceId: selection.instanceId, model: selection.model)
        }
        return model.selection(withEffort: effort(for: model))
    }

    private func reloadFavourites() async {
        if let saved = try? await favouritesStore.load() {
            favouriteModelKeys = saved
        }
    }

    private func addImage(_ data: Data, name: String) {
        guard images.count < ImageAttachment.maxCount else {
            setNotice("Attach up to eight images per message.", kind: .input)
            return
        }
        guard data.count <= ImageAttachment.maxBytes else {
            setNotice("Images must be 10 MB or smaller.", kind: .input)
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String)
        else {
            setNotice("Float couldn't read that image.", kind: .input)
            return
        }
        let payload: (data: Data, type: UTType)
        if [UTType.png, .jpeg, .gif, .webP].contains(type) {
            payload = (data, type)
        } else if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: 4_096, kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary), let png = Self.encode(image, as: .png) {
            payload = (png, .png)
        } else {
            setNotice("Float couldn't convert that image.", kind: .input)
            return
        }
        guard payload.data.count <= ImageAttachment.maxBytes else {
            setNotice("The converted image exceeds T3's 10 MB limit.", kind: .input)
            return
        }
        let ext = payload.type.preferredFilenameExtension ?? "png"
        let finalName = URL(fileURLWithPath: name).pathExtension.isEmpty
            ? "\(name).\(ext)" : URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + ".\(ext)"
        images.append(ImageAttachment(
            name: String(finalName.prefix(255)), mimeType: payload.type.preferredMIMEType ?? "image/png",
            data: payload.data
        ))
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        else { return nil }
        return encode(image, as: .jpeg)
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        return CGImageDestinationFinalize(writer) ? output as Data : nil
    }
}
