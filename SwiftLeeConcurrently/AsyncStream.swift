import Foundation

// Code from https://github.com/AvdLee/Swift-Concurrency-Course/blob/main/Sample%20Code/Module%206%20-%20Async%20Sequences/AsyncSequencesConcurrency/Lesson%20Examples/AsyncStreams.swift

struct AsyncStreamDemonstrator {
    enum DemonstrationError: Error {
        case streamFinishedWithoutData
    }
    func demonstrateFileDownloading(imageURL: URL) async throws -> Data {
        do {
            let fileDownloader = FileDownloader()
            
            for try await status in fileDownloader.download(imageURL) {
                switch status {
                case .downloading(let progress):
                    print("Downloading progress: \(progress)")
                case .finished(let data):
                    print("Downloading completed with data: \(data)")
                    return data
                }
            }
            print("Download finished and stream closed without data")
            throw DemonstrationError.streamFinishedWithoutData
        } catch {
            print("Download failed with \(error)")
            throw error
        }
    }
    
    func demonstrateCancellation(imageURL: URL) {
        let task = Task.detached {
            do {
                let fileDownloader = FileDownloader()
                
                for try await status in fileDownloader.download(imageURL) {
                    switch status {
                    case .downloading(let progress):
                        print("Downloading progress: \(progress)")
                    case .finished(let data):
                        print("Downloading completed with data: \(data)")
                    }
                }
            } catch {
                print("Download failed with \(error)")
            }
        }
        task.cancel()
    }
}

struct FileDownloader {
    enum Status {
        case downloading(Float)
        case finished(Data)
    }
    
    enum FileDownloadingError: Error {
        case missingData
    }
    
    func download(_ url: URL, progressHandler: @Sendable @escaping (Float) -> Void, completion: @Sendable @escaping (Result<Data, Error>) -> Void) throws {
        /// Proper progress reporting should be done via `URLSessionDelegate`. For the sake of this example,
        /// we're only reporting progress on start and finish.
        progressHandler(0.1)
        
        /// Focussing on images only for this example.
        var imageRequest = URLRequest(url: url)
        imageRequest.allHTTPHeaderFields = ["accept": "image/jpeg"]
        
        print("Starting file download...")
        
        let task = URLSession.shared.dataTask(with: imageRequest) { data, response, error in
            progressHandler(1.0)
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let data {
                completion(.success(data))
            } else {
                completion(.failure(FileDownloadingError.missingData))
            }
        }
        task.resume()
    }
}

extension FileDownloader {
    /// Define a download overload which provides an `AsyncThrowingStream`.
    func download(_ url: URL) -> AsyncThrowingStream<Status, Error> {
        return AsyncThrowingStream { continuation in
            /// Configure a termination callback to understand the lifetime of your stream.
            continuation.onTermination = { @Sendable terminationReason in
                print("Stream termination reason: \(terminationReason)")
            }
            
            do {
                /// Call into the original closure-based method.
                try self.download(url, progressHandler: { progress in
                    /// Send progress updates through the stream.
                    continuation.yield(.downloading(progress))
                }, completion: { result in
                    let useShorthandYielding: Bool = false
                    
                    if useShorthandYielding {
                        /// Option 1: Shorthand yielding
                        ///  In the .success(_:) case, this returns the associated value from the iterator’s next() method.
                        ///  If the result is the failure(_:) case, this call terminates the stream with the result’s error, by calling finish(throwing:).
                        continuation.yield(with: result.map { .finished($0) })
                        continuation.finish()
                    } else {
                        /// Option 2: Yielding using a switch case.
                        switch result {
                        case .success(let data):
                            /// Send a finished message to the stream.
                            continuation.yield(.finished(data))
                            
                            /// Terminate the continuation.
                            continuation.finish()
                        case .failure(let error):
                            
                            /// Finished and terminate the continuation with the error:
                            continuation.finish(throwing: error)
                        }
                    }
                })
            } catch {
                /// Finished and terminate the continuation with the error:
                continuation.finish(throwing: error)
            }
        }
    }
}
