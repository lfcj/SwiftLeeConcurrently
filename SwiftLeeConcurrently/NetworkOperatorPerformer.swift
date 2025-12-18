import Combine
import Foundation
import Network

public protocol NetworkMonitoring: NSObject, Sendable {
    var connectionUpdates: AsyncStream<Bool> { get }
    func start()
}

public enum NetworkOperationExecutionError: Error {
    case timeoutPassed
    case missingValue
    case deallocatedSelf
    case networkStatusStreamClosed
    case unknownError(Error)
}

public actor NetworkMonitor: NSObject, NetworkMonitoring {
    
    nonisolated public let connectionUpdates: AsyncStream<Bool>

    private var continuation: AsyncStream<Bool>.Continuation?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NWMonitor")
    
    public override init() {
        var cont: AsyncStream<Bool>.Continuation?
        connectionUpdates = AsyncStream { continuation in
            cont = continuation
        }
        super.init()
        self.continuation = cont
    }
    
    nonisolated public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task(priority: .high) {
                await self?.updateNetworkStatus(isAvailable)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateNetworkStatus(_ available: Bool) {
        continuation?.yield(available)
    }
}

public final class NetworkOperatorPerformer {

    // MARK: - Properties

    private let networkMonitor: NetworkMonitoring

    private var timerCancellable: Cancellable?

    // MARK: - Init/De-Init

    public init(networkMonitor: NetworkMonitoring = NetworkMonitor()) {
        self.networkMonitor = networkMonitor
        self.networkMonitor.start()
    }

    // MARK: - Invoking Network Access

    public func invokeUponNetworkAccess<T: Sendable>(
        within timeoutDuration: Duration,
        _ closure: @escaping @Sendable () async -> T
    ) async -> Result<T, NetworkOperationExecutionError> {
        do {
            return try await withThrowingTaskGroup(returning: Result<T, NetworkOperationExecutionError>.self) { group in
                _ = group.addTaskUnlessCancelled { [weak self] in
                    guard let self = self else {
                        return Result<T, NetworkOperationExecutionError>.failure(.deallocatedSelf)
                    }
                    for await isNetworkAvailable in await self.networkMonitor.connectionUpdates {
                        if isNetworkAvailable {
                            let result = await closure()
                            return Result<T, NetworkOperationExecutionError>.success(result)
                        }
                    }
                    return Result<T, NetworkOperationExecutionError>.failure(.networkStatusStreamClosed)
                }

                _ = group.addTaskUnlessCancelled {
                    try await Task<Never, Never>.sleep(for: timeoutDuration, clock: .continuous)
                    return Result<T, NetworkOperationExecutionError>.failure(.timeoutPassed)
                }

                // Odd case in which task group can be empty
                guard let result = try await group.next() else {
                    return .failure(.missingValue)
                }

                group.cancelAll()
                return result
            }
        } catch {
            return .failure(.unknownError(error))
        }
    }

}
