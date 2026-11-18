import AppKit
import FloatCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
    @Published private var questionFlow: T3QuestionFlow?
    @Published private(set) var approvalPreview: String?
    @Published private(set) var approvalAccessEnabled = false
    @Published private(set) var approvalAccessBusy = false
    @Published private(set) var approvalAccessError: String?
    @Published private(set) var pendingApprovals: [ApprovalRequest] = []
    @Published private(set) var respondingToApproval = false
    @Published private(set) var approvalError: String?
    @Published private(set) var approvalSummary: String?
    private var approvalMaintenance: Task<Void, Never>?
    private var nextApprovalRead = Date.distantPast
    private var answeredApprovalIDs: Set<String> = []
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
    @Published private var loadedThreadProject: T3Project?
    @Published private var cachedProjectName: String?
    private var projectsEnvironmentID: String?
    private var pendingLaunchMachine: T3Machine?

    struct ProjectLookup: Equatable {
        let threadID: String
        let projectID: String
        let environmentID: String?
    }
    @Published private(set) var threadMachineDisconnected = false
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
    @Published private var modelEfforts: T3ModelEfforts
    private var pickedCatalogModel: T3Model?
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
        modelEfforts = T3ModelEfforts(values: defaults.dictionary(forKey: "modelEfforts") as? [String: String] ?? [:])
        draft = defaults.string(forKey: "draft") ?? ""
        selectedProjectID = defaults.string(forKey: "preferredProjectID")
        selectedMachineID = defaults.string(forKey: "preferredMachineID")
        if let data = defaults.data(forKey: "preferredModel") {
            savedModel = try? JSONDecoder().decode(T3ModelSelection.self, from: data)
        }
        if let data = defaults.data(forKey: "thread"),
            let stored = try? JSONDecoder().decode(ThreadReference.self, from: data) {
            reference = stored
            threadProjectID = defaults.string(forKey: "threadProjectID")
            cachedProjectName = defaults.string(forKey: "threadProjectName")
                ?? (threadProjectID == nil ? stored.projectName : nil)
            title = defaults.string(forKey: "threadTitle")
            if let encoded = defaults.data(forKey: "previews") {
                previews = (try? PropertyListDecoder().decode([String: [Data]].self, from: encoded)) ?? [:]
            }
        }
    }

    var groupedMessages: [ChatMessage] { ChatMessage.groupReplies(in: messages) }

    var hasConversation: Bool { reference != nil || submitting }
    var hasTrayNotice: Bool { notice != nil && noticeKind != .input }
    var statusNoticeDismissed: Bool { dismissedStatusNotice == status }
    var pendingQuestion: T3PendingQuestionRequest? { questionFlow?.request }
    var questionIndex: Int { questionFlow?.index ?? 0 }
    var activeQuestion: T3Question? { questionFlow?.activeQuestion }
    var activeApproval: ApprovalRequest? { pendingApprovals.first }

    var questionCanAdvance: Bool { questionFlow?.canAdvance == true }
    var isLastQuestion: Bool { questionFlow?.isLast ?? true }
    var composerText: String {
        guard activeQuestion != nil else { return draft }
        return questionFlow?.composerText ?? ""
    }
    var composerPlaceholder: String {
        if let question = activeQuestion {
            return question.allowsCustom ? "Or type your own answer…" : "Pick an answer above…"
        }
        if activeApproval != nil || approvalPreview != nil { return "Waiting on your approval…" }
        return hasConversation ? "Ask a follow-up…" : "Ask anything, or paste a screenshot…"
    }
    var composerEditable: Bool { activeQuestion?.allowsCustom != false }
    var showsStop: Bool { submitting || (status == .running && !stopAcknowledged) || stopping }
    var canStop: Bool { showsStop && !stopping }
    var canSend: Bool {
        !submitting && !stopping && !loading && status != .running && status != .waiting &&
            (reference != nil || (!loadingProjects && (!loadingModels || !models.isEmpty))) &&
            (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var selectedModel: T3ModelSelection? {
        if let threadSelection = nextModel ?? threadModel, reference != nil { return threadSelection }
        if let pickedCatalogModel, pickedCatalogModel.selection.matches(savedModel) {
            return pickedCatalogModel.selection
        }
        return T3Model.preferred(
            in: models, saved: savedModel, favourites: favouriteModelKeys
        )?.selection
    }

    var selectedCatalogModel: T3Model? {
        models.first { $0.selection.matches(selectedModel) }
            ?? pickedCatalogModel.flatMap { $0.selection.matches(selectedModel) ? $0 : nil }
    }

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

    var threadHeaderEnvironmentID: String? {
        if let reference { return reference.environmentID }
        return pendingLaunchMachine.flatMap { $0.isLocal ? nil : $0.id }
    }

    var threadProject: T3Project? {
        if let loadedThreadProject, loadedThreadProject.id == threadProjectID {
            return loadedThreadProject
        }
        guard threadHeaderEnvironmentID == projectsEnvironmentID else { return nil }
        return projects.first { $0.id == threadProjectID }
    }

    var threadProjectLabel: String? {
        if let project = threadProject {
            return client.isScratchProject(project, environmentID: threadHeaderEnvironmentID) ? nil : project.title
        }
        return cachedProjectName
    }

    var threadMachineName: String? {
        guard let environmentID = threadHeaderEnvironmentID else { return nil }
        return machines.first { $0.id == environmentID }?.name ?? reference?.machineName ?? pendingLaunchMachine?.name
    }

    var threadProjectLookup: ProjectLookup? {
        guard let reference, let projectID = threadProjectID, !needsT3, !threadMachineDisconnected else { return nil }
        return ProjectLookup(threadID: reference.threadId, projectID: projectID, environmentID: reference.environmentID)
    }

    func loadThreadProject() async {
        guard let lookup = threadProjectLookup, loadedThreadProject?.id != lookup.projectID,
              threadProject?.faviconPath == nil, threadProject?.projectIcon == nil else { return }
        for attempt in 0..<3 {
            guard !Task.isCancelled, lookup == threadProjectLookup else { return }
            if let project = try? await client.project(lookup.projectID, environmentID: lookup.environmentID) {
                guard !Task.isCancelled, lookup == threadProjectLookup else { return }
                loadedThreadProject = project
                cachedProjectName = threadProjectLabel
                persistThreadMetadata()
                return
            }
            if attempt < 2 { try? await Task.sleep(for: .seconds(1)) }
        }
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
                try await loadModelCatalogue()
            } catch {
                modelCatalogFailed = true
            }
        }
    }

    private func loadModelCatalogue() async throws {
        let catalogue = try await client.modelCatalogue()
        await reloadFavourites()
        let saved = savedModel
        var savedSearchMatch: T3Model?
        if let saved,
            let provider = catalogue.providers.first(where: { $0.id == saved.instanceId }),
            provider.enabled, provider.omittedModels > 0,
            !provider.models.contains(where: { $0.selection.matches(saved) }) {
            // T3 can omit a model from the initial list while still returning it in search.
            let results = try? await client.modelCatalogue(search: saved.model)
            savedSearchMatch = results?.available.first { $0.selection.matches(saved) }
            if results == nil { savedSearchMatch = pickedCatalogModel }
        }
        if savedModel == saved { pickedCatalogModel = savedSearchMatch }
        models = catalogue.available
        modelProviders = catalogue.providers
    }

    func selectModel(_ model: T3Model) {
        guard canChooseModel else { return }
        let selection = model.selection
        pickedCatalogModel = model
        savedModel = selection
        if reference != nil { nextModel = selection.matches(threadModel) ? nil : selection }
        defaults.set(try? JSONEncoder().encode(selection), forKey: "preferredModel")
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
                projectsEnvironmentID = environmentID
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
        modelEfforts.value(for: model)
    }

    func setEffort(_ value: String, for model: T3Model) {
        guard modelEfforts.set(value, for: model) else { return }
        defaults.set(modelEfforts.values, forKey: "modelEfforts")
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

    func startApprovalMaintenance() {
        guard approvalMaintenance == nil else { return }
        approvalMaintenance = Task { [weak self] in
            repeat {
                await self?.maintainApprovalAccess()
                try? await Task.sleep(for: .seconds(3_600))
            } while !Task.isCancelled && self != nil
        }
    }

    private func maintainApprovalAccess() async {
        guard !approvalAccessBusy else { return }
        do {
            let enabled = try await client.approvals.maintain()
            if approvalAccessEnabled && !enabled {
                if approvalPreview == nil { approvalPreview = activeApproval?.summary }
                pendingApprovals = []
            }
            approvalAccessEnabled = enabled
        } catch {
            // Keep the last known state if Keychain or the local CLI is
            // temporarily unavailable. The next refresh can retry.
        }
    }

    func enableApprovals() {
        guard let reference, reference.environmentID == nil, approvalPreview != nil else { return }
        setApprovalAccess(enabled: true)
    }

    func disableApprovals() {
        setApprovalAccess(enabled: false)
    }

    private func setApprovalAccess(enabled: Bool) {
        guard !approvalAccessBusy else { return }
        approvalAccessError = nil
        approvalError = nil
        approvalAccessBusy = true
        Task {
            defer { approvalAccessBusy = false }
            do {
                if enabled { try await client.approvals.enable() }
                else { try await client.approvals.disable() }
                approvalAccessEnabled = enabled
                nextApprovalRead = .distantPast
                if !enabled { pendingApprovals = [] }
                if let reference { refresh(reference, force: true) }
            } catch {
                approvalAccessError = (error as? ApprovalAccessError)?.errorDescription
                    ?? (enabled ? "Float couldn't turn on approvals. Check that T3 Code is running and try again."
                                : "Float couldn't revoke its approvals key. Try again from the menu bar.")
            }
        }
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
        loadedThreadProject = nil
        cachedProjectName = nil
        pendingLaunchMachine = nil
        threadMachineDisconnected = false
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
        approvalPreview = nil
        approvalAccessError = nil
        approvalError = nil
        approvalSummary = nil
        pendingApprovals = []
        respondingToApproval = false
        answeredApprovalIDs = []
        nextApprovalRead = .distantPast
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
                try await loadModelCatalogue()
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
        let launchProject = target == nil ? selectedProject : nil
        let projectID = launchProject?.id
        let selection = selectedModel.map(selectionForSend)
        clearNotice()
        answeredQuestionSummary = nil
        needsT3 = false
        retrySendAfterLaunch = false
        thinkingStartedAt = .now
        if target == nil {
            prepareLaunchHeader(project: launchProject, machine: launchMachine, text: text,
                                attachmentName: attachments.first?.name)
        }
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
                    projectName: launchProject?.title
                )
                reference = receipt.reference
                pendingLaunchMachine = nil
                if target == nil, receipt.projectID != threadProjectID {
                    threadProjectID = receipt.projectID
                    loadedThreadProject = nil
                }
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
                if target == nil {
                    threadProjectID = nil
                    loadedThreadProject = nil
                    cachedProjectName = nil
                    pendingLaunchMachine = nil
                    title = nil
                }
                if case T3Error.serverUnavailable = error { retrySendAfterLaunch = true }
                showError(error)
                if case T3Error.uncertainDelivery = error, let target { refresh(target, force: true) }
            }
            submitting = false
            focusRequest += 1
        }
    }

    private func prepareLaunchHeader(project: T3Project?, machine: T3Machine?, text: String, attachmentName: String?) {
        pendingLaunchMachine = machine
        threadProjectID = project?.id
        loadedThreadProject = project
        cachedProjectName = project?.title
        title = T3Client.launchTitle(for: text, attachmentName: attachmentName)
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
        questionFlow?.isSelected(option) == true
    }

    func selectQuestionOption(_ option: T3Question.Option) {
        guard !answeringQuestion, activeQuestion != nil else { return }
        questionFlow?.select(option)
        questionError = nil
        focusRequest += 1
    }

    func selectQuestionOption(at index: Int) -> Bool {
        guard !answeringQuestion, composerText.isEmpty, let question = activeQuestion,
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
        questionFlow?.setCustomAnswer(text)
        questionError = nil
    }

    @discardableResult func goBackQuestion() -> Bool {
        guard !answeringQuestion, questionFlow?.goBack() == true else { return false }
        questionError = nil
        focusRequest += 1
        return true
    }

    func confirmOrSend() {
        if activeQuestion != nil {
            confirmQuestion()
        } else {
            send()
        }
    }

    func confirmQuestion() {
        guard !answeringQuestion, var flow = questionFlow, flow.activeQuestion != nil else { return }
        switch flow.confirm() {
        case nil:
            questionError = "Pick an answer to continue."
        case .advanced:
            questionFlow = flow
            questionError = nil
            focusRequest += 1
        case .submit(let answers):
            guard let reference else { return }
            let request = flow.request
            let summary = Self.questionSummary(request.questions, drafts: flow.drafts)
            let version = generation
            answeringQuestion = true
            questionError = nil
            Task {
                do {
                    try await client.answer(request, answers: answers, thread: reference)
                    guard generation == version else { return }
                    answeredQuestionSummary = summary
                    if pendingQuestion?.requestId == request.requestId {
                        resetQuestion()
                        status = .running
                        dismissedStatusNotice = nil
                        focusRequest += 1
                    }
                    refresh(reference, force: true)
                } catch {
                    guard generation == version, pendingQuestion?.requestId == request.requestId else { return }
                    answeringQuestion = false
                    questionError = "Float couldn't send that answer. Try again."
                }
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

    func close() async {
        approvalMaintenance?.cancel()
        await client.close()
    }

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
                    applyThreadMetadata(page.thread)
                    try await expandLongMessages(page, reference: reference, generation: version)
                    guard generation == version, !Task.isCancelled else { return }
                    merge(page)
                    if !receivedFirstPage {
                        receivedFirstPage = true
                        earliest = page.earlierPosition
                        hasOlderMessages = earliest != nil
                    }
                    updateApprovalPreview(from: page)
                    try await updateQuestion(from: page, thread: reference)
                    guard generation == version, !Task.isCancelled else { return }
                    status = page.thread.pendingRequestCount > 0 ? .waiting : page.thread.status
                    await updateApprovals(from: page, thread: reference, generation: version)
                    guard generation == version, !Task.isCancelled else { return }
                    activeRunId = page.recentRuns?.first { $0.status == .running }?.runId
                    updateFailure(from: page)
                    if status != .running { stopAcknowledged = false }
                    loading = false
                    connectionFailures = 0
                    threadMachineDisconnected = false
                    if needsT3 || noticeKind == .connection {
                        clearNotice()
                        needsT3 = false
                    }
                    if status != .running && status != .waiting && page.thread.titleRegeneration == nil { return }
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

    private func applyThreadMetadata(_ thread: ThreadSnapshot.Thread) {
        let projectChanged = threadProjectID != thread.projectId
        let serverTitle = thread.title.isEmpty ? nil : thread.title
        let titleChanged = serverTitle.map { $0 != title } ?? false
        if projectChanged {
            // A scratch thread can move to a project. Avoid carrying the
            // previous project's identity over to the new workspace.
            if threadProjectID != nil { cachedProjectName = nil }
            threadProjectID = thread.projectId
            loadedThreadProject = nil
        }
        if let serverTitle, titleChanged { title = serverTitle }
        threadModel = thread.modelSelection ?? threadModel
        if projectChanged || titleChanged { persistThreadMetadata() }
    }

    private func merge(_ snapshot: ThreadSnapshot) {
        var merged = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for item in snapshot.items where item.isChatMessageCandidate {
            let isUser = item.type == "user_message"
            let expanded = expandedText[item.id]
            let raw = expanded?.timestamp == item.updatedAt ? expanded?.text : nil
            let text = item.chatText(expandedText: raw) ?? ""
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

    private func updateApprovalPreview(from snapshot: ThreadSnapshot) {
        let pending = snapshot.thread.pendingRequestCount > 0
            ? snapshot.items.first(where: \.isPendingApproval) : nil
        let preview = pending.map { item in
            if item.text == "Ran command" { return "The agent wants to run a command." }
            return item.text ?? "Review this request in T3."
        }
        if approvalPreview != preview { approvalPreview = preview }
    }

    private func updateApprovals(from snapshot: ThreadSnapshot, thread: ThreadReference, generation version: Int) async {
        guard snapshot.thread.pendingRequestCount > 0, thread.environmentID == nil, approvalAccessEnabled else {
            if !pendingApprovals.isEmpty { pendingApprovals = [] }
            return
        }
        guard !approvalAccessBusy, !respondingToApproval, Date.now >= nextApprovalRead else { return }
        nextApprovalRead = Date.now.addingTimeInterval(2)
        do {
            let requests = try await client.pendingApprovals(thread)
            guard generation == version, !Task.isCancelled, approvalAccessEnabled, !approvalAccessBusy else { return }
            let pending = requests.filter { !answeredApprovalIDs.contains($0.id) }
            if pending != pendingApprovals {
                if pending.first?.id != activeApproval?.id { approvalError = nil }
                pendingApprovals = pending
            }
            if pending.isEmpty, !requests.isEmpty, pendingQuestion == nil {
                approvalPreview = nil
                status = .running
            }
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            if loseApprovalAccess(ifRejected: error) { return }
            if activeApproval == nil, approvalPreview != nil {
                approvalError = "Float couldn't load the approval. You can open it in T3."
            }
        }
    }

    private func loseApprovalAccess(ifRejected error: Error) -> Bool {
        guard case ApprovalAccessError.rejected = error else { return false }
        approvalAccessEnabled = false
        if approvalPreview == nil, let activeApproval {
            approvalPreview = activeApproval.summary
        }
        pendingApprovals = []
        approvalAccessError = "T3 no longer accepts Float’s approvals key. Turn it on again to continue here."
        return true
    }

    @discardableResult func allowVisibleApproval() -> Bool {
        guard activeQuestion == nil, approvalAccessEnabled,
              let request = activeApproval, request.allowedDecisions.contains(.allow) else { return false }
        respondToApproval(.allow, requestID: request.id)
        return true
    }

    func respondToApproval(_ decision: ApprovalDecision, requestID: String) {
        guard activeQuestion == nil, !respondingToApproval, !approvalAccessBusy, approvalAccessEnabled,
              let request = activeApproval, request.id == requestID, request.allowedDecisions.contains(decision),
              let reference, reference.environmentID == nil else { return }
        let version = generation
        respondingToApproval = true
        approvalError = nil
        Task {
            defer {
                if version == generation { respondingToApproval = false }
            }
            do {
                try await client.respondToApproval(request, decision: decision, thread: reference)
                guard generation == version else { return }
                answeredApprovalIDs.insert(request.id)
                approvalSummary = "\(decision == .allow ? "Allowed" : "Denied"): \(request.summary)"
                pendingApprovals.removeAll { $0.id == request.id }
                approvalPreview = nil
                if pendingApprovals.isEmpty, pendingQuestion == nil { status = .running }
                nextApprovalRead = .distantPast
                refresh(reference, force: true)
            } catch {
                guard generation == version else { return }
                if !loseApprovalAccess(ifRejected: error) {
                    approvalError = "Float couldn't confirm the decision. Check the request in T3."
                }
            }
        }
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
        questionFlow = T3QuestionFlow(request: question)
        answeringQuestion = false
        questionError = nil
        focusRequest += 1
    }

    private func resetQuestion() {
        questionFlow = nil
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
        for item in snapshot.items where item.isChatMessageCandidate && item.textTruncated
            && expandedText[item.id]?.timestamp != item.updatedAt {
            let text = try await client.readRemainder(reference, item: item)
            guard generation == version, !Task.isCancelled else { return }
            expandedText[item.id] = (item.updatedAt, text)
        }
    }

    private func showError(_ error: Error) {
        let detail = error.localizedDescription
        if Self.isRemoteMachineUnavailable(error),
            let machine = threadMachineName
                ?? selectedMachine.flatMap({ $0.isLocal ? nil : $0.name })
                ?? (reference?.environmentID == nil ? nil : "Thread machine") {
            needsT3 = false
            threadMachineDisconnected = reference?.environmentID != nil
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
        persistThreadMetadata()
        defaults.set(previews.isEmpty ? nil : try? PropertyListEncoder().encode(previews), forKey: "previews")
    }

    private func persistThreadMetadata() {
        defaults.set(threadProjectID, forKey: "threadProjectID")
        defaults.set(threadProjectLabel, forKey: "threadProjectName")
        defaults.set(title, forKey: "threadTitle")
    }

    private func selectionForSend(_ selection: T3ModelSelection) -> T3ModelSelection {
        guard let model = selectedCatalogModel, model.selection.matches(selection) else {
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
