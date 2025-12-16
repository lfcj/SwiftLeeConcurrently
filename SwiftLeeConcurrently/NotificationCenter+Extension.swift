import Foundation

// This code was found in https://avanderlee.com/courses/wp/swift-concurrency/discarding-task-groups/
extension NotificationCenter {
    func notifications(named names: [Notification.Name]) -> AsyncStream<()> {
        AsyncStream { continuation in
            /// Create a task so we can cancel it on termination of the stream.
            let task = Task {
                /// Start the discarding task group.
                await withDiscardingTaskGroup { group in
                    /// Iterate over all names and add a child task to observe the notifications.
                    for name in names {
                        group.addTask {
                            for await _ in self.notifications(named: name) {
                                /// Yield to the stream to tell the observer one of the notifications was called.
                                continuation.yield(())
                            }
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

/* The above can be used to observe as many notifications as we want and react using this:
 
 for await _ in NotificationCenter.default.notifications(named: [.userDidLogin, UIApplication.didBecomeActiveNotification]) {
     refreshData()
 }
*/

