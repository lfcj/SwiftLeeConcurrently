struct ParentTaskCancellation {
    func parentTaskExample() async {
        let handle = Task {
            print("Parent task started")

            async let childTask1 = someWork(id: 1)
            async let childTask2 = someWork(id: 2)

            let finishedTaskIDs = try await [childTask1, childTask2]
            print(finishedTaskIDs)
        }

        /// Cancel parent task after a short delay of 0.5 seconds.
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        /// This cancels both childTask1 and childTask2:
        handle.cancel()

        /// Wait for the parent task and notice how cancellation propagates.
        try? await handle.value
        print("Parent task finished")
    }

    func someWork(id: Int) async throws -> Int {
        for i in 1...5 {
            /// Check for cancellation and throw an error if detected.
            try Task.checkCancellation()
            print("Child task \(id): Step \(i)")
            
            /// Sleep for 0.4 seconds.
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        
        return id
    }
}
