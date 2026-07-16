struct FleetOverview: Equatable, Sendable {
    let stateCounts: [WorkState: Int]
    let hosts: [HostSnapshot]
    let queue: [QueueItemSnapshot]

    init(snapshot: FleetSnapshot) {
        stateCounts = snapshot.stateCounts
        hosts = snapshot.hosts
        queue = snapshot.queue
    }

    func count(for state: WorkState) -> Int {
        stateCounts[state, default: 0]
    }
}
