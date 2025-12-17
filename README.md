# Swiftlee Concurrency - Swift 6

These are the notes for (AvdLee's Swift Concurrency Code)[https://github.com/AvdLee/Swift-Concurrency-Course/tree/main]

What started in Swift 5 as implementing the ideas behind Lattner's Manifesto, has now continued with Swift 6.

Its goal is to eliminate all data races and help code become more predictable, reducing unexpected runtime issues.


## Async/Await

- One advantage vs completion handlers is that the compiler does not complain when we forget to call the handler. Not returning a value inside of an `async` method makes the code non-compilable. 

In this code:

```
let titleOne = try await fetcher.fetchTitle(1)
let titleTwo = try await fetcher.fetchTitle(2)
let titleThree = try await fetcher.fetchTitle(3)

print("Title 3: \(titleThree)")
print("Title 2: \(titleTwo)")
print("Title 1: \(titleOne)")
```

The requests will fire one by one, in order of definition, which is the idea behind structured asynchronicity. So if the method `fetchTitle` prints the number, one will get this in the console:
```
1 
2
3
"Title 3: xxx"
"Title 2: yyy"
"Title 1: zzz"
```

The only exception happens with `async let`:

### async let

Opposite to `Task`, `async let` creates a structured task that is automatically canceled when the scope is left.

Since `async let` runs tasks asynchronously, one does not know when they start nor can know the order in which they end. Hence, doing:

```
async let titleOne = fetcher.fetchTitle(1)
async let titleTwo = fetcher.fetchTitle(2)
async let titleThree = fetcher.fetchTitle(3)
```  

can run any of the `fetchTitle` commands at first.

** => If the method is `async`, `async let` runs immediately.**

Example, if we have an async method that fetches a random number and prints it before returning it...:

```
func fetchRandomNumber() async -> Int {
    print("Starting to fetch number") 
    // some async logic using await
    print("Fetched number: \(randomNumber)")
    return randomNumber
}

async let number1 = await fetchRandomNumber()
try await Task.sleep(nanoseconds: 1_000_000_000)
async let number2 = await fetchRandomNumber()
let numbers = await [number1, number2]
print(numbers) 
``` 
...the output would be:

```
Starting to fetch number
Fetched number: xxx
Starting to fetch number
Fetched number: yyy
[xxx, yyy]
```
This shows us that the results for number1 and number2 were already fetched, way before `await [number1, number2]` were called.


### How is cancelling supported?

`async let` is a fancy `TaskGroup`. When different tasks as running asynchronously called and one fails, all tasks are not stopped immediately; instead it is waited until `await` is called.

So if the examples above throws an error for the first call of ``fetchRandomNumber`, the second task would still be started and the error would only be propagated upon calling `await [number1, number2]`, upon which all running tasks would be cancelled automatically.

### How to make sure a task completes before the scope ends?

When doing:
```
async let _ = fetchRandomNumber()
async let _ = await fetchRandomNumber()
```

The difference is that the first line will be cancelled upon leaving the scope. The second case will be awaited because `await` is there.

### When to use `async let` vs `Task`?

Use it in order to reduce memory overhead, which is higher with manually created tasks, and more importantly, when needing to make sure a task is cancelled when the scope is left. Cancelling `Task`s is a more manual activity.

So, unless one needs manual cancellation, dynamic task spawning or sequential execution, do use `async let`. Last but not least, `async let` can only be used within local declarations, not at the top level.

### Network requests with async-await using `URLSession`

Here we transform a method with signature:

```
func performPOSTURLRequest(completion: @escaping (Result<PostData, NetworkingError>) -> Void) {
```

to one like this one:

```
func performPOSTURLRequest() async throws(NetworkingError) -> PostData {
}
```

- By defining `throws(NetworkingError)`, the set of thrown errors is easier to follow.
- One can forget calling completion. Forgetting to return a value in a method or to handle an error make the code non-compilable.

## Tasks

#### When does a task start executing?

Tasks start immediately after being created, so nothing has to be done to schedule them.

#### How to cancel tasks?

A task can be cancelled by keeping a reference to it:

```
var myTaskReference = Task { await ... }
```
and calling:
```
myTaskReference.cancel()
```

BUT it does not mean the processes running inside will be cancelled by it, not like it happens with publishers or with a `URLSessionTask`.

`URLSession` performs cancellation tasks before running, so doing:
```
let task = Task { URLSession...() }
task.cancel()
```
will work making sure the `URLSession` request does not run. For asynchronous code within a `Task` that does not do so, one needs to use
```
try Task.checkCancellation()
```
if we are ok with handling a `CancellationError` from the caller or have a `do/catch` block. One way to avoid the latter block and being able to catch the cancellation is with a `Task.isCancelled` boolean:

```
guard Task.isCancelled == false else {
   return someDefaultValueUsedWhenNetworkFails
}
```

#### Cancelling image downloads from within SwiftUI views when they disappear

One quick way is having a 
```
@State var imageDownloadingTask: Task<Void, Never>?
...
.onAppear { imageDownloadingTask = Task { ...await downloadImage() } }
.onDisappear { imageDownloadingTask?.cancel() }
```

nevertheless, there is a way to let SwiftUI do this automatically, that is, with the `task` modifier:

 ```
@State var image: UIImage?
var body: some View {
     UIImage(uiImage: image)
     .task { image = await downloadImage() }
}
 ```
 
 In this case, SwiftUI cancels the task once the view is removed.
 
 
 #### Is .task run before Task?
 
 The executor decides, this is an example that explains it well:
 
 ```
 SomeView()
    .task(priority: .high, {
        /// Executes earlier than a task scheduled inside `onAppear`.
        print("1")
    })
    .onAppear {
        /// Scheduled later than using the `task` modifier which
        /// adds an asynchronous task to perform before the view appears.
        Task(priority: .high) { print("2") }
        
        /// Regular code inside `onAppear` might appear to run earlier than a `Task`.
        /// This is due to the task executor scheduler.
        print("3")
    }
```

 #### Parent Tasks 
 
 All children tasks are *notified* by their parents when a cancellation happens.
 
 **However**, that a Task is notified does not mean that the code will be cancelled. It is imperative to check for `Task.isCancelled` or `try Task.checkCancellation()` during execution.

#### Task types

A `Task` type generally infers the success of failure types it can handle.

The task `Task<String, Error>` will return a `String` when successful or an `Error` when not successful.

The task `Task<String, Never>` will return a `String` and is never expected to fail.

It is possible to handle errors within a task using `do/catch` blocks, or to throw them and propagate them to the caller. 

### Detached Tasks or _unstructured_ concurrency.

```
"A detached task runs a given operation asynchronously as part of a new top-level task."
```
And we start a task like this:
```
Task.detached {
    await doSomethingFromNonStructuredConcurrency()
}
```

Just like newly created Tasks, detached tasks are executed in a non structure way. One important thing is that detached tasks **do not inherit** from their context. They cannot. This includes priority and cancellation state, so one needs to address separately as it is a risk.

In this example:

```
let parentTask = Task {
    await someLongTask1()

    Task.detached {
        try Task.checkCancellation()
        await someLongTask2()
    }
}
parentTask.cancel()
```

The `someLongTask1` would be cancelled, the second one would not, even though we check if cancellation happened.

#### When to use Detached Tasks?

If using a 'detached' task is important, one that runs independently, `async let` would be advisable, or task groups. But in cases in which there is no need to access the context or need to cancel the tasks, such as downloading specific data or cleaning up directories, a detached task could be the solution.

### Task Groups

`async let` allows us creating tasks that run inside an _awaited_ array. But what if we need to use a for-loop? In that case `task groups` are the solution. These ones allow us to run a lot of different tasks asynchronously and return when all of them are done. These child tasks can run serially or in parallel. 

Here is an example that adds a task that returns a `String`, runs them all in parallel and returns when all tasks are done:

```
let results: [String] = await withTaskGroup(of: String.self) { group in
    group.addTask { "A" }
    group.addTask { "B" }
    return await group.reduce(into: []) { $0.append($1) }
}
```  

We can start tasks and gather their results, this is helpful to download the definition for a set of words, for example:
```
let dictionary: [String] = await withTaskGroup(of: String.self, returning: [String].self) { group in
    let words = await downloadWordsFromBook()
    for word in words {
        group.addTask { await downloadDefinition(of: word) }
    }
    var definitions = [String]()
    for await definition in group { // <- async sequence
        definitions.append(definition)
    }
    return definitions
}
```

The latter async sequence conforms to `AsyncSequence` and can be rewritten as:

```
return await group.reduce(into: [String]()) { partialResult, definition in
    partialResult.append(name)
}
```

#### What if one of the task group tasks throws an error?

In cases in which the method is one that can throw, using `withThrowingTaskGroup` is the right option. 

```
let dictionary: [String] = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
    let words = try await downloadWordsFromBook()
    for word in words {
        group.addTask { try await downloadDefinition(of: word) }
    }
    return try await group.reduce(into: [String]()) { partialResult, definition in
        partialResult.append(name)
    }
}
```

The great part is that `dictionary` will have a list of definitions that did not throw an error.

#### When are all tasks cancelled by a thrown error and when not?

In the following code, no task will be cancelled when the index is 3 because the error is inside of a child task:

```
try await withThrowingTaskGroup(of: Void.self) { group in
    (0..<5).forEach { index in 
        group.addTask {
            if index == 3 {
                throw SomeError()
            } else {
                print("index: \(index)")
            }    
        }
    }
}
``` 
The above code prints the numbers between 0 and 4, except number 3.

All tasks are cancelled only when the result of a task is unwrapped, meaning the error is rethrown inside of the main body of `withThrowingTaskGroup`:
```
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        print("3")
        throw NSError(domain: "hi", code: 123)
    }
    try await group.next()
} 
```
In this case the first `try await` before `withThrowingTaskGroup` will throw the error.
 
That child tasks do not throw errors is very useful for batched tasks that do not need a status update, such as analytics logs.

But in cases in which one wants status updates, one can use a for or a while loop in order to unwrap errors/results inside of groups and handle them accordingly:

```
while let someResult = try await group.next() {}
```
or 
```
for try await result in group {}
```

> So, to summarize:
> 
> Use `withTaskGroup` when your tasks can’t fail.
> 
> Use `withThrowingTaskGroup` when any child might throw.
> 
> To make the group fail early if a task throws, iterate over the results using methods like `next()` — otherwise, errors are silently ignored.

#### Cancellation in groups

Groups of tasks can also be cancelled from outside when needed, one option is by doing:
```
groupTask.cancelAll()
```

In an ideal world, code executed inside of child tasks respects cancellation correctly, but since the world is not always an ideal world, another good option is to run:
```
group.addTaskUnlessCancelled {}
```

### **async let** vs **TaskGroup**

Both `async let` and `TaskGroup` are very useful options to run tasks asynchronously and immediately, but here is a quick comparison:

| Characteristic | `async let`  | `Task Group` |
| ------------- | ------------- | ------------- |
| **It is bound to the scope where it is created**| Yes  | No  |
| **How does cancellation happen?**| It happens when scope is left  | Needs to happen manually  |
| **How are errors handled?**| It stops after the first error and throws it | It can ignore errors or throw them, it has control over them |
 
 As we can see in the [async let proposal site](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0317-async-let.md), the goal was to have a lightweight way to spawn an asynchronous task and let the parent use its results later. If one needs more control over cancellations, dynamically creating tasks or post-processing results, `TaskGroup`s are the perfect solution.
 
 ### [Discarding Task Groups](https://avanderlee.com/courses/wp/swift-concurrency/discarding-task-groups/)
 
 A quick summary of "Discarding Task Groups" is "Task Groups that discard the results of its child tasks".
 
 What is the benefit of this? Memory! Child tasks stared with `addTask` are not kept to be called with `.next()`, allowing quick and efficient memory release. A discarding group waits for all of its tasks to finish before returning, even if it has throwing tasks. When it returns, it is always empty, unless the main body kept something, like the count of added tasks.
 
 Here is example:
 ```
 let addedTasks = await withDiscardingTaskGroup(returning: Int.self) { group in
   var addedTasks = 0
   (0..<5).forEach { index in
       if index % 2 == 0 {
           group.addTask {
               print("index: \(index)")
           }
           addedTasks += 1
       }
   }
   return addedTasks
 }
 ```
 
 Notice that the above one does not use `try` and the added tasks cannot throw. In order to run throwing tasks, we need to use: `withThrowingDiscardingTaskGroup`.
 
 #### Cancellation
 
 Cancellation happens recursively over its child tasks as this is a structured concurrency primitive, so running `cancelAll()` cancels tasks.
 
 #### When to use?
 
 It makes sense to use when one needs different concurrent tasks executed without worrying about results, only about the final success state.
 
 One example is waiting for notifications. See the Notifications extension in the repository in order to see how an `AsyncSequence` and a `DiscardingTaskGroup` can be used to handle triggered notifications.
 
 #### Errors
 
 The discarding task group does not keep a memory, so it cannot store an error to throw it later (or not), so it throws it the moment it gets it. It does not cancel tasks that already started, it allows them to complete, but does not start new ones. 
 This is a crucial difference between `withThrowingTaskGroup` and `withThrowingDiscardingTaskGroup`. The first one keeps the error and throws it if it is unwrapped with `next()`, but the second one cannot do that because it does not access memory, so it throws it immediately.
 
   
### [Structured vs. Unstructured Tasks](https://avanderlee.com/courses/wp/swift-concurrency/structured-vs-unstructured-tasks/)

| Characteristic | Structured Tasks  | Unstructured Tasks |
| ------------- | ------------- | ------------- |
| **Inherits context and lifecycle from parent**| Yes, their scope is tied to an existing task, task group or actor  | No  |
| **Is execution flow predictable?**| Yes, meaning the compiler makes sure structured concurrency rules are ensured, which diminishes risks of data leaks  | No  |
| **Do they share a cancellation state?**| Yes, they can respect it using `Task.checkCancellation()`, which means they will be cancelled if parent tasks are cancelled. | No |

#### Structured Concurrency Tools

| Structured  | Unstructured |
| ------------- | ------------- |
| `async let` | `Task { }` – inherits context and explicit cancellation status but not lifetime  |
| `withTaskGroup` / `withThrowingTaskGroup`  | `Task.detached { }` – completely independent   |
| `withDiscardingTaskGroup` / `withThrowingDiscardingTaskGroup` |

#### What are "structured concurrency rules"?

- **Parent-Child Task Hierarchy:** Child tasks inherit priority, context and task-local values from parent task. Parent tasks cannot finish until all child tasks are done.
- **Automatic Cancellation Propagation:** Parent tasks propagate their cancellation status to their child tasks and they get cancelled **immediately**, even if they do not have code that respects the parent's cancellation status.
- **Scoped Lifetime:** Tasks cannot outlive their scope, they must finish before their scope ends.
- **Error propagation up the hierarchy:** Errors from tasks automatically propagate to parent tasks.
- **No Orphaned Tasks:** Every task has a parent, a.k.a: a clear owner.

All of the above secure structured flow of code, efficient resource management, less risk of data leaks/races, assured cancellation where needed (no zombie tasks), higher chances all errors are handled as they are bubbled up.

> The key is to use structured concurrency by default and only break out when you have a specific need for tasks with independent lifetimes.

### (Managing Task Priorities)[https://avanderlee.com/courses/wp/swift-concurrency/managing-task-priorities/]


Swift 6 wants us to not think about threads as we do not know in which thread a task is running. It invites us to try mainly focus on priorities.

#### What are default task priorities?

All tasks, except detached ones, inherit their priority from the context in which they are created. Running just `Task {}`, for example, we do not know which `Task.getCurrentTaskPriority` would be printed here:

```
Task {
    print("Current task priority: \(Task.currentPriority)")
}
```

If it is launched from within a SwiftUI view, then it would be `.userInitiated`, which is the same as `.high` (as of today and given their `rawValue` is the same one, but that can change in the future). 

A detached priority, however, would still print `.medium`. even if it is launched from a `.high` environment. The reason is because it is a complete unstructured tool that acts completely independent and does not inherit any context.

Here is a list of all priority levels currently available:

- `.userInitiated`: Default for tasks triggered by user actions, like loading data.
- `.utility`: Used for longer-running tasks that don’t require immediate results.
- `.background`: Ideal for low-priority work like caching or prefetching.
- `.high`: Used for tasks that require immediate user feedback.
- `.medium`: Used for tasks that don’t require immediate results, similar to utility.
- `.low`: Similar to the background priority.

#### Do priorities change during execution?

Not always, but they can and the executor is responsible for it. 

In cases in which the result of a task with low priority is needed by a task with high priority, the executor temporarily elevates the priority of the low-prio task to make sure the more urgent one does not suffer delays: the so called "priority-inversion".


#### What are the executors?

Executors are Swift's schedulers. They decide when a task is run taking priorities and resources into account. Actors, for example, have their own executor to make sure no data races happen.

> Executors in Swift Concurrency prevent race conditions, optimize performance, and help us avoid priority inversions.

**Priorities are only hints for the systems, they are not guarantees. The best option is to use the default task to let the executor decide. Try to set priorities when really sure of the high/low urgency.**

Here is a small table to practice guessing the set priority:

| Code  | `Task.currentPriority` |
| ------------- | ------------- |
| ```Task {
            print("Default task priority: \(Task.currentPriority)")
        }``` | Can be `.medium`, in general, but can also be `.high` as `Task` inherits the priority from its context. |
| ```Task.detached {
            print("Default task priority: \(Task.currentPriority)")
        }```  | `.medium`   |
| ```Task(priority: .background) {
            print("This task runs with a background priority: \(Task.currentPriority)")
        }``` | `.background` |
| ```func getCurrentTaskPriority() -> TaskPriority { Task.currentPriority }
    Task(priority: .utility) {
            async let taskPriority = getCurrentTaskPriority()
        }``` | `.utility` | 
| | |

