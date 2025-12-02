import Foundation

struct PostData: Codable, Sendable {
    let name: String
    let age: Int
}
nonisolated struct PostResponse: Decodable {
    let json: PostData
}
enum NetworkingError: Error, Sendable {
    case encodingFailed(innerError: EncodingError)
    case decodingFailed(innerError: DecodingError)
    case invalidStatusCode(statusCode: Int)
    case requestFailed(innerError: URLError)
    case otherError(innerError: Error)
    
    /// Only needed for closure based handling:
    case invalidResponse
}
struct APIProvider {
    func makePOSTRequest() -> URLRequest {
        let url = URL(string: "https://httpbin.org/post")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let postData = PostData(name: "Regina", age: 20)
        let httpBody = try! JSONEncoder().encode(postData)
        request.httpBody = httpBody
        return request
    }
    
    func performPOSTURLRequest(completion: @escaping @Sendable (Result<PostData, NetworkingError>) -> Void) {
        URLSession.shared.dataTask(with: makePOSTRequest()) { data, response, error in
            do {
                if let error {
                    throw error
                }
                guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkingError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkingError.invalidStatusCode(statusCode: httpResponse.statusCode)
                }
                let decodedResponse = try JSONDecoder().decode(PostResponse.self, from: data)
                completion(.success(decodedResponse.json))
            } catch let error as DecodingError {
                completion(.failure(.decodingFailed(innerError: error)))
            } catch let error as EncodingError {
                completion(.failure(.encodingFailed(innerError: error)))
            } catch let error as URLError {
                completion(.failure(.requestFailed(innerError: error)))
            } catch let error as NetworkingError {
                completion(.failure(error))
            } catch let error {
                completion(.failure(.otherError(innerError: error)))
            }
        }.resume()
    }

    func performPOSTURLRequest() async throws(NetworkingError) -> PostData {
        do {
            let (data, response) = try await URLSession.shared.data(for: makePOSTRequest())
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
                throw NetworkingError.invalidStatusCode(statusCode: -1)
            }
            guard (200...299).contains(statusCode) else {
                throw NetworkingError.invalidStatusCode(statusCode: statusCode)
            }

            let postResponse = try JSONDecoder().decode(PostResponse.self, from: data)
            return postResponse.json
        } catch let error as DecodingError {
            throw .decodingFailed(innerError: error)
        } catch let error as URLError {
            throw .requestFailed(innerError: error)
        } catch let error as NetworkingError {
            throw error
        } catch let error {
            throw .otherError(innerError: error)
        }
    }

    func main() {
        // Closure Request
        APIProvider().performPOSTURLRequest { result in
            print("Success response with closure: \(try! result.get())")
        }

        Task {
            let asyncResponse = try await APIProvider().performPOSTURLRequest()
            print("Success response with await: \(asyncResponse)")
        }

    }
}
