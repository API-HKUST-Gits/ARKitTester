//
//  RemoteAccess.swift
//  SigIntIOS
//
//  Created by HU Siyan on 6/8/2024.
//

import Foundation

class RemoteAccess: NSObject, URLSessionDelegate {
    static let shared = RemoteAccess()
    
    private override init() {
        super.init()
    }
    
//     MARK: - Upload
    func uploadJSONDictionary(_ dictionary: [String: Any], to urlString: String, completion: @escaping (Result<Data, Error>) -> Void) {
        // Ensure the URL is valid
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InvalidURL", code: 0, userInfo: nil)))
            return
        }
        
        // Convert dictionary to JSON data
        do {
            print(dictionary)
            let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            
            // Create the URL request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            // Create a URLSession task for the request
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NoData", code: 0, userInfo: nil)))
                    return
                }
                
                completion(.success(data))
            }
            
            // Start the task
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    
//     MARK: - Download
    func download(from downloadLink: String, to filePath: String, success: @escaping (String) -> Void, failure: @escaping (Error?) -> Void) {
        guard let url = URL(string: downloadLink) else {
            failure(NSError(domain: "InvalidURL", code: 0, userInfo: nil))
            return
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        
        let task = session.downloadTask(with: url) { location, response, error in
            if let error = error {
                failure(error)
                return
            }
            
            guard let location = location,
                  let response = response as? HTTPURLResponse,
                  let suggestedFilename = response.suggestedFilename else {
                failure(NSError(domain: "DownloadFailed", code: 0, userInfo: nil))
                return
            }
            
            let destinationFilePath = (filePath as NSString).appendingPathComponent(suggestedFilename)
            
            do {
                try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: destinationFilePath))
                success(suggestedFilename)
            } catch {
                failure(error)
            }
        }
        
        task.resume()
    }
    
    func read(from remoteLink: String, success: @escaping (Data) -> Void, failure: @escaping (Error) -> Void) {
        guard let url = URL(string: remoteLink) else {
            failure(NSError(domain: "InvalidURL", code: 0, userInfo: nil))
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                failure(error)
                return
            }
            
            guard let data = data else {
                failure(NSError(domain: "NoData", code: 0, userInfo: nil))
                return
            }
            
            success(data)
        }
        
        task.resume()
    }
    
    func read(from remoteLink: String, withParameters parameters: [String: String], success: @escaping (Data) -> Void, failure: @escaping (Error) -> Void) {
        guard let url = URL(string: remoteLink) else {
            failure(NSError(domain: "InvalidURL", code: 0, userInfo: nil))
            return
        }
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = parameters
        
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                failure(error)
                return
            }
            
            guard let data = data else {
                failure(NSError(domain: "NoData", code: 0, userInfo: nil))
                return
            }
            
            success(data)
        }
        
        task.resume()
    }
}
