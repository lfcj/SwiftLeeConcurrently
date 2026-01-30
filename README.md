# Swiftlee Concurrency - Swift 6

These are the notes for [AvdLee's Swift Concurrency Code](https://github.com/AvdLee/Swift-Concurrency-Course/tree/main)

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
func performPOSTURLRequest() async throws(NetworkingError) -> PostData {}
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

### [Managing Task Priorities](https://avanderlee.com/courses/wp/swift-concurrency/managing-task-priorities/)


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
| ```Task { print("Default task priority: \(Task.currentPriority)") }``` | Can be `.medium`, in general, but can also be `.high` as `Task` inherits the priority from its context. |
| ```Task.detached { print("Default task priority: \(Task.currentPriority)") }```  | `.medium`   |
| ```Task(priority: .background) { print("This task runs with a background priority: \(Task.currentPriority)") }``` | `.background` |
| ```func getCurrentTaskPriority() -> TaskPriority { Task.currentPriority }\nTask(priority: .utility) { async let taskPriority = getCurrentTaskPriority() }``` | `.utility` | 

### [Task.sleep() vs. Task.yield()](https://avanderlee.com/courses/wp/swift-concurrency/task-sleep-vs-task-yield/)

Both `.sleep` and `.yield` can be used to _stop_ a task for a certain period of time.

**.sleep does not sleep the block the underlying thread**, it just allows low priority tasks to be executed **for a certain time**. A common use case is to sleep a thread that reacts to user input (debouncing), like running a search after a user types. Other uses are polling APIs are intervals, limiting network requests using a rate, or artificial delays for UI testing.
 The code is like this one:

```
try await Task.sleep(for: .milliseconds(500))
```

This [code](https://github.com/AvdLee/Swift-Concurrency-Course/blob/main/Sample%20Code/Module%203%20-%20Tasks/ConcurrencyTasks/ConcurrencyTasks/Views/Task%20Sleep%20Example/ArticleSearcher.swift) shows how to use manual or automatically cancelled tasks that sleep for 500 ms before performing a search in order to allow the user type.

**.yield suspends the current task and allows others to execute**. It might suspend the task for a long time in order to execute higher priority tasks, or it might not even suspend it at all if the calling task is the one with the highest priority at the moment. 

There are no many situations in which `.yield` is a better option than `.sleep`, except for tests in asynchronous code, in which one wants to try and force threads to run in a certain order, hence assuring determinism: a must for tests. 

>  The duration of suspension is fixed for Task.sleep() and indeterminate for Task.yield(), both are non-blocking for their respective threads. .sleep can be cancelled and .yield only yields control.

### [Task local storage using @TaskLocal](https://avanderlee.com/courses/wp/swift-concurrency/task-local-storage-using-tasklocal/)

`@TaskLocal` is a wrapper that allows us to set a local variable to be used within a certain scope. As always, it is not inherited by detached tasks.

VdLee does not advice on using these properties as the risk of accessing it when it is no longer available is high and passing a pass-by-value variable is safer and has the same effect.

 ### [Running tasks in SwiftUI](https://avanderlee.com/courses/wp/swift-concurrency/running-tasks-in-swiftui/)
 
 `.task` is a very useful modifier to run asynchronous tasks tied to the lifecycle of a view. SwiftUI takes care of cancelling them when the view disappears. 
 
 It is important to know it is launched _before_ the view appears, so if our task modifies the view model, there needs to be a way to avoid unwanted changes before showing the view (e.g.: when using a search to filter lists, do not filter if the search query is empty).
 
 It is also good to notice this `.task` only runs once per view appearance. One way to make sure it runs again is to tie it to a changing ID. In the case of a search, it can be the search query, which will change when the user types. Example:
 
 ```
 .task(id: searchQuery) {
    await articleSearcher.search(searchQuery)
}
 ```
 
 Another option is to set the priority of the associated `.task`. The current default one for SwiftUI is `.userInitiated`, currently equivalent to `.high`, but we could want to log analytics with `.task(priority: .low)`

### [Task timeout handler using Task Groups](https://avanderlee.com/courses/wp/swift-concurrency/creating-a-task-timeout-handler-using-a-task-group/)

Task groups can be used creatively to create timeouts. By letting one of the tasks `.sleep(timeoutDuration)`, if that one is the first one to finish when one calls `group.next()`, then the timeout ended and the other task was not finished.

I used the example given by AdLee in the link above in order to run an operation **only** if the network is available. If the network does not become available during the timeout, then the operation is not executed.

Check out the [`NetworkOperationPerformer`](https://github.com/lfcj/SwiftLeeConcurrently/blob/main/SwiftLeeConcurrently/NetworkOperatorPerformer.swift) to see the details. The tests are also given [here](https://github.com/lfcj/SwiftLeeConcurrently/blob/main/SwiftLeeConcurrentlyTests/NetworkPerformerTests.swift).

## Sendable

### [Isolation Domains](https://avanderlee.com/courses/wp/swift-concurrency/explaining-the-concept-of-sendable-in-swift/)

The key here is not the protocol itself, but understanding that Swift does not care so much about threads, but about **isolation domains**. When an value or reference is passed between these domains, the compiler needs to know that it is _Sendable_ in order to guarantee thread-safetyness.

> An **isolation domain** defines a boundary within which a value or reference can be safely accessed without data races. These domains prevent concurrent modifications by ensuring that code executes in a controlled environment.

There are three types of isolation domains:

#### `nonisolated`

Default for all code. It means it does not modify any shared state. Therefore, it cannot modify states from other isolated domains. Nonisolated code can be called from any thread. An example could be:

```func sum(a: Int, b: Int) { a + b }```

#### `actor-isolated`

All properties inside of an actor are actor-isolated, meaning they only exist directly within the isolated domain that the actor creates and are thread-safe within it. These properties can be accessed from outside using `async` getters, which makes sure the access is protected.

```
actor Friends {
    var names: [String] = []

    func addFriend(_ name: String) {
        names.append(name)
    }

    func getFriendsList() -> [String] {
        return names
    }
}
```

An interesting feature in actors is that one can set a method or variable as `nonisolated` inside an actor. This would allow accessing it without `await`:

```
actor Friends {
    nonisolated let title = "Friends"
}
``` 

#### `global-actor`

It is the same as `actor-isolated`, but instead of providing access to methods, types and variables to only one isolated domain / actor, it provides a shared location domain. This is useful for different components of an app that need to be on the same level, like UI, which uses `@MainActor`

#### Can values travel between isolation domains?

Yes, and the trick is that they are `Sendable`. Value types are already `Sendable` by default, because they do not mutate. Reference values are not because they can mutate.

So, knowing an `Int` is `Sendable`, we know this struct:

```
struct A { var count: Int }
``` 
is `Sendable` by default.

```
class A { var count: Int }
```
is not.

### [Data Races vs. Race Conditions](https://avanderlee.com/courses/wp/swift-concurrency/understanding-data-races-vs-race-conditions-key-differences-explained/)

A **data race** is when different and multiple threads try to access shared data at the same time without mutual exclusion. The outcome is non-deterministic and can lead to errors or even crashes, so compiler is not happy and would complain in the following code when one turns the Thread Sanitizer on:

```
var counter = 0
let queue = DispatchQueue.global(qos: .background)

for _ in 1...10 {
    queue.async {
       counter += 1
    }
}

print("Final counter value: \(counter)")
```

**Race conditions** happen when multiple threads access shared data at the same time respecting mutual exclusion, but without properly synchronising. This is non-deterministic and can lead to errors. Compilers are happy, engineers maintaining flaky tests: less. 

In the following example, the compiler is happy because the actor protects the `Counter`s value from data races, but output can be different every time.

```
actor Counter {
    private var value = 0

    func increment() {
        value += 1
    }
    
    func getValue() -> Int {
        return value
    }
}

let counter = Counter()

for _ in 1...10 {
    Task {
        await counter.increment() // Safely increments the counter
    }    
}

// Read is safe, but outcome is not deterministic.
print("Final counter value: \(await counter.getValue())")
```

### [Conforming to Sendable](https://avanderlee.com/courses/wp/swift-concurrency/conforming-your-code-to-the-sendable-protocol/)

In a few words, `Sendable` is a protocol that tells the compiler that an object can be passed between isolation domains without worrying about mutual exclusion or data races.

The following is automatically `Sendable` and can be marked as such:

- Reference types that only have non-mutable variables
- Reference types that protect their mutable variables with locks (`@unchecked Sendable` is needed here.)
- structs or enum types because they are value types.

#### What is @unchecked Sendable

In cases in which we want to add conformance to `Sendable` from another module, the compiler will complain because there is the chance it does not have complete visibility over variables of the class (internal variables can exist). This means that it can not be sure objects have a complete thread-safe status. 
If we are sure ourselves, we can use `@unchecked Sendable` and make sure all variables are safe.


### [Sendable and Value Types](https://avanderlee.com/courses/wp/swift-concurrency/sendable-and-value-types/)

Value types are copied-by-value types, which makes them `Sendable` already because they are not mutable. This includes `structs`, `enum`s, `tuple`s and basic data types like `Int`, `String`, `Double` and `Bool`. They are implicitly `Sendable`.

#### When are enums or structs NOT Sendable implicitly?

When an `enum` or a `struct` are marked `public` or with `@usableFromInline`, they are not implicitly `Sendable`. If we want them to be `Sendable`, it has to be written explicitly.

Why?

Because when a struct or enum is shared publicly, the compiler does not have access to hidden details, such as private variables. This makes that it cannot guarantee the objects are thread-safe by default, so `Sendable` is needed explicitly. This makes sure that the compiler that compiled the module containing that struct made sure that private properties were also thread-safe.

An enum or struct can be part of frameworks or packages and accessed when they are public. In these cases, the 'client' that uses the dependency relies on types already being `Sendable` or not. If one was _implicitly_ `Sendable` and a new version means it is no longer the case, then the user of the framework will have a problem. That is a reason Swift Compilers require public value types to be explicitly marked as `Sendable`. 

**public** enums and structs are implicitly Sendable _when they are @frozen_. This allows the compiler to know ahead of time that there will not be changes, so if the current mutable variables are thread-safe, the objects will be it as well.

#### Sendable and actors.

One way to implicitly mark a value type as `Sendable` is by tying it to an actor. The most common way is using `@MainActor` as this would make sure that only that actor can access variables within the object and thread-safety would be given.

 ### [Sendable and Reference Types](https://avanderlee.com/courses/wp/swift-concurrency/sendable-and-reference-types/)

A reference type is never implicitly `Sendable` per se, only when using actors. Reference types are shared by sharing a reference, so changes to the objects change the object that all components have access to. Besides classes, these are other reference types in Swift:

- Closures
- Actors
- Metatypes (`Type` & `AnyClass`)
- Protocol with `AnyClass` or object constraints
- NSObjects
- References through UnsafePointer & Unmanaged

In order to have a reference type conform to `Sendable`, our type needs to:

1. Be `final`
2. Contain only non-mutable properties or already `Sendable` ones.
3. Have `NSObject` as superclass or none.

If these three are not fulfilled, it is necessary to add `@unchecked Sendable` or synchronize access using locks.

Dealing with `Sendable` reference types is added effort, so before creating one, consider these steps:

- Can I make this class a structure instead?
- Does this class need to be mutable and non-final?
- Is this class mainly used from the main thread and should it be marked with @MainActor instead?

**Why can't a non-final class be `Sendable`?'** Because its children could compromise thread-safety

### [Sendable and closures](https://avanderlee.com/courses/wp/swift-concurrency/using-sendable-with-closures/)

Closures are reference types that cannot conform to protocols at the moment, but are also very valuable types in programming with Swift.

In case in which we have an `actor` that guarantees already thread-safety, we might want to create methods that perform background work, like performing all planned transactions that are due today:

```
actor BankAccount {
    private(set) var money: Int = 0
    private let plannedTransactions: [PlannedTransaction] = []

    func transferMoney(_ amount: Int) {
        money -= amount
    }

    nonisolated func performMonthlyTransaction(_ canHappen: @escaping (PlannedTransaction) -> Bool) async {
        plannedTransactions.forEach { plannedTransaction in
            Task {
                if canHappen(plannedTransaction) {
                    await transferMoney(plannedTransaction.amount)
                }
            }
        }
    }
}
```

The error `Passing closure as a 'sending' parameter risks causing data races between code in the current task and concurrent execution of the closure` appears because we're sending a function from a task-isolation domain to an actor-isolation domain.

We'd need the task-isolation domain to conform to `Sendable` to ensure thread-safety, so we do:
```
nonisolated func performMonthlyTransaction(_ canHappen: @escaping @Sendable (PlannedTransaction) -> Bool) async {
    plannedTransactions.forEach { plannedTransaction in
        Task {
            if canHappen(plannedTransaction) {
                await transferMoney(plannedTransaction.amount)
            }
        }
    }
}
```

#### Capture-by-value

Whenever we have a closure in which we capture an inmutable value, we can use a list to capture it to comply with the compiler. When we do:
```
var someValue: SomeClass
await doSomething { [someValue] x in}
```

we capture `someValue`'s current value at that time and cannot not mutate it.

### [@unchecked Sendable](https://avanderlee.com/courses/wp/swift-concurrency/using-unchecked-sendable/)

The ideal world is that all of our types are `Sendable`, but there can be cases where we know something is thread-safe and cannot conform to `Sendable`, so we need to have the compiler ignore it using `@unchecked Sendable`. 

Even if we use a lock to make sure access is thread-safe, the compiler cannot know we are taking care of that, like this:
```
final class Counter {
    private let cacheMutatingLock = DispatchQueue(label: "cache.lock.queue")
    private var counter: Int = 0

    func increment() {
        cacheMutatingLock.sync { counter += 1 }
    }

    func decrement() {
        cacheMutatingLock.sync { counter -= 1 }
    }
}
```

`@unchecked` should only be used in very, very safe cases, as data races can be introduced that way. The best way is to migrate to `actor` in order to ensure thread-safety.

### Understanding region-based isolation and the sending keyword

> With region-based isolation, Swift drastically reduces the number of times we’ll have to use Sendable.

There are scenarios in which the compiler can reason that there will not be a data race and does not send a warning, even if a mutable value is shared across domains and is not `Sendable`, like in this case:

````
public class Person {
    var name: String
}
```

Here `Person` is not `Sendable`, `public` and non-final, so `name` is definitely mutable. But no error is thrown here:

```
func sendableChecked() {
    let person = Person(name: "Jane Done")
    Task { print(person.name) }
}
``` 
That is because the compiler can see that the `person` object is local: it detects an "isolation region".

But, if we add another access after sending this object to the task, like this:

```
Task { print(person.name) }
print(person.name)
```

The error now tells us:
```
Passing value of non-Sendable type '() async -> ()' as a 'sending' argument to initializer 'init(name:priority:operation:)' risks causing races in between local and caller code
```
because we are calling it after already transferring it to the task's isolation domain. Even though both our usages are reads, the basic logic is that a data race would occur if we access the mutable state from different isolation domains, so there is an error.

#### `sending`

There are scenarios where we are sure there will not be a data race, but the compiler does not agree. `sending` is helpful for these cases as it:
- makes sure that the value cannot be accessed from the original location after being transferred.
- prevents race conditions by enforcing ownership transfer.
- allows for optimized performance by avoiding redundant copies.

In the code above, if we do:

```
func check(person: sending SimplePerson) {
    Task {
        print(person.name)
    }
    print(person.name)
}
```
The `sending` moves the local region checks to this inner method's region only and makes sure that the `person` object cannot be accessed from the original called anymore.

Since the isolation region is now the inner method only, the compiler can now see that `person.name` is being read by the task and by the inner method logic's isolation domain, so mutex is not needed -> no data race risk.

However, if we make a change after the Task gets the value:

```
func check(person: sending SimplePerson) {
    Task {
        print(person.name)
    }
    person.name = "Other"
}
```
we will get a data-race error again. However, if we make sure that the method and the Task run on the same `MainActor`:

```
@MainActor
func check2(person: sending SimplePerson) {
    Task(priority: .userInitiated) {
        print(person.name)
    }
    person.name = "Hi"
}
```

The error becomes a warning as there will not be data race (same isolation domain), but there can be a race condition.

#### Returning with `sending`

We have other cases in which we also want to transfer ownership, especially with actors that have factor methods. In this case, this method is executed by the main actor:

```
@MainActor
func makePerson(name: String) -> SimplePerson {
    SimplePerson(name: name)
}
```

and this method wants to use that factory method:

```
func makePersonAndPrintIt() async {
    let person = await makePerson(name: "some name")
}
```
And it cannot.

The error being: 
```
Non-Sendable 'SimplePerson'-typed result can not be returned from main actor-isolated instance method 'makePerson(name:)' to nonisolated context
```
but in this case, we know that transferring domains would not cause a data-race, so the solution would be to let the compiler transfer the ownership:

```
@MainActor
func makePerson(name: String) -> sending SimplePerson {
    SimplePerson(name: name)
}
```
 
### Concurrency-safe global variables

Typical global variables are singletons and there are different ways to make sure the are concurrency-safe, or at least that the compiler does not complain:

1. actor isolation with @MainActor: Big disadvantage is that it is a hassle to call from non-concurrent domains.
2. Marking a `Sendable`. Great, but not always doable for big codebases.
3. Dangerous and fast: `nonisolated(unsafe) var shared = Singleton()`, for example. This tells the compiler that we take responsibility for thread safety. Just like with `@unchecked Sendable`, it is better to never use it.

### Combining Sendable with custom Locks

As discussed before, if mutable states are already protected with locks, then the best next step is making sure a migration to actors happen. From:

```
func increment() {
    lock.lock()
    counter += 1
    lock.unlock()
}
```

to an actor:

```
actor Counter {
    private var counter = 0
    func increment() {
        counter += 1
    }
}
```

But this would mean that any calls to `increment` in the codebase would need to migrate to using `await increment()`, which can be very cumbersome.

For these scenarios, again, the best route is to create a ticket to migrate. The second best option is to mark the class with `@unchecked Sendable`, make it final and make sure mutable states are as private as possible so changes only happen locally.

## Actors

### What is an actor?

Actors are reference types wrapped in bubbles paper. One can call values within them without worries about thread safety.

> “Only one task at a time can access my mutable state.” 

This is ensured by obliging usage of `await` by every caller of methods or properties when the caller is in a different isolation domain.

#### What is under the hood?

An _executor_. Every actor has a specific executor that takes care of running calls to the actor. Since any calls to an actor can only run on that executor, this one cannot modify a state at the same time and concurrency safety is given.


#### What is the difference between an actor and a class?

That actors do not support inheritance. Only with one exception: `NSObject`...to be able to work with Objective-C

### An introduction to Global Actors

A global actor is one that can be tied to a function, a type or a property and makes sure that access to said entity are thread-safe. An example is the `@MainActor`, which means: "make sure this runs on the executor running in the main thread", so mostly UI updates.

It is also possible to create other global actors for global variables that need protection. The `@globalActor` attributed makes that the actor it is applied to is globally accessible, like this:

```
@globalActor
actor AccountInfo {
    static let shared = AccountInfo()
}
```

By having the variable `shared` we automatically conform to the protocol `GlobalActor`. 

Once we define it, we can use it for activities that only said actor should handle, like login:

```
@AccountInfo
func login() {}

@AccountInfo
struct AccountManager {}
```

These actions would all run in the same executor.

#### Why is it good that it is a singleton?

If it is not a singleton, then different instances of the global actor can be created. Each would get a different executor and our goal is that all of our tasks run in the same executor: creating global isolation.

### When and how to use @MainActor

The `@MainActor` is a global actor that runs on the main thread as long as the methods, properties, etc. that it applies to are being called from a asynchronous context.

This means that Swift will not allow such a call:

```
@MainActor func updateViews() {}

DispatchQueue.global().async {
    updateViews() // ❌ Compile-time error
}
``` 

#### Using the MainActor directly

It is possible to use `MainActor.run {}` instead of `DispatchQueue.main.async {} ` when we need to run any UI updates in the main thread.

Another option is to use the attributed for the complete method. In cases in which there is a network call, this one still happens in the background thread because `URLSession.shared` handles its own queues. In this code:

```
@MainActor
func fetchImage(for url: URL) async throws -> UIImage {
    let (data, _) = try await URLSession.shared.data(from: url)
    guard let image = UIImage(data: data) else {
        throw ImageFetchingError.imageDecodingFailed
    }
    return image
}
```
the method is first called on the main thread, but then it asks the `URLSession` for data. Once it receives it, the main thread receives it and creates the `UIImage`, which is then returned, this on the main thread already.

#### Using `MainActor.assumeIsolated`

There can be cases in which we are in a synchronous context and need to access the `MainActor` isolated domain. In that case we cannot use `await`, but *if we are very sure we are already in the main thread*, we can call:

```
MainActor.assumeIsolated { // run code in the main thread accessing MainActor's context }
```

If we were not in the main thread, the app will crash, as this method checks that the executor is the same one as the `MainActor`'s one.

The safest option is to make sure one is the main thread before calling `assumeIsolated`

```
 assert(Thread.isMainThread)
```
...although we would already have a crash when testing.

### Isolated vs. non-isolated access in actors

Actors are `isolated` by default, just like declarations are `internal` unless marked otherwise.

There are cases in which we want to mark properties as `isolated` or `nonisolated` and we can do so. When interacting with actors from outside of their isolation domain, since we need to use `await`, we can use `isolated` to reduce the number of suspension points (so `await` calls). If we have this:

```
func payMortgage(_ sum: Double, from bankAccount: BankAccount) {}
```

where `BankAccount` is an actor, then withdrawing the money and showing the balance afterwards will needs two suspension points:

```
func payMortgage(_ sum: Double, from bankAccount: BankAccount) async -> Double {
    await bankAccount.withdrawMoney(sum)
    let newBalance = await bankAccount.balance
    return newBalance
}
```
One option to avoid waiting twice is to use `isolated` to mark `bankAccount`, that way the complete method will be executed in the actor's isolation domain:

```
func payMortgage(_ sum: Double, from bankAccount: isolated BankAccount) async -> Double {
    await bankAccount.withdrawMoney(sum)
    let newBalance = await bankAccount.balance
    return newBalance
}
```
Callers of `payMortgage` outside of the `BankAccount` actor will need to use `await`, of course.

#### isolated closures

We can have closures that get an isolated actor in order to perform actions from outside, like this:

```
actor BankAccount {
    func payMonthlyBills(_ perform: @escaping (isolated BankAccount) -> Void)
}
```
that way, the caller can use the `BankAccount` and call all the methods it needs from it without needing to await:
```
await bankAccount.payMonthlyBills { account in
    account.payMortgage()
    account.payUtilities()
    account.payTaxes()
}
```

#### Adding this extension for all actors

As this is very useful in order to perform several operations on an actor, this can be an extension for all Actors:

```
extension Actor {
    @discardableResult
    func performInIsolation<T: Sendable>(_ closure: @escaping (isolated Self) throws -> T) async rethrows -> T {
        try closure(self)
    }
}
```

which would allow us to call:
```
await bankAccount.performInIsolation { account in ... }
```
for all actors.

#### Using the nonisolated keyword in actors

Accessing non mutable data inside actors can be needed and the best option is to mark those properties as `nonisolated`. When it is a `let`-property, the compiler recognizes is as nonisolated already, but if we a computer property such as:
```
let firstName
let lastName: String
nonisolated var fullName: String { "\(firstName) \(lastName)"}
``` 
This is very helpful for cases in which we need to conform to a protocol, one such as `CustomStringConvertible`, which has a `var description: String { get}` property. It would not compile because we could pass actors and classes as `CustomStringConvertible`s and the it'd be impossible to know if the caller is the actor itself, so the compiler throws an error. An easy fix is to mark is as `nonisolated`. 

### Using Isolated synchronous deinit

It is often that we want to cancel tasks inside of `deinit`, but that causes a compiler error for actors because `deinit` is nonisolated, so calling any `cancel` methods would need to happen with `await`.

This is, of course, not possible because deinit can not be asynchronous. That would a mess for the ARC system, no knowing when an object can really be released. 

A solution is adding `isolated` to deinit:

```
isolated deinit {
    cancel()
}
```

This is only available for 18.4+.

### Adding isolated conformance to protocols

If we have a bank account such as this one:

```
@MainActor
final class BankAccount {
    let holder: String
    var balance: Double
    init(holder: String, balance: Double) {
        self.holder = holder
        self.balance = balance
    }
} 
```

and want to make it `Equatable` later, the comparison that uses `lhs.balance == rhs.balance` can cause a data race because we do not know which actor is executing this code. We cannot be sure it is the `MainActor`. Thankfully, if we turn "InferIsolatedConformances" on under Build Settings, we can tell the compiler that `BankAccount` only conforms to `Equatable` when the main actor is working on it:

```
extension BankAccount: @MainActor Equatable {}
``` 

### Understanding actor reentrancy

Actor reentrancy is whenever the actor does work, suspends it to let another actor, with a different priority (possibly) do work, and then returns to finish the work it had started. The state of the actor can have changed during that "break" and can cause unexpected behaviour. Actor reentrancy can cause race conditions and is the nature of concurrency's difficulties. 

If we'd have a method to count the number of cars that pass by a small town:

```
func controlTraffic() {
    cars += 1
    await police.notify(cars)
    announce("\(cars) have passed as of now.")
}
``` 
Then we could unexpected announcements because, take 5 cars pass, if the `police.notify` method takes a bit more, the actor waits for the `police` method to finish, but, in parallel, its executor can count more cars and change the actor's `cars` number, such that when all `controlTraffic` methods finally resume and call `announce`, the number of `cars` can be the same for all.

One could end up with:
```
x have passed as of now
x have passed as of now
x have passed as of now
```
instead of 
```
x-2 have passed as of now
x-1 have passed as of now
x have passed as of now
```

The solution in concurrency is to make sure that actors end up all of their important work before suspension

### Inheritance of actor isolation using the #isolation macro

Sometimes it can be useful to inherit the isolation domain of the caller and `#isolation` is helpful there, as it allows entering the actor's properties and methods without suspension and even safely pass non-sendable values. This macro offers that option to `async` methods.

The example begins with a sequential map extension that transform all values in an array, allowing the transformation to happen asynchronously: 
```
extension Collection where Element: Sendable {
    func sequentialMap<Result: Sendable>(
        transform: (Element) async -> Result
    ) async -> [Result] {
        var results: [Result] = []
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
```
Would we call this method inside of a @MainActor context, like this:
```
Task { @MainActor in
    let names = ["Antoine", "Maaike", "Sep", "Jip"]
    let lowercaseNames = await names.sequentialMap { name in
        await lowercaseWithSleep(input: name)
    }
    print(lowercaseNames)
}
```
then the compiler would complain because `sequentialMap` would leave the `MainActor`'s context and enter `lowercaseWithSleep`'s one. This could cause data races. The solution is to make sure that `lowercaseWithSleep` is executed by the calling actor's executor. This is done passing the isolation domain:

```
func sequentialMap<Result: Sendable>(
    isolation: isolated (any Actor)? = #isolation,
    transform: (Element) async -> Result
) async -> [Result] {
```

This is very powerful to write **generic extensions**, so the extension can be easily called without `await` / context switches.

### Using a custom actor executor

> By default, actors run their tasks on a shared global thread pool. This pool doesn’t stick to a specific thread or queue, so an actor’s tasks can hop between different threads as they run.

There are situations in which we want to make sure our tasks run in a background queue (blocking, heavy, slow ones) and prefer to create an executor for those cases.

When having an executor, we can use methods such as `Task(executorPreference:)` or `group.addTask(executorPreference:)` to set a preferred executor. Emphasis on "preferred", as the system will pick another executor if needed.

A custom executor that is a `TaskExecutor` and a `SerialExecutor` would look like this:

```
final class DispatchQueueTaskSerialExecutor: TaskExecutor, SerialExecutor {
    private let dispatchQueue: DispatchQueue
    
    init(dispatchQueue: DispatchQueue) {
        self.dispatchQueue = dispatchQueue
    }
    
    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        dispatchQueue.async {
            unownedJob.runSynchronously(
                isolatedTo: self.asUnownedSerialExecutor(),
                taskExecutor: self.asUnownedTaskExecutor()
            )
        }
    }
    
    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}
```

and is to be used in cases in which we are really sure. It is also important we keep a strong reference to it from the actor because the ARC does not count it and we'd want to deinit after out actor stops existing.

### Using a Mutex as an alternative to actors

`async`/`await` are very helpful, but they introduce the need of a context switch. `actor`s are very thread-safe, but they introduce their isolated domains and the need to interact with `Sendable` instances. In cases in which we want to protect a specific case of mutability, a mutex can be the simplest solution.

#### [What is the difference between a Mutex and a Lock?](https://www.avanderlee.com/concurrency/modern-swift-lock-mutex-the-synchronization-framework/)

All mutexes are locks, but not all locks are mutexes. A mutex is a lock with strict ownership, meaning only one thread or task can lock/unlock it.

Here is an example of a mutex for a bank account:

```
class MutexBankAccount {
    private let balance = Mutex<Int>(0)

    var currentBalance: Int {
        balance.withLock { currentBalance in
            return currentBalance
        }
    }

    func deposit(_ amount: Int) {
        balance.withLock { currentBalance in
            currentBalance += amount
        }
    }

    func withdraw(_ amount: Int) -> Bool {
        return balance.withLock { currentBalance in
            guard currentBalance >= amount else { return false }
            currentBalance -= amount
            return true
        }
    }
}
```

The value to be protected is not separate from the lock, but is defined _within_ the lock. The parameter inside of the `withLock` method is `inout`, what allows us to comfortably modify it safely.

#### Throwing errors

We might want to throw an error instead of returning false when there is not enough money to withdraw and this is easy because `withLock` already `throws`:
```
func throwingWithdraw(_ amount: Int) throws {
    try balance.withLock { currentBalance in
        guard currentBalance >= amount else { throw Error.reachedZero }
        currentBalance -= amount
    }
}
```
`Mutex`s are `Sendable`, so they are a great way to create `Sendable` classes without actors or structs, very helpful to wrap non-Sendable types into classes and make them Sendable.

#### When to use actors and when to use Mutex?

There are cases in which you need safe, but **synchronous** access to data and actors are not the solution. There is also legacy code that cannot handle `async`/`await` calls

When actors can be used, they are the best call. When the mutable properties is small, mutex are a good, synchronous option. Its main downside is that it is thread-blocking, so the work done inside of the lock should be as small as possible, or one can easily have a livelock.

## AsyncStream and AsyncSequences

### Working with asynchronous sequences

An async sequence is one where we can await for results to come inside of a loop, like this:
```
for await result in array {
    accumulator.append(result)
}
```

`AsyncSequence` itself is just a protocol that defines how to access values. The entities that implement this protocol have an `AsyncIterator` and implement logic to store values.

### Creating a custom AsyncSequence

While `AsyncStream`s are better for usage, implementing a custom `AsyncSequence` is a good step to understand better how it works:

```
struct Images: AsyncSequence, AsyncIteratorProtocol {

    let urls: [URL]
    var currentIndex = 0

    mutating func next() async -> Data? {
        guard !Task.isCancelled else {
            return nil
        }

        guard currentIndex <= urls.count else {
            return nil
        }

        let currentURL = urls[currentIndex]
        let imageData = await fetchImage(from: currentURL)
        currentIndex += 1
        return imageData
    }

    func makeAsyncIterator() -> Images {
        self
    }

    func fetchImage(from url: URL) async -> Data {
        try? await Task.sleep(nanoseconds: 100_000)
        return Data()
    }
}
```

This sequence receives an array or urls, fetches the image for each one asynchronously, and returns them to the caller:
```
for await image in Images(urls: []) {}
```

Regular methods that are available for `Sequence` are also available for `AsyncSequence`, such as a `filter`, `map`, or even `contains`:
```
for await image in Images(urls: []).filter { $0.count > 0 } {}
let containsBigImage = await Images(urls: []).contains { $0.count > 2000000 }
```

### Using AsyncStream and AsyncThrowingStream in your code

An `AsyncThrowingStream` is a stream of values that can throw an error. The stream can be closed with a `finish` event.

Its best use is whenever a completion closure can keep delivering values, so the caller `await`s on it.

In a case where a download method gives us progress information as well as a final piece of downloaded data, the completion method could look like this:

```
func download(_ url: URL, progressHandler: @escaping (Float) -> Void, completion: @escaping (Result<Data, Error>) -> Void) throws {
        // .. Download implementation
    }
```

In this case the `progressHandler` could only be called once. If we implement the logic with an `AsyncStream`, the download logic could report progress in a more granular way:

```
func download(_ url: URL) throws -> AsyncThrowingStream<Status, Error> {
    AsyncThrowingStream { continuation in
        do {
            try download(
                url,
                progressHandler: { progress in
                    continuation.yield(.downloading(progress))
                },
                completion: { result in
                    continuation.yield(with: result.map { .finished($0)} )
                    continuation.finish()
                }
            )
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
```

In order to call this method, we can do so:

```
for try await status in fileDownloader.download(URL(string: "www.google.com")!) {
    switch status {
    case .downloading(let progress):
        print("Download is at \(progress)")
    case .finished(let data):
        print("All is good and we have \(data.count) bytes")
    }
}
```

#### Debugging an AsyncStream

Besides regular print statements, we can add a closure that is called when the `AsyncStream` is terminated:

```
continuation.onTermination = { @Sendable terminationReason in
    print("Stream termination reason: \(terminationReason)")
}
```

The value for `terminationReason` can be `finished`, `cancelled`, etc. This method is not only for debugging, of course, but also useful for cleanup work after the `AsyncStream` is closed.

#### Cancellation

`AsyncStream`s can get cancelled when an enclosing task is cancelled due to context inheritance.

There is **no way to cancel an `AsyncStream` directly**.

#### Configuring a buffer policy

The default `bufferingPolicy` of a stream is `.unbounded`, meaning it keeps all the values that it emits until they are read.

This is helpful to make sure one does not miss values, but not always needed. When wanting to receive the latest update on something (authentication status, network availability, etc.), then older values are not important.

Would we want to only keep 1 or x number of the latest values, we can use `.bufferingNewest(x)` as the buffering policy.

And, would we want the exact opposite: keeping 1 or x number of the **first** values, we can use `.bufferingOldest(x)`.

A final option is a buffering policy that keeps nothing and only emits the latest values. None read values are lost. This one is `.bufferingNewest(0)`.

### AsyncStream vs Publisher

There are enough situations in which replacing a `Publisher` with a `AsyncStream` is possible and there is one major difference: !! `AsyncStream` is designed to have one consume only and `Publisher` can have as many as it needs -> This is very important to keep in mind, because one can technically still do:

```
let stream = AsyncStream { ... }
Task { for await result in stream {} }
Task { for await result1 in stream {} }
``` 
In this case, both tasks would be unpredictable values emitted from the stream, no error, but a HUGE ERROR :) 

### Deciding between AsyncSequence, AsyncStream, or regular asynchronous methods

#### When to use an `AsyncSequence`?

As often as one needs to use `Sequence` directly in synchronous contexts: never? The important part about `AsyncSequence` is understanding how it works so we can interact with it. 

It will be used A LOT, but as an end-user, just like normal loops are used in programming, example:

```
let stream = NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange)
for await notification in stream {
    // handle time zone change notification
}
```

#### When to use `AsyncStream`?

> For bridging delegates, closure callbacks, or emitting events manually, an AsyncStream is often the best choice

Bridging delegates means that we create a bridge class that is the delegate of an entity we want to observe. This bridge class has a stream that is accessible for callers and calls the `continuation.yield` from the delegate methods. Callers that need the information that is delegated need to call the `for await update in bridge.stream` to be kept in the loop of changes.

Another option is for repetitive tasks, such as calling a service every x seconds, using `unfolding`:

```
struct PingService {
    
    func startPinging() -> AsyncStream<Bool> {
        AsyncStream<Bool> {
            try? await Task.sleep(for: .seconds(5))
            return await ping()
        } onCancel: {
            print("Cancelled pinging!")
        }
    }
    
    func ping() async -> Bool { true }
}
let pingService = PingService()

for await pingResult in pingService.startPinging() { .. handle ping result .. }
```

## Threading

### How Threads related to Tasks

A thread is a system resource to run a set of instructions. A task is a unit of asynchronous work that is run by Swift' cooperative pool.

Said pool takes care of optimizing resources so we developers do not have to do that on the lower level. That means that tasks can run on any thread that the pool spawns, but we do not see it. And the pool does not create a thread per task, but schedules the tasks on the minimum amount of threads or however it sees efficiently, with no more threads than CPU cores.

It is important to note that one task can start on one thread and finish on another one. In this code:

```
func task1() async throws {
    print("Task 1 started on thread: \(Thread.current)") // thread xxxxY
    try await Task.sleep(for: .seconds(2))
    print("Task 1 resumed on thread: \(Thread.current)") // thread xxxxY or xxxx2 or any other
}
```

the thread used after the suspension can be the first one or any other one.

A **big advantage** of Swift Concurrency vs Grand Dispatch Central is that it avoids threads explosion and is generally more efficient.

### Getting rid of the "Threading Mindset"

The most important swift is going from:

> In which Thread should this run? 

to

> Which actor should execute/own this?

This makes that our worry is no longer execution efficiency, but efficiently picking isolation domains to make sure there are not a lot of suspension points (actors interact with each other using suspension) while keeping mutual exclusion.

#### Hints, not (necessarily) priorities.

Threads in GCD allowed setting a QoS (quality-of-service) for a thread. Swift Concurrency allows "priorities" such as `userInitiated` that tell the execution pool that a task is important for the user. Setting this does not mean it will run right away, in the Pool We Trust for it to run asap :) 

#### Why Sendable makes so much sense

If we steer away from threads and think tasks that can be executed on any thread that is available, it is clear that _any thread_ will have access to modify data. This is a big danger for thread-safety and it becomes very obvious why a task's isolation domain is necessary. If no two threads can modify an isolation domain at the same time, then it does not matter on which thread a task runs as long as it has its domain.

### Understanding Task suspension points 

A suspension point is when a task stops executing to allow other task to run.

It usually happens after `await`, but **not always**. If the task that is _awaited_ can run synchronously, it can happen that no suspension happens. Swift Concurrency takes care of that decision.

### Actor re-entrancy

It is very important to think that an isolation domain is like an island and tasks are sets of work that happen on that island. Even if the resources of the island are safe to only be used individually, if this happens:

```
func buildHouse() {
    try chooseLocationWithWoodNearby()
    await chopWoodForHouse()
    buildHouse()
}

Task { buildHouse } // task for Jane's house
Task { buildHouse } // task for Bob's house
```

In this case, if the location chosen is the same one, whichever task returns faster from `chopWoodForHouse` might have chopped all wood. The next `chopWoodForHouse` will not have the same resources. This is called a race condition and can deliver unexpected results. In this case, no wood -> no house.

#### Will a task always run on a background thread?

We cannot know. The only time we know where a task is running is when the actor is the `MainActor`. Its tasks are executed by the main thread.

### Dispatching to different threads using nonisolated(nonsending) and @concurrent (Updated for Swift 6.2)

Up until Swift 6.2 or when `NonisolatedNonsendingByDefault` is set to FALSE, calling an asynchronous method with `await` from within a task run by the `MainActor` would have made that said task runs in a background thread.

When `NonisolatedNonsendingByDefault` is set to TRUE, **if the async method is nonisolated**, then it is run on the `MainActor` as well to avoid the context switch.

If that behavior becomes default and there is a case when we do not want it, then we can use the `@concurrent` attribute to oblige the context switch.  

### Controlling the default isolation domain (Updated for Swift 6.2)

The default isolation domain is `MainActor` for new projects. One can change this to `nonisolated` by disabling the `Default Actor isolation` under Build Settings.

## Memory Management

### Overview of memory management in Swift Concurrency

Swift Concurrency deals with thread-safety dangers, but memory leaks, retain cycles and unexpected object lifetimes are still very much present.

When one sets an object to `nil`, if a `Task` that it started has a strong reference to it, it will continue running until `deinit` is called, so a retain cycle happens.

Even if one holds a `[weak self]` reference, if any method is called and it had a task, that task will finish, even when its result is not needed.

It is imperative one pays attention to memory consumption in Swift Concurrency apps.

### Preventing retain cycles when using Tasks

The idea scenario is to avoid strong references, especially to `self`, as much as possible. Nevertheless, tasks can still continue running after an object is set to `nil`.

The best approach is to keep tabs on tasks and make sure we cancel them **actively** before an object is set to `nil`.

## Performance

### Using Xcode Instruments to find performance bottlenecks

Performance usually suffers due to 
- UI hangs
- Poor parallelization 
- Unnecessary suspensions.

Using Swift Concurrency from Xcode Instruments is helpful to see how many Tasks are running, how many Actors and what is the Main Thread dealing with.

It is good to name tasks like this:

```
Task(name: "Some name \(index)") {
``` 

when creating them from within a for-loop in order to see where they are being executed in Instruments.

This task shows an [example](https://github.com/AvdLee/Swift-Concurrency-Course/tree/main/Sample%20Code/Module%2010%20-%20Performance) of a for-loop running from within a Task that inherits the isolation context from the @MainActor:

```
@MainActor
class Generator {
    var wallpapers = [Wallpaper]()
    func generate() {
        Task {
            for i in 0..<number {
                let wallpaper = generateRandomWallpaper()
                wallpapers.append(wallpaper)
            }
        }
    }

}
```

The solution starts by creating an actor for the `generateRandomWallpaper` method and calling it with `await`. This does not introduce parallelization because the same actor is being used for every generation. It moves work away from the Main Thread, so it is a first step.

The next approach is using a TaskGroup. We can, however, see that generation happens one-by-one. This is because the actor is being used and it acts "alone" to protect is isolation domain. It is protecting nothing because there is no mutable state.

-> There is no need for an actor.

The next step is making sure that `generateRandomWallpaper` is `@concurrent` in order to send the work to background threads. The TaskGroup is also not needed because we would not need to cancel all tasks at the same time, nor do we need the results at once. Since we are fine receiving results whenever they are ready, the final optimal solution is:

```
@MainActor
class Generator {
    var wallpapers = [Wallpaper]()
    func generate() {
        for i in 0..<number {
            Task {
                let wallpaper = await WallpaperFactory.generateRandomWallpaper()
                wallpapers.append(wallpaper)
            }
        }
    }
}
struct WallpaperFactory {
    @concurrent static func generateRandomWallpaper() -> Wallpaper {}
}
```

Accesses to `wallpapers` are protected by the `@MainActor`, parallelization is guaranteed as one task is created to generate each wallpaper and the work within it is executed concurrently.

### Reducing suspension points by managing isolation effectively

The main goal is to have the least amount of code between suspension points to avoid non-deterministic scenarios.

When seeing `await` as crossing a border between isolation points, the goal is to:

> 1. Do as much work as possible before a border crossing
> 2. Cross it once
> 3. Finish the job
> 4. Only cross again when necessary

The best way to avoid suspension points is to not use them. That means: use synchronous methods instead of non-needed async ones.

#### Using nonisolated(nonsending) and @concurrent

When synchronous methods are not possible, using `nonisolated(nonsending)` or `@concurrent` are helpful to control suspension points.

The first one allows calling the method from the isolation domain of the caller, so there is no context switch / suspension point needed. In this code:

```
@MainActor
func updateUI() {
    Task {
        print("Starting on the main thread: \(Thread.current)")
        await someBackgroundTask()
    }
}
nonisolated(nonsending) private func someBackgroundTask() async {
    print("Background task started on thread: \(Thread.current)")
}
```
the output will always be:

```
Starting on the main thread: <_NSMainThread: 0x600001708080>{number = 1, name = main}
Background task started on thread: <_NSMainThread: 0x600001708080>{number = 1, name = main}
```

`@concurrent`, on the other side, allows us to explicitly do the context switch whenever we deem it necessary.

#### Inheritance of actor isolation using the #isolation macro

When dealing with actors and wanting to inherit the isolation domain of the caller, the go-to action is using `#isolation`.

#### Prefer non-suspending variant when available

Instead of calling `try await Task.checkCancellation()`, one can call 
```
guard !Task.isCancelled else { return }
```

#### Use Task groups or async let

These tools allow for parallel execution instead of waiting for work to be executed to continue

#### Checklist

> Whenever you write await, ask yourself:

> - Can this be synchronous?
> - Can I move this await to a higher-level function? (image processing example)
> - Am I accidentally hopping between isolation domains?
> - Would nonisolated(nonsending) remove the suspension?
> - Is there a non-suspending API available?
> - Should this be merged with another await using async let or task groups?

### Using Xcode Instruments to detect and remove suspension points

Using the checklist above is a great start, but it is always good to double check how Tasks are behaving.

Xcode Instruments allow us opening the Swift Concurrency instrument and checking the states of tasks. They are:

> Creating -> Running -> Suspended -> Ending

It is advised to stop on tasks that do the same and zoom into their "Suspended" states. What the longest they are suspended? That is how faster our app can be.

We can make it faster by removing suspension points, when possible.

In the example of the Wallpaper task, the second suspension is very long after a while. These are the suspensions.

```
@MainActor
class Generator {
    var wallpapers = [Wallpaper]()
    func generate() {
        for i in 0..<number {
            Task {
                // First suspension to enter `WallpaperFactory` isolation context and create wallpaper.
                let wallpaper = await WallpaperFactory.generateRandomWallpaper()
                // Second suspension to re-enter MainActor and add the wallpaper to the array
                wallpapers.append(wallpaper)
            }
        }
    }
}
```

In this case the `WallpaperFactory` does not protect any mutable state, so it can actually live within the same one as `Generator` and be executed concurrently:
```
@MainActor
class Generator {
    var wallpapers = [Wallpaper]()
    func generate() {
        for i in 0..<number { @concurrent in
            Task {
                // Notice this is now synchronous, no await.
                let wallpaper = WallpaperFactory.generateRandomWallpaper()
 
                // Only one suspension point to return to `MainActor`:
                await MainActor.run {
                    wallpapers.append(wallpaper)
                }
            }
        }
    }
}
```

Now there is only one suspension point. Further improvements would be to only load the amount of wallpapers that fit the screen, and not `number`, or even loading them into an array at once, since creating them does not need long.

### How to choose between serialized, asynchronous, and parallel execution

The goal is to always think in this order: `Sync -> Async -> Parallel` and only move towards the right when really needed.

Candidates for async or further classification are non-UI work, storage access, large data sets or network calls.

Today's devices are incredibly fast, so synchronous calls can be faster than async ones + context switches. A common example is reading JSONs from disk. Small ones and cached in the system, so it is faster to read them synchronously than switching to a background isolation domain.

It is advised to run apps for a long time in the background simulating user usage and monitoring them via Instruments. That allows catching performance glitches and starting optimization.

Overall, never forget Donald Knuth:

> Early Optimization is the Mother of all Evil

A final checklist to move along this funnel is:

> - Will this block the main actor long enough to be visible?
> - Will the work scale with user data (N items → N cost)?
> - Does the work involve I/O?
> - Does the work benefit from combining multiple independent operations?
> - Is this logic called frequently?
> - Is parallelism here causing memory pressure and CPU scheduling overhead mostly, or adding real value?
> - If you check 2 or more boxes, async or parallel is usually justified. However, once again, use Instruments when in doubt!

## Testing Concurrent Code

### [Testing concurrent code using XCTest](https://github.com/AvdLee/Swift-Concurrency-Course/tree/main/Sample%20Code/Module%2011%20-%20Testing%20Concurrent%20Code)

Tests that test methods that run in the `MainActor` have to be marked so as well. The ideal scenario would be to change the tested method so it runs on a different actor (if possible), but it is not always possible, so marking the test method itself with `@MainActor` fixes the error. It makes that the tests run in the main thread, so should be used with caution.

#### Dealing with `.sleep(` in tests.

In a method that starts a Task and does not wait for its result, then the best option is observing changes for `@Published` variables or `@ObservableObject`s using `withObservationTracking`. This method observes changes in an object or a variable and fulfills an expectation that is awaited. It looks like this:

```
let observableObject = MyObservableObject()
let expectation = self.expectation(description: "Changes")

_ = withObservationTracking {
    observableObject.results
} onChange: {
    expectation.fulfill()
}

observableObject.performTask()

/// Asynchronously await for the expectation to fulfill.
await fulfillment(of: [expectation], timeout: 10.0)

/// Assert the result.
XCTAssertEqual(observableObject.results, "expected results", "Should have results 'bla' 'bla'")
```

#### Expectations using Swift Testing.

Since Swift Testing does not support expectations, a roundabout needs to be found, either with a `withCheckedContinuation`...:

```
let observableObject = MyObservableObject()
    
await withCheckedContinuation { continuation in
    _ = withObservationTracking {
        observableObject.results
    } onChange: {
        continuation.resume()
    }
    
    observableObject.performTask()
}

#expect(observableObject.results == "expected results")
```
...or with a `confirmation` if we can `await` for the method that causes the change (`performTask`) and want to make sure we test the tracking works:
```
let observableObject = MyObservableObject()
    
/// Create and await for the confirmation.
await confirmation { confirmation in
    /// Start observation tracking.
    _ = withObservationTracking {
        observableObject.results
    } onChange: {
        /// Call the confirmation when results change.
        confirmation()
    }
    
    /// Start and await searching.
    /// Note: using `await` here is crucial to make confirmation work.
    /// the confirmation method would otherwise return directly.
    await observableObject.performTask()
}

#expect(observableObject.results == "expected results")
```

#### Using `setUp` and `tearDown` in Swift Testing

`setUp` and `tearDown` do not exist in Swift Testing structs. Instead we have `init() async throws` and `deinit`.

The `deinit` only allows for synchronous code, so in order to call async clean-up code, we need a new way of thinking of tests:

##### Using Test Scoping Traits for asynchronous clean ups

In order to have code that runs before and after tests, we can introduce "test traits" that will provide specific test scope. Instead of writing tests directly inside of a testing class, we create an environment for it.

```
@MainActor
final class MyClassTesting {

    @MainActor
    struct Environment {
        @TaskLocal static var observableObject = MyObservableObject()
    }
}
```
Then we define the trait itself to be able to run tests:
```
struct MyObjectTestingTrait: SuiteTrait, TestTrait, TestScoping {
    @MainActor
    func provideScope(for test: Test, testCase: Test.Case?, performing function: () async throws -> Void) async throws {
        print("Running for test \(test.name)")

        let observableObject = MyObservableObject()
        try await MyObjectTestingTrait.Environment.$observableObject
            .withValue(observableObject) { // It binds the task-local to the specific value for the duration of the synchronous operation
            await observableObject.setUp()
            try await function() // Original test
            await articleSearcher.tearDown()
        }
    }
}
```

Now we can call a test using this scope in this way:

```
@Test(MyObjectTestingTrait())
func testEmptyQuery() async {
    await Environment.observableObject.performSearchTask("")
    #expect(Environment.observableObject.results == "Expected results when search is empty query")
}
```

Another option is using the suite:

```
@Suite(MyObjectTestingTrait())
@MainActor
final class MyClassTesting {
    // ...
}
```

Traits are the solution to use `setUp` and `tearDown` inside of Swift Testing. If using `@Suite` or `@Test(...Trait())` depends on the needs of the test.

#### [Using Swift Concurrency Extras by Point-Free](https://github.com/pointfreeco/swift-concurrency-extras)

This framework is a great asset to avoid flaky tests. One common example is testing for `isLoading` states in methods such as:

```
var fetchFunStuff = (URL) async throws -> Data // we can have different ways to inject this logic for testing purposes
func load() async -> FunStuff {
    isLoading = true // (4)
    defer { isLoading = false } // (4)
    let funStuff = await fetchFunStuff() // (5)
    return funStuff
}
```

If one tests for it like this:

```
func testIsLoading() {
    Task { someObject.load() }
    XCTAssertTrue(someObject.isLoading)
}
```
It will mostly fail because the `load` method will not have started, or it will have finished. We cannot know.

The solution is in the framework above, more precisely in their method `withMainSerialExecutor`, which "attempts to run all tasks spawned in an operation serially and deterministically".

Testing a case such as `isLoading` with the main serial executor would then look like this:

```
func testIsLoading() {
    try await withMainSerialExecutor {
        someObject.fetchFunStuff = { // (1)
            // Let the #expect(isLoading) happen 
            Task.yield() // (5)
            return Data() // (7)
        }
        let task = Task { someObject.load() } // (2)
        
        // Suspend the current execution and let the Task above start executing `load`, which sets `isLoading` to `true`
        Task.yield()  // (3)

        XCTAssertFalse(someObject.isLoading) // (6)

        await task.value // (7)

        XCTAssertFalse(someObject.isLoading) // 8
    }
}
```

Thanks to the main serial executor running this code, we can know **exactly** in which order it will be executed. Like this:

1. Assign value to `fetchFunStuff`
2. Create `Task` that will execute the `load()` method
3. Yield execution time to waiting task, the `load` one
4. First lines inside of `load` are executed, one of them is `isLoading = true`
5. `fetchFunStuff` is called and then the `Task.yield()` inside of it, which lets the waiting task, the `testIsLoading` one, continue running.
6. `#expect(someObject.isLoading)` is called.
7. The task that continues running `load()` is resumed, returns the `Data()` and calls `defer`
8. Since `defer` was called, `isLoading` is now false and it can be asserted.

#### Why is the main serial executor needed?

Because of the definition of `yield`:

> If this task is the highest-priority task in the system, the executor immediately resumes execution of the same task. As such, this method isn’t necessarily a way to avoid resource starvation.

Meaning that, in a context where the main serial executor can be busy (when a lot of tests are running), the yield might turn back and forth. When we set the executor, we know it will forcibly switch.

A trick to run everything inside of the main serial executor under `XCTest` is using

```
override func invokeTest() {
    withMainSerialExecutor {
        super.invokeTest()
    }
}
```

#### [Using a main serial executor using Swift Testing](https://github.com/pointfreeco/swift-concurrency-extras/pull/56)

The parallel execution of SwiftTesting does not play well with the serial executor only, so just using a trait does not work.

The solution is using `serialized` for the whole suite:

```
@Suite(.serialized)
@MainActor
final class MyClassTesting {
    // ...
}
```

## Migrating existing code to Swift Concurrency & Swift 6

### Steps to migrate existing code to Swift 6 and Strict Concurrency Checking

#### 1. Find an isolated piece of code

It is good to start with a piece of code that does not have dependencies.

#### 2. Update related dependencies

Take a look at 3rd party packages and check for available updates.

#### 3. Add async alternatives

Use the Editor -> Refactor -> `Add Async Alternative` or `Add Async Wrapper` option in Xcode to add `async` alternatives to methods with warnings once the build settings are changed.

Then add a 'deprecated' warning to the old method:

```
@available(*, deprecated, renamed: "oldMethod(someParameter:)", message: "Consider using the async/await alternative.")
```

#### 4. Change the Default Actor Isolation

The default actor isolation inside of Build Settings can be `MainActor` and resolve warnings and errors.

#### 5. Enable Strict Concurrency Checking

Enable strict concurrency checking as "Complete" inside of the Build Settings.

**Minmal** enforces Sendable and actor-isolation checks where concurrency is explicitly used via @MainActor or @Sendable.

**Targeted** enforces what minimal does as well as any type that conforms to `Sendable`.

**Complete** enforces the above across all the codebase. Maximum safety.

#### 6. Add Sendable conformances

Make everything `Sendable`, even if the compiler has not complained _yet_.

#### 7. Enable Approachable Concurrency

Do it one-by-one and create a pull request for each of them. The list of approachable concurrency ones is in the point below.

#### 8. Enable upcoming features

Build settings allow to take on future features by enabling this:

| Swift Compiler - Upcoming features | Enabled? | Notes |
| ------------- | ------------- | ------------- |
| Bare Slash Regex Literals | Yes |
| Concise Magic File | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) | 
| Default Internal Imports | No |
| Deprecate Application Main | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| [Disable Outward Actor Isolation Inference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0401-remove-property-wrapper-isolation.md) | Yes - $(SETTING_DefaultValue_$(SWIFT_UPCOMING_FEATURE_6_0)_$(SWIFT_APPROACHABLE_CONCURRENCY)) |
| Dynamic Actor Isolation | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| Forward Trailing Closures | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| [Global-Actor-Isolated Types Usability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0434-global-actor-isolated-types-usability.md) | Yes - $(SETTING_DefaultValue_$(SWIFT_UPCOMING_FEATURE_6_0)_$(SWIFT_APPROACHABLE_CONCURRENCY)) |
| Implicitly Opened Existentials | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| Import Objective-C Forward Declarations | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| [Infer Isolated Conformances](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-isolated-conformances.md) | NO - $(SWIFT_APPROACHABLE_CONCURRENCY) |
| [Infer Sendable for Methods and Key Path Literals](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0418-inferring-sendable-for-methods.md) | Yes - $(SETTING_DefaultValue_$(SWIFT_UPCOMING_FEATURE_6_0)_$(SWIFT_APPROACHABLE_CONCURRENCY)) |
| Isolated Default Values | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| Isolated Global Variables | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| Member Import Visibility | No |
| Nonfrozen Enum Exhaustivity | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| Region Based Isolation | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| [Require Existential any](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md) | Yes - $(SWIFT_UPCOMING_FEATURE_6_0) |
| [nonisolated (nonsending) By Default](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md) | NO - $(SWIFT_APPROACHABLE_CONCURRENCY) |

One option is also `Migrate`, instead of YES or NO, which allows using Swift's migration tooling.

When enabling a proposed feature, do google the related proposal to understand the associated changes.

#### 9. Change to Swift 6 language mode

Change `Swift Language Version` to Swift 6. The ideal scenario is that there are no warnings...

### [Migration tooling for upcoming Swift features](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0486-adoption-tooling-for-swift-features.md)

When migrating to a feature, instead of marking "YES" directly, set 'Migrate'. This will show up warnings and adding Xcode's proposed changes is a good tool to wrap up the migration.

### Techniques for rewriting closures to async/await syntax

The first step is using the Editor -> Refactor -> Add Async Wrapper migration tool in order to avoid warnings.

By adding the `deprecated` warning, the first migration to use all alternatives is a shorter path.

The next step is using Editor -> Refactor -> Convert Function to Async...but that does not always gets rid of the closure, so manual rewriting is needed.

When converting `Result<Success, Error>`, it is helpful to create a nested `enum MyError: Swift.Error` and throw it when there are issues calling our new code.

### How and when to use @preconcurrency

Similar to `@unchecked Sendable`, `@preconcurrency` helps mute concurrency-related warnings.

This is helpful for 3rd party dependencies that one cannot control and can be used like this:

```
@preconcurrency import <some_module>
```
It is advised to only use this when there is a warning, not by default.

### Migrating away from Functional Reactive Programming like RxSwift or Combine

The current often usage of Combine in Swift Concurrency times is `@Published`: waiting for variable updates to update UI. The [SE-475 Transactional Observation of Values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md) proposes adding `Observations` to be able to do the same with Swift Concurrency. An example would be:

```
let names = Observations { person.name }

Task.detached {
    for await name in names {
            print("There is a new name: \(name)"
    }
}
```

It also allows to have several consumers in parallel, which is a must for Combine alternatives.

It is advised to try to migrate to Swift Concurrency without touching Comobine. For example, in this code to debounce search queries:

```
$searchQuery
    .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
    .sink(receiveValue: { /* do search and filtering */ })
    .store(in: &cancellables)
```
the alternative would be:
```
func search(_ query: String) {
    currentSearchTask?.cancel()
    currentSearchTask = Task {
        do {
            try await Task.sleep(for: .milliseconds(500)) // Debounce
            /* do search and filtering */ } 
        } catch {
            print("Search was cancelled")
        }
    }
}
```

Another Combine -> Swift Concurrency migration example is going from a view that uses a `@Published` variable to perform a search:

```
struct Combine_ListView: View {
    @StateObject private var myObservableObject = Combine_ObservableObject()
    var body: some View {
        List {
            ForEach(myObservableObject.results, id: \.self) { title in
                Text(title)
            }
        }
        .searchable(text: $myObservableObject.searchQuery)
    }
}
```
to an option where the searchQuery is a local `@State` variable and `.onChange` helps us monitor changes in order to perform a search:
```
struct Concurrency_ListView: View {
    @State private var searchQuery = ""
    @State private var myObservableObject = Concurrency_ObservableObject()
    var body: some View {
        List {
            ForEach(myObservableObject.results, id: \.self) { title in
                Text(title)
            }
        }
        .searchable(text: $searchQuery)
        .onChange(of: searchQuery) { oldValue, newValue in
            guard oldValue != newValue else { return }
            myObservableObject.search(newValue)
        }
        // or:
        .task(id: searchQuery) {
            await articleSearcher.search(searchQuery)
        }
    }
}
```

### A threading risk when using `sink` with actors

Compile-time safety does not apply to `sink` closures. So what throws an error in this scenario:
```
NotificationCenter.default.addObserver(forName: .someNotification) { [weak self] _ in
    self?.didReceiveSomeNotification() // Call to main actor-isolated instance in sync nonisolated context.
}
```
passes quietly here:
```
NotificationCenter.default.publisher(for: someNotification) 
    .sink { [weak self] _ in
        self?.didReceiveSomeNotification()
    }
```

And "notifications expect the poster to be in the same poster as the received", which is not very easy across a complete app...this translates to a crash when receiving a notification from a background thread and using `Combine`.

The best option is to migrate to concurrency-safe notifications.

The old API looks like this:

```
NotificationCenter.default.addObserver(forName: SomeObject.someNotification, queue: .main) { [weak self] _ in 
        self?.handleSomeNotification()
    }
```

the new one looks like this:
```
token = NotificationCenter.default.addObserver(of: SomeObject.self, for: .someNotification) { [weak self] message in
    self?.handleSomeNotification
}
```

While very similar, a big difference is the parameter of the completion method: message, which has a type of `MainActorMessage`:

```
public protocol MainActorMessage: SendableMetatype {
    @MainActor static func makeMessage...
    @MainActor static func makeNotification...
}
```
Taking a further look, we see that notifications that conform to this protocol are used in the `addObserver` method variant that respects observing and receiving in the `@MainActor`:

```
public func addObserver<Identifier, Message>(of subject: Message.Subject.Type, for identifier: identifier, using observer: @escaping @MainActor (Message) -> Void) -> NotificationCenter.ObservationToken where identifier: NotificationCenter.MessageIdentifier, Message: NotificationCenter.MainActorMessage, Message == Identifier.MessageType.
```

We can see the `observer` above and the `makeMessage` and `makeNotifications` are all methods within the `@MainActor`, which allows the compiler reason about thread safety.

#### Creating a custom AsyncMessage

Let us imagine one has this notification:

```
extension Notification.Name {

    /// Sent when user signs in, profile is passed as an object 
    static let userDidSignIn = Notification.Name(rawValue: "userDidSignIn")
}
```

The first step to migrate this notification to use the new API is:

```
struct UserDidSignInMessage: NotificationCenter.AsyncMessage {
    typealias Subject = Profile
    let profile: Subject
}
```

and then, using the [discoverability using Static Member Lookup in Generic Contexts](https://www.avanderlee.com/swift/static-member-lookup-generic-contexts/), we can do:

```
extension NotificationCenter.MessageIdentifier where Self == NotificationCenter.BaseMessageIdentifier<UserDidSignInMessage> {
    static var userDidSignIn: NotificationCenter.BaseMessageIdentifier<UserDidSignInMessage> {
        .init()
    }
}
```

Once we have the message defined, we need to adapt our observation logic like this:

```
userDidSignInToken = NotificationCenter.default.addObserver(of: Profile.self, for: .userDidSignIn) { [weak self] message in
    self?.handleSignIn(with: message.profile)
}
```

### Using Agent Skills for Swift Concurrency

These notes are a summary of [this video](https://www.youtube.com/watch?v=khekVi1PK3o&t=1s), which explains how to use [Agent Skills](https://agentskills.io/home) in order to help adopt and keep up with Swift Concurrency.

#### Hot do skills work?

Agent Skills has a list of skills one first explores, e.g.:
- I want to refactor SwiftUI
- I want to improve Swift Concurrency

A skill to do so is found and its SKILL.md is read. Its instructions are then executed by reading instructions one-by-one.

It is advised to use the latest skill to plan a refactor. For Swift, Antoine created the [Swift Concurrency Agent Skill repo](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill)

Reading the references inside of `swift-concurrency` alone is like following the course above, full of best practices with code examples.

Starting minute 10, it shows a real-life example. OMG, super mighty tool.



## Conclusion

This has been a very good overview of Swift Concurrency, which fixes a lot of the things that were wrong with Swift and its concurrency.

Applying it helps increase UI responsiveness, eliminate data races and make the app generally smoother.

Will be applying the learnings to https://github.com/lfcj/listen-anonymously/tree/main
