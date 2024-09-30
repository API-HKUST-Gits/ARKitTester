//
//  FileManager.swift
//  SigIntIOS
//
//  Created by HU Siyan on 30/7/2024.
//

import Foundation
import UIKit

class DataManager {
    static let shared = DataManager()
    private init() {}
    
    enum SubFolder: String {
//        case rgb = "RGB"
//        case depth = "Depth"
        case sensor = "Sensor"
        case gps = "GPS"
        case gt = "Gt"
//        case nerf = "NeRF"
    }
    
    func createNewDataFolder(folderName: String) -> URL? {
        let fileManager = FileManager.default
        
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Unable to access documents directory")
            return nil
        }
        
        let folderURL = documentsDirectory.appendingPathComponent(folderName)
        
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            print("Created new data folder at: \(folderURL.path)")
            
            // Create sub-folders
            try createSubFolders(in: folderURL)
            
            return folderURL
        } catch {
            print("Error creating directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createSubFolders(in parentFolder: URL) throws {
        /*let subFolders: [SubFolder] = [.rgb, .depth, .sensor, .gps, .gt, .nerf]*/  // Added .arKit
        let subFolders: [SubFolder] = [.sensor, .gps, .gt]
        
        for subFolder in subFolders {
            let subFolderURL = parentFolder.appendingPathComponent(subFolder.rawValue)
            try FileManager.default.createDirectory(at: subFolderURL, withIntermediateDirectories: true, attributes: nil)
            print("Created sub-folder: \(subFolderURL.path)")
        }
    }
    
    func getSubFolderURL(mainFolder: URL, subFolder: SubFolder) -> URL {
        return mainFolder.appendingPathComponent(subFolder.rawValue)
    }
    
    func saveImage(_ image: UIImage, named fileName: String, in saveFolder: URL) -> Bool {
        let fileURL = saveFolder.appendingPathComponent(fileName)
        
        guard let imageData = image.pngData() else {
            print("Failed to convert image to PNG data")
            return false
        }
        
        do {
            // Ensure the directory exists
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true, attributes: nil)
            
            // Write the file
            try imageData.write(to: fileURL, options: .atomic)
//            print("Successfully saved image at: \(fileURL.path)")
            return true
        } catch {
            print("Error saving image: \(error.localizedDescription)")
            return false
        }
    }
    
    func appendDictionaryToJSONFile(dictionary: [String: Any], fileName: String, in saveFolder: URL) {
        let fileURL = saveFolder.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        
        do {
            var jsonArray: [[String: Any]] = []
            
            // Check if file exists
            if fileManager.fileExists(atPath: fileURL.path) {
                // Read existing JSON data
                let data = try Data(contentsOf: fileURL)
                if let existingArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    jsonArray = existingArray
                }
            }
            
            // Append new dictionary
            jsonArray.append(dictionary)
            
            // Convert updated array to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
            
            // Write to file
            try jsonData.write(to: fileURL, options: .atomic)
            
//            print("Successfully appended dictionary to file at \(fileURL.path)")
        } catch {
            print("Error handling JSON file: \(error)")
        }
    }
    
    func appendStringToFile(_ string: String, fileName: String, in saveFolder: URL) {
        let fileURL = saveFolder.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                // File exists, append the new string
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                
                // Move to the end of the file
                fileHandle.seekToEndOfFile()
                
                // Add a newline before appending the new string, if the file is not empty
                if fileHandle.offsetInFile > 0 {
                    fileHandle.write("\n".data(using: .utf8)!)
                }
                
                // Write the new string
                fileHandle.write(string.data(using: .utf8)!)
                
                // Close the file
                fileHandle.closeFile()
                
//                print("Successfully appended string to existing file at \(fileURL.path)")
            } else {
                // File doesn't exist, create a new file with the string
                try string.write(to: fileURL, atomically: true, encoding: .utf8)
                
//                print("Successfully created new file with string at \(fileURL.path)")
            }
        } catch {
            print("Error handling text file: \(error)")
        }
    }
}
