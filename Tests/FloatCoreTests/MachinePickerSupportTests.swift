import Testing

@testable import FloatCore

private func machine(
    _ id: String, name: String, kind: T3Machine.Kind = .linked,
    status: T3Machine.Status = .reachable
) -> T3Machine {
    T3Machine(id: id, name: name, kind: kind, status: status)
}

private func machineProject(_ id: String) -> T3Project {
    T3Project(id: id, title: id, workspaceRoot: "/tmp/\(id)")
}

@Test func machineListPutsThisMacFirstThenSortsLinkedMachines() {
    let local = machine("local", name: "This Mac", kind: .local)
    let mini = machine("mini", name: "Dylan’s Mac mini")
    let laptop = machine("laptop", name: "Build laptop")

    #expect(T3MachinePicker.ordered([mini, local, laptop]) == [local, laptop, mini])
}

@Test func offlineMachinesCannotRemainSelected() {
    let local = machine("local", name: "This Mac", kind: .local)
    let online = machine("online", name: "Online")
    let offline = machine("offline", name: "Offline", status: .unreachable)
    let expired = machine("expired", name: "Expired", status: .expired)

    #expect(local.isOnline)
    #expect(online.isOnline)
    #expect(!offline.isOnline)
    #expect(!expired.isOnline)
    #expect(T3MachinePicker.resolvedID("online", machines: [local, online, offline]) == "online")
    #expect(T3MachinePicker.resolvedID("offline", machines: [local, online, offline]) == "local")
    #expect(T3MachinePicker.resolvedID("expired", machines: [local, expired]) == "local")
    #expect(T3MachinePicker.resolvedID("missing", machines: [local, online]) == "local")
}

@Test func switchingMachinesKeepsOnlyAProjectThatExistsThere() {
    let shared = machineProject("float")
    let other = machineProject("reports")

    #expect(
        T3MachinePicker.projectIDAfterSwitch(
            "float", projectsOnSelectedMachine: [shared, other]
        ) == "float"
    )
    #expect(
        T3MachinePicker.projectIDAfterSwitch(
            "missing", projectsOnSelectedMachine: [shared, other]
        ) == nil
    )
    #expect(
        T3MachinePicker.projectIDAfterSwitch(
            "float", projectsOnSelectedMachine: []
        ) == nil
    )
}
