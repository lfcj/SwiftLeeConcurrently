import Combine
import Foundation
import SwiftLeeConcurrently
import Testing

@MainActor
struct NetworkPerformerTests {

    @Test("If the network is initially available, the given closure is invoked")
    func given_availableNetwork_closureIsInvoked() async throws {
        // GIVEN
        let networkMonitor = FakeNetworkMonitoring()
        networkMonitor.isNetworkAvailable = true
        let networkPerformer = NetworkOperatorPerformer(
            networkMonitor: networkMonitor
        )

        // WHEN
        let result = await networkPerformer.invokeUponNetworkAccess(
            within: .seconds(0),
            { "Invoked!" }
        )

        // THEN
        let resultString: String = try result.get()
        #expect(resultString == "Invoked!")
    }

    @Test(
        """
         If the network is initially not available and does not become available, timeout error is throws
        """
    )
    func given_unavailableNetwork_timeOutPassErrorIsThrows_AfterTimeout() async {
        // GIVEN
        let networkMonitor = FakeNetworkMonitoring()
        networkMonitor.isNetworkAvailable = false
        let timerSubject = PassthroughSubject<Date, Never>()
        let networkPerformer = NetworkOperatorPerformer(networkMonitor: networkMonitor)

        // WHEN
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            timerSubject.send(Date())
        }
        let result = await networkPerformer.invokeUponNetworkAccess(
            within: .seconds(0.5),
            { "Timeout passed" }
        )

        // THEN
        switch result {
        case .failure(let error):
            #expect(error == .timeoutPassed)
        case .success(let successString):
            #expect(successString == "Timeout error was expected")
        }
    }

    @Test(
        """
         If the network is initially not available but becomes available **within** the given timeout duration, the given closure is invoked. From this point on, the timeout duration becomes irrelevant and is not used to cancel the closure execution.
        """
    )
    func given_unavailableNetwork_whenAvailableWithinTimeout_thenClosureIsInvoked() async throws {
        // GIVEN
        let networkMonitor = FakeNetworkMonitoring()
        networkMonitor.isNetworkAvailable = false
        let networkPerformer = NetworkOperatorPerformer(networkMonitor: networkMonitor)

        // WHEN
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            networkMonitor.isNetworkAvailable = true
            networkMonitor.networkStatusStream = AsyncStream(unfolding: { true })
        }

        let result = await networkPerformer.invokeUponNetworkAccess(
            within: .seconds(5),
            { "Network became available" }
        )

        // THEN
        switch result {
        case .failure(let error as NSError):
            #expect(error == NSError(domain: "Error not expected", code: -1))
        case .success(let successString):
            #expect(successString == "Network became available")
        }
    }
}

final class FakeNetworkMonitoring: NSObject, NetworkMonitoring {
    var networkStatusStream: AsyncStream<Bool> = AsyncStream(unfolding: { false })
    
    var isNetworkAvailable: Bool = false
    func start() {}
}


extension NetworkOperationExecutionError: @retroactive Equatable {
    public static func == (lhs: SwiftLeeConcurrently.NetworkOperationExecutionError, rhs: SwiftLeeConcurrently.NetworkOperationExecutionError) -> Bool {
        switch (lhs, rhs) {
        case (.timeoutPassed, .timeoutPassed):
            return true
        case (.missingValue, .missingValue):
            return true
        case (.unknownError(let lhsError), .unknownError(let rhsError)):
            return lhsError as NSError == rhsError as NSError
        default:
            return false
        }
    }
}
