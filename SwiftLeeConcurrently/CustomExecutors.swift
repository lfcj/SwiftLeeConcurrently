import Foundation

final class DispatchQueueExecutor: SerialExecutor {
    private let dispatchQueue: DispatchQueue
    
    init(dispatchQueue: DispatchQueue) {
        self.dispatchQueue = dispatchQueue
    }
    
    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let unownedExecutor = unsafe asUnownedSerialExecutor()
        
        dispatchQueue.async {
            unsafe unownedJob.runSynchronously(on: unownedExecutor)
        }
    }
}

actor LoggingActor {
    
    private let executor: DispatchQueueExecutor
    
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe executor.asUnownedSerialExecutor()
    }
    
    init(dispatchQueue: DispatchQueue) {
        executor = DispatchQueueExecutor(dispatchQueue: dispatchQueue)
    }
    
    func log(_ message: String) {
        print("[\(Thread.current)] \(message)")
    }
}

/* Example:
 
 let dispatchQueue = DispatchQueue(label: "com.logger.queue", qos: .utility)
 dispatchQueue.sync {
     /// Give the thread a name so we can verify it in our print statements.
     Thread.current.name = "Logging Queue"
 }
 let actor = LoggingActor(dispatchQueue: DispatchQueue(label: "com.logger.queue"))
 await actor.log("Example message")

 // Prints: [<NSThread: 0x600003ad2940>{number = 2, name = Logging Queue}] Example message
 */

// Sharing executor among actors:

extension DispatchQueueExecutor {
    /// An example of a globally available executor to use inside any actor.
    static let loggingExecutor = DispatchQueueExecutor(dispatchQueue: DispatchQueue(label: "com.logger.queue", qos: .utility))
}

actor SharedExecutorLoggingActor {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe DispatchQueueExecutor.loggingExecutor.asUnownedSerialExecutor()
    }
    
    func log(_ message: String) {
        print("[\(Thread.current)] \(message)")
    }
}

final class DispatchQueueTaskExecutor: TaskExecutor {
    private let dispatchQueue: DispatchQueue
    
    init(dispatchQueue: DispatchQueue) {
        self.dispatchQueue = dispatchQueue
    }
    
    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let unownedExecutor = unsafe asUnownedTaskExecutor()
        
        dispatchQueue.async {
            unsafe unownedJob.runSynchronously(on: unownedExecutor)
        }
    }
}

/*
 let dispatchQueue = DispatchQueue(label: "com.logger.queue", qos: .utility)
 dispatchQueue.sync {
     /// Give the thread a name so we can verify it in our print statements.
     Thread.current.name = "Logging Queue"
 }

 let taskExecutor = DispatchQueueTaskExecutor(dispatchQueue: dispatchQueue)

 Task(executorPreference: taskExecutor) {
     print("[\(Thread.currentThread)] Task Executor example")
     
     // Prints: [<NSThread: 0x60000062c980>{number = 2, name = Logging Queue}] Task Executor example
 }
 */
