# Swiftlee Concurrency - Swift 6

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
 
 All child tasks are *notified* by their parents when a cancellation happens.
 
 **However**, that a Task is notified does not mean that the code will be cancelled. It is imperative to check for `Task.isCancelled` during execution.
