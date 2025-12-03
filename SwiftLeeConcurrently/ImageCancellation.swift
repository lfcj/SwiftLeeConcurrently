import SwiftUI

struct ImageDownloadView: View {
    @State var image: UIImage?
    @State var imageDownloadingTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let image {
                Image(uiImage: image)
            } else {
                Text("Loading...")
            }
        }.onAppear {
            imageDownloadingTask = Task {
                do {
                    image = try await ImageFetcher().fetchImage()
                    print("Image loading completed")
                } catch {
                    print("Image loading failed: \(error)")
                }
            }
        }.onDisappear {
            imageDownloadingTask?.cancel()
        }
    }
}

struct AutoCancellingDownloadView: View {
    @State var image: UIImage?

    var body: some View {
        VStack {
            if let image {
                Image(uiImage: image)
            } else {
                Text("Loading...")
            }
        }.task {
            do {
                image = try await ImageFetcher().fetchImage()
                print("Image loading completed")
            } catch {
                print("Image loading failed: \(error)")
            }
        }
    }
}

struct ImageFetcher {
    
    // The wrapper is used to be able to show how cancellation works to return a fallback
    func fetchImageWithWrapper() async throws -> UIImage? {
        let imageTask = Task { () -> UIImage? in
            let imageURL = URL(string: "https://httpbin.org/image")!
            var imageRequest = URLRequest(url: imageURL)
            imageRequest.allHTTPHeaderFields = ["accept": "image/jpeg"]
            
            guard Task.isCancelled == false else {
                return UIImage(systemName: "xmark.circle")
            }
            print("Starting network request...")
            let (imageData, _) = try await URLSession.shared.data(for: imageRequest)
            
            return UIImage(data: imageData)
        }
        imageTask.cancel()
        return try await imageTask.value
    }

    func fetchImage() async throws -> UIImage {
        let fallbackImage = UIImage(systemName: "xmark.circle")!
        let imageURL = URL(string: "https://httpbin.org/image")!
        var imageRequest = URLRequest(url: imageURL)
        imageRequest.allHTTPHeaderFields = ["accept": "image/jpeg"]
        
        guard Task.isCancelled == false else {
            return fallbackImage
        }
        print("Starting network request...")
        let (imageData, _) = try await URLSession.shared.data(for: imageRequest)
        
        return UIImage(data: imageData) ?? fallbackImage
    }
}
#Preview {
    ImageDownloadView()
}
