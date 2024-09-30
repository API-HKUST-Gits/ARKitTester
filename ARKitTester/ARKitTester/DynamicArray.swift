//
//  DynamicArray.swift
//  SigIntIOS
//
//  Created by HU Siyan on 1/9/2024.
//

import Foundation

class DynamicArray {
    private var array: [[String: Any]] = []
    
    init() {
        self.array = []
    }
    
    // Copy constructor
    init(copyFrom other: DynamicArray) {
        self.array = other.array.map { element in
            return element.mapValues { value in
                if let copyable = value as? NSCopying {
                    return copyable.copy() as Any
                } else {
                    return value
                }
            }
        }
    }
    
    // Insert an element
    func insert(_ element: [String: Any]) {
        array.append(element)
    }
    
    // Remove an element at a specific index
    func remove(at index: Int) {
        guard index >= 0 && index < array.count else { return }
        array.remove(at: index)
    }
    
    // Modify an element at a specific index
    func modify(at index: Int, with newElement: [String: Any]) {
        guard index >= 0 && index < array.count else { return }
        array[index] = newElement
    }
    
    // Get an element at a specific index
    func get(at index: Int) -> [String: Any]? {
        guard index >= 0 && index < array.count else { return nil }
        return array[index]
    }
    
    func getAllItems() -> [[String: Any]] {
        return array
    }
    
    // Get the count of elements
    var count: Int {
        return array.count
    }
    
    // NSCopying protocol implementation
    func copy(with zone: NSZone? = nil) -> Any {
        return DynamicArray(copyFrom: self)
    }
    
    // Deep copy method
    func deepCopy() -> DynamicArray {
        return self.copy() as! DynamicArray
    }
    
    // Traverse the array and remove elements based on a timestamp and threshold
    func traverseAndRemove(timestamp: Date, key: String, threshold: Any) {
        array = array.filter { element in
            guard let elementTimestamp = element["timestamp"] as? Date,
                  let value = element[key] else {
                return true // Keep elements that don't have the required keys
            }
            
            if elementTimestamp <= timestamp {
                if let thresholdDouble = threshold as? Double,
                   let valueDouble = value as? Double {
                    return valueDouble <= thresholdDouble
                } else if let thresholdInt = threshold as? Int,
                          let valueInt = value as? Int {
                    return valueInt <= thresholdInt
                } else if let thresholdString = threshold as? String,
                          let valueString = value as? String {
                    return valueString <= thresholdString
                }
            }
            
            return true // Keep elements that don't match the criteria
        }
    }
    
    // Print all elements (for debugging)
    func printAll() {
        for (index, element) in array.enumerated() {
            print("Element \(index): \(element)")
        }
    }
}

//// Example usage:
//let dynamicArray = DynamicArray()
//
//// Insert elements
//dynamicArray.insert(["id": 1, "name": "John", "value": 10, "timestamp": Date()])
//dynamicArray.insert(["id": 2, "name": "Jane", "value": 20, "timestamp": Date().addingTimeInterval(3600)])
//dynamicArray.insert(["id": 3, "name": "Bob", "value": 30, "timestamp": Date().addingTimeInterval(7200)])
//
//print("Initial array:")
//dynamicArray.printAll()
//
//// Modify an element
//dynamicArray.modify(at: 1, with: ["id": 2, "name": "Jane", "value": 25, "timestamp": Date().addingTimeInterval(3600)])
//
//print("\nAfter modification:")
//dynamicArray.printAll()
//
//// Remove an element
//dynamicArray.remove(at: 0)
//
//print("\nAfter removal:")
//dynamicArray.printAll()
//
//// Traverse and remove elements based on timestamp and threshold
//let thresholdTimestamp = Date().addingTimeInterval(5400) // 1.5x hours from now
//dynamicArray.traverseAndRemove(timestamp: thresholdTimestamp, key: "value", threshold: 20)
//
//print("\nAfter traversal and removal:")
//dynamicArray.printAll()
