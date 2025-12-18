import Combine
import Foundation
import Network

public protocol NetworkMonitoring: NSObject, Sendable {
    var isNetworkAvailable: Bool { get async }
    var networkStatusStream: AsyncStream<Bool> { get }
    func start()
}

public enum NetworkOperationExecutionError: Error {
    case timeoutPassed
    case missingValue
    case unknownError(Error)
}

public actor NetworkMonitor: NSObject, NetworkMonitoring {
    private var _isNetworkAvailable: Bool = false
    public var isNetworkAvailable: Bool {
        _isNetworkAvailable
    }

    // Use AsyncStream instead of Combine
    public let networkStatusStream: AsyncStream<Bool>
    private var statusContinuation: AsyncStream<Bool>.Continuation?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NWMonitor")
    
    public override init() {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.networkStatusStream = stream
        self.statusContinuation = continuation
    }
    
    nonisolated public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task {
                await self?.updateNetworkStatus(isAvailable)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateNetworkStatus(_ available: Bool) {
        _isNetworkAvailable = available
        statusContinuation?.yield(available)
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
                    while await self?.networkMonitor.isNetworkAvailable ==  false {
                        try await Task<Never, Never>.sleep(for: .milliseconds(200), clock: .continuous)
                    }
                    let result = await closure()
                    return Result<T, NetworkOperationExecutionError>.success(result)
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
