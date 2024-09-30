//
//  ViewController.swift
//  ARKitTester
//
//  Created by HU Siyan on 25-09-2024.
//

import UIKit
import ARKit
import SceneKit
import CoreMotion
import CoreLocation


class ViewController: UIViewController, ARSessionDelegate, CLLocationManagerDelegate, ARSCNViewDelegate {
    
    private let algoDomain = ""
    private let remoteAccess = RemoteAccess.shared
    
    @IBOutlet var startButton: UIButton!
    @IBOutlet var pauseButton: UIButton!
    @IBOutlet var stopButton: UIButton!
    
    @IBOutlet var logView: UITextView!
    @IBOutlet var imageView: UIImageView!
    
    @IBOutlet var sceneView: ARSCNView!
    private var session: ARSession!
    
    private var depthMapWidth: Int = 0
    private var depthMapHeight: Int = 0
    
    private var currentDataFolder: URL?
    
    private var captureTimer: Timer?
    private let captureInterval: TimeInterval = 1
    
    private var captureTimerSensor: Timer?
    private let captureIntervalSensor: TimeInterval = 0.01
    
    private var routePoints: [CGPoint] = []
    private var serverTrajectory: [CGPoint]?
    
    let motionManager = CMMotionManager()
    let locationManager = CLLocationManager()
    
    private var isCollecting = false
    private var frameCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Do any additional setup after loading the view.
        session = ARSession()
        session.delegate = self
        sceneView.session = session
        sceneView.delegate = self
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        
        self.stopButton.isEnabled = false
        self.stopButton.isHidden = true
        
        self.pauseButton.isEnabled = false
        self.pauseButton.isHidden = true
        
        
        // Create a new data folder
        let folderName = String(format: "%@", generateTS())
        currentDataFolder = DataManager.shared.createNewDataFolder(folderName: folderName)
        
        startARSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let folderURL = currentDataFolder {
            print("New data will be saved in: \(folderURL.path)")
        } else {
            print("Failed to create data folder")
        }
    }
    
//    MARK: Server Functions
    private func uploadDataToServer() {
        guard let currentDataFolder = self.currentDataFolder else {
            print("No current data folder")
            return
        }
        
        let transformData = readTransformData(folder: currentDataFolder)
        let imuData = readIMUData(folder: currentDataFolder)
        let gpsData = readGPSData(folder: currentDataFolder)
        let compassData = readCompassData(folder: currentDataFolder)
        
        let payload: [String: Any] = [
            "transform": transformData,
            "imu": imuData,
            "gps": gpsData,
            "compass": compassData
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: payload)
        sendJSONToServer(postUrl: algoDomain, jsonData: jsonData)
    }
    
    func sendJSONToServer(postUrl: String, jsonData: Data) {
        guard let surl = URL(string: postUrl) else {
          return
        }
        var request = URLRequest(url: surl)
        request.httpMethod = "POST"
        request.setValue("\(String(describing: jsonData.count))", forHTTPHeaderField: "Content-Length")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: Any] {
                print(responseJSON)
                let responseTRAJ = responseJSON["Trajectory"] as! Array<Array<Double>>
                DispatchQueue.main.async {
                    handleServerResponse(responseTRAJ)
                }
            }
        }.resume()
    }
    
    private func readTransformData(folder: URL) -> [[String: Any]] {
        let transformURL = folder.appendingPathComponent("Gt/transform.json")
        guard let data = try? Data(contentsOf: transformURL),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let arrayOfDicts = json as? [[String: Any]] else {
            print("Failed to read transform data")
            return []
        }
        return arrayOfDicts
    }

    private func readIMUData(folder: URL) -> [[String: Any]] {
        let imuURL = folder.appendingPathComponent("Sensor/imu.txt")
        guard let contents = try? String(contentsOf: imuURL) else {
            print("Failed to read IMU data")
            return []
        }
        
        return contents.components(separatedBy: .newlines).compactMap { line -> [String: Any]? in
            let components = line.components(separatedBy: ",")
            guard components.count == 16,
                  let timestamp = Double(components[0]),
                  let roll = Double(components[1]),
                  let pitch = Double(components[2]),
                  let yaw = Double(components[3]),
                  let rotationX = Double(components[4]),
                  let rotationY = Double(components[5]),
                  let rotationZ = Double(components[6]),
                  let gravityX = Double(components[7]),
                  let gravityY = Double(components[8]),
                  let gravityZ = Double(components[9]),
                  let userAccX = Double(components[10]),
                  let userAccY = Double(components[11]),
                  let userAccZ = Double(components[12]),
                  let magnetoX = Double(components[13]),
                  let magnetoY = Double(components[14]),
                  let magnetoZ = Double(components[15]) else {
                return nil
            }
            
            // Transform to the desired output format
            return [
                "timestamp": timestamp,
                "roll": roll,
                "pitch": pitch,
                "yaw": yaw,
                "rotationRate": ["x": rotationX, "y": rotationY, "z": rotationZ],
                "gravity": ["x": gravityX, "y": gravityY, "z": gravityZ],
                "userAcceleration": ["x": userAccX, "y": userAccY, "z": userAccZ],
                "magneticField": ["x": magnetoX, "y": magnetoY, "z": magnetoZ]
            ]
        }
    }
    
    private func readGPSData(folder: URL) -> [[String: Double]] {
        let gpsURL = folder.appendingPathComponent("GPS/gps.txt")
        guard let contents = try? String(contentsOf: gpsURL) else {
            print("Failed to read GPS data")
            return []
        }
        
        return contents.components(separatedBy: .newlines).compactMap { line -> [String: Double]? in
            let components = line.components(separatedBy: ",")
            guard components.count == 6,
                  let timestamp = Double(components[0]),
                  let latitude = Double(components[1]),
                  let longitude = Double(components[2]),
                  let altitude = Double(components[3]),
                  let verticalAccuracy = Double(components[4]),
                  let horizontalAccuracy = Double(components[5]) else {
                return nil
            }
            
            return [
                "timestamp": timestamp,
                "latitude": latitude,
                "longitude": longitude,
                "altitude": altitude,
                "verticalAccuracy": verticalAccuracy,
                "horizontalAccuracy": horizontalAccuracy
            ]
        }
    }
    
    private func readCompassData(folder: URL) -> [[String: Double]] {
        let compassURL = folder.appendingPathComponent("GPS/compass.txt")
        guard let contents = try? String(contentsOf: compassURL) else {
            print("Failed to read compass data")
            return []
        }
        
        return contents.components(separatedBy: .newlines).compactMap { line -> [String: Double]? in
            let components = line.components(separatedBy: ",")
            guard components.count == 4,
                  let timestamp = Double(components[0]),
                  let x = Double(components[1]),
                  let y = Double(components[2]),
                  let z = Double(components[3]) else {
                return nil
            }
            
            return [
                "timestamp": timestamp,
                "x": x,
                "y": y,
                "z": z
            ]
        }
    }
    
    
//    MARK: IBActions
    @IBAction func StartClicked(_ sender: UIButton) {
        print("StartClicked was tapped!")
        
        self.startButton.isEnabled = false
        self.startButton.isHidden = true
        
        self.pauseButton.isEnabled = true
        self.pauseButton.isHidden = false
        
        self.stopButton.isEnabled = true
        self.stopButton.isHidden = false
        
        frameCount = 0
        isCollecting = true
        startCaptureTimer()
        print("Started collecting data")
    }
    
    @IBAction func PauseClicked(_ sender: UIButton) {
        print("PauseClicked was tapped!")
        if (self.isCollecting) {
            self.isCollecting = false
            
            let pausedButtonImage = UIImage(systemName: "pause.fill")
            sender.setImage(pausedButtonImage, for: .normal)
        } else {
            self.isCollecting = true
            
            let pausedButtonImage = UIImage(systemName: "playpause.circle.fill")
            sender.setImage(pausedButtonImage, for: .normal)
        }
    }
    
    @IBAction func SaveClicked(_ sender: UIButton) {
        print("SaveClicked was tapped!")
        
        self.startButton.isEnabled = true
        self.startButton.isHidden = false
        
        self.pauseButton.isEnabled = false
        self.pauseButton.isHidden = true
        
        self.stopButton.isEnabled = false
        self.stopButton.isHidden = true
        
        isCollecting = false
        stopCaptureTimer()
        print("Stop collecting data")
        
        logView.text = "Start Uploading data to server..."
        uploadDataToServer()
    }
    
//    MARK: ImageView Operations
    func handleServerResponse(_ responseTRAJ: [[Double]]?) {
        guard let responseTRAJ = responseTRAJ, responseTRAJ.count >= 2 else {
            serverTrajectory = nil
            drawRoute()
            return
        }

        var newServerTrajectory = responseTRAJ.compactMap { point -> CGPoint? in
            guard point.count >= 2 else { return nil }
            return CGPoint(x: CGFloat(point[0]), y: CGFloat(point[1]))
        }

        guard newServerTrajectory.count >= 2, routePoints.count >= 2 else {
            serverTrajectory = newServerTrajectory
            drawRoute()
            return
        }

        // Align the first and last points of the server trajectory with the route points
        let firstRoutePoint = routePoints.first!
        let lastRoutePoint = routePoints.last!
        let firstServerPoint = newServerTrajectory.first!
        let lastServerPoint = newServerTrajectory.last!

        // Calculate scale and translation
        let scaleX = (lastRoutePoint.x - firstRoutePoint.x) / (lastServerPoint.x - firstServerPoint.x)
        let scaleY = (lastRoutePoint.y - firstRoutePoint.y) / (lastServerPoint.y - firstServerPoint.y)
        let translateX = firstRoutePoint.x - (firstServerPoint.x * scaleX)
        let translateY = firstRoutePoint.y - (firstServerPoint.y * scaleY)

        // Apply transformation to all server trajectory points
        newServerTrajectory = newServerTrajectory.map { point in
            CGPoint(x: point.x * scaleX + translateX,
                    y: point.y * scaleY + translateY)
        }

        // Update serverTrajectory property
        self.serverTrajectory = newServerTrajectory

        drawRoute()
    }
    
    
    func updateAndDrawRoute(with transform: matrix_float4x4) {
        // Extract the position from the transformation matrix
        let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
        
        // Add the new position to the route
        routePoints.append(position)
        
        // Draw the route
        drawRoute()
    }
    
    func drawRoute() {
        let renderer = UIGraphicsImageRenderer(size: imageView.bounds.size)
        
        let img = renderer.image { ctx in
            let context = ctx.cgContext
            
            // Calculate the scale and offset
            let (scale, offset) = calculateScaleAndOffset()
            
            // Start from the center of the image
            let centerX = imageView.bounds.width / 2
            let centerY = imageView.bounds.height / 2
            
            // Draw the original route
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(2.0)
            
            if let firstPoint = routePoints.first {
                let x = centerX + (firstPoint.x * scale) + offset.x
                let y = centerY + (firstPoint.y * scale) + offset.y
                context.move(to: CGPoint(x: x, y: y))
            }
            
            for point in routePoints.dropFirst() {
                let x = centerX + (point.x * scale) + offset.x
                let y = centerY + (point.y * scale) + offset.y
                context.addLine(to: CGPoint(x: x, y: y))
            }
            
            context.strokePath()
            
            // Draw the server trajectory in a different color
            if let serverTrajectory = serverTrajectory {
                context.setStrokeColor(UIColor.blue.cgColor)
                context.setLineWidth(2.0)
                
                if let firstPoint = serverTrajectory.first {
                    let x = centerX + (firstPoint.x * scale) + offset.x
                    let y = centerY + (firstPoint.y * scale) + offset.y
                    context.move(to: CGPoint(x: x, y: y))
                }
                
                for point in serverTrajectory.dropFirst() {
                    let x = centerX + (point.x * scale) + offset.x
                    let y = centerY + (point.y * scale) + offset.y
                    context.addLine(to: CGPoint(x: x, y: y))
                }
                
                context.strokePath()
            }
        }
        
        imageView.image = img
    }

    func calculateScaleAndOffset() -> (scale: CGFloat, offset: CGPoint) {
        let allPoints = routePoints + (serverTrajectory ?? [])
        guard !allPoints.isEmpty else { return (1.0, .zero) }
        
        let minX = allPoints.map { $0.x }.min()!
        let maxX = allPoints.map { $0.x }.max()!
        let minY = allPoints.map { $0.y }.min()!
        let maxY = allPoints.map { $0.y }.max()!
        
        let width = maxX - minX
        let height = maxY - minY
        
        let scaleX = (imageView.bounds.width * 0.8) / width
        let scaleY = (imageView.bounds.height * 0.8) / height
        
        let scale = min(scaleX, scaleY)
        
        let offsetX = -((maxX + minX) / 2) * scale
        let offsetY = -((maxY + minY) / 2) * scale
        
        return (scale, CGPoint(x: offsetX, y: offsetY))
    }
    
//    MARK: ARSessionDelegate method
    func startARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("AR World Tracking is not supported on this device.")
            return
        }

        let configuration = ARWorldTrackingConfiguration()

        // Enable LiDAR and scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            print("LiDAR and mesh scene reconstruction enabled.")
        } else {
            print("This device does not support LiDAR and mesh scene reconstruction.")
        }

        // Enable depth information
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            print("Depth information enabled.")
        } else {
            print("This device does not support depth information.")
        }
        
        if #available(iOS 14.0, *) {
            configuration.sceneReconstruction = .meshWithClassification
            
            // Find the highest resolution video format
            if let highestResolutionFormat = ARWorldTrackingConfiguration.supportedVideoFormats.max(by: {
                $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height
            }) {
                configuration.videoFormat = highestResolutionFormat
                print("Selected video format: \(highestResolutionFormat.imageResolution.width)x\(highestResolutionFormat.imageResolution.height) at \(highestResolutionFormat.framesPerSecond) FPS")
                
                depthMapWidth = Int(configuration.videoFormat.imageResolution.width)
                depthMapHeight = Int(configuration.videoFormat.imageResolution.height)
                print("Using resolution: \(depthMapWidth)x\(depthMapHeight)")
            }
        }
        depthMapWidth = Int(depthMapWidth/2)
        depthMapHeight = Int(depthMapHeight/2)

        // Enable environment texturing for better lighting estimation
        configuration.environmentTexturing = .automatic

        // Enable world alignment for more accurate positioning
        configuration.worldAlignment = .gravity

        // Set up session delegate for handling frame updates and errors
        sceneView.session.delegate = self

        // Run the session with the new configuration
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        print("AR session started with configuration: \(configuration)")
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session failed: \(error.localizedDescription)")
        if let arError = error as? ARError {
            switch arError.code {
            case .sensorUnavailable:
                print("Sensor unavailable. This could affect point cloud data.")
            case .sensorFailed:
                print("Sensor failed. This could affect point cloud data.")
            default:
                print("AR Session failed with error code: \(arError.code.rawValue)")
            }
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR Session was interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR Session interruption ended")
    }
    
    func saveTransformation(from frame: ARFrame, timestamp ts: Double, timestamp_str time_st: String, safeFileName: String) {
        
        let rgb_safeFileName = "images/rgb_\(time_st).png"
        let depth_safeFileName = "depth/depth_\(time_st).png"
        
        let manifest_frame = [
//            "filePath": rgb_safeFileName,
//            "depthPath": depth_safeFileName,
            "transformMatrix": arrayFromTransform(frame.camera.transform),
            "timestamp_relative": frame.timestamp,
            "timestamp": ts,
            "flX":  frame.camera.intrinsics[0, 0],
            "flY":  frame.camera.intrinsics[1, 1],
            "camera_angle_x": focal2fov(focal: frame.camera.intrinsics[0, 0], pixels: Int(frame.camera.imageResolution.width)),
            "camera_angle_y": focal2fov(focal: frame.camera.intrinsics[1, 1], pixels: Int(frame.camera.imageResolution.height)),
            "cx":  frame.camera.intrinsics[2, 0],
            "cy":  frame.camera.intrinsics[2, 1],
            "w": Int(frame.camera.imageResolution.width),
            "h": Int(frame.camera.imageResolution.height)
        ] as [String : Any]
        
        let save_dir =  DataManager.shared.getSubFolderURL(mainFolder: currentDataFolder!, subFolder: DataManager.SubFolder.gt)
        DataManager.shared.appendDictionaryToJSONFile(dictionary: manifest_frame, fileName: safeFileName, in: save_dir)
        
        DispatchQueue.main.async {
            self.updateAndDrawRoute(with: frame.camera.transform)
        }
    }
    
//    MARK: Private Functions
    private func generateTS() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let safeFileName = (dateFormatter.string(from: Date()))
        return safeFileName
    }
    
    func arrayFromTransform(_ transform: matrix_float4x4) -> [[Float]] {
        var array: [[Float]] = Array(repeating: Array(repeating:Float(), count: 4), count: 4)
        array[0] = [transform.columns.0.x, transform.columns.1.x, transform.columns.2.x, transform.columns.3.x]
        array[1] = [transform.columns.0.y, transform.columns.1.y, transform.columns.2.y, transform.columns.3.y]
        array[2] = [transform.columns.0.z, transform.columns.1.z, transform.columns.2.z, transform.columns.3.z]
        array[3] = [transform.columns.0.w, transform.columns.1.w, transform.columns.2.w, transform.columns.3.w]
        return array
    }
    
    func extractTranslationAndRotation(from frame: ARFrame) -> (translation: SIMD3<Float>, rotation: simd_quatf) {
        let transform = frame.camera.transform
        
        // Extract translation
        let translation = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        
        // Extract rotation
        let rotation = simd_quatf(transform)
        
        return (translation, rotation)
    }

    // Helper function to convert rotation matrix to quaternion
    func simd_quaternion(_ matrix: simd_float3x3) -> simd_float4 {
        let trace = matrix.columns.0[0] + matrix.columns.1[1] + matrix.columns.2[2]
        
        if trace > 0 {
            let s = 0.5 / sqrt(trace + 1.0)
            let w = 0.25 / s
            let x = (matrix.columns.2[1] - matrix.columns.1[2]) * s
            let y = (matrix.columns.0[2] - matrix.columns.2[0]) * s
            let z = (matrix.columns.1[0] - matrix.columns.0[1]) * s
            return simd_float4(x, y, z, w)
        } else {
            if matrix.columns.0[0] > matrix.columns.1[1] && matrix.columns.0[0] > matrix.columns.2[2] {
                let s = 2.0 * sqrt(1.0 + matrix.columns.0[0] - matrix.columns.1[1] - matrix.columns.2[2])
                let w = (matrix.columns.2[1] - matrix.columns.1[2]) / s
                let x = 0.25 * s
                let y = (matrix.columns.0[1] + matrix.columns.1[0]) / s
                let z = (matrix.columns.0[2] + matrix.columns.2[0]) / s
                return simd_float4(x, y, z, w)
            } else if matrix.columns.1[1] > matrix.columns.2[2] {
                let s = 2.0 * sqrt(1.0 + matrix.columns.1[1] - matrix.columns.0[0] - matrix.columns.2[2])
                let w = (matrix.columns.0[2] - matrix.columns.2[0]) / s
                let x = (matrix.columns.0[1] + matrix.columns.1[0]) / s
                let y = 0.25 * s
                let z = (matrix.columns.1[2] + matrix.columns.2[1]) / s
                return simd_float4(x, y, z, w)
            } else {
                let s = 2.0 * sqrt(1.0 + matrix.columns.2[2] - matrix.columns.0[0] - matrix.columns.1[1])
                let w = (matrix.columns.1[0] - matrix.columns.0[1]) / s
                let x = (matrix.columns.0[2] + matrix.columns.2[0]) / s
                let y = (matrix.columns.1[2] + matrix.columns.2[1]) / s
                let z = 0.25 * s
                return simd_float4(x, y, z, w)
            }
        }
    }
    
    func focal2fov(focal: Float, pixels: Int) -> Float {
        return 2 * atan(Float(pixels)/2.0*focal);
    }
    
//    MARK: Capture Functions
        private func startCaptureTimer() {
            
            motionManager.startAccelerometerUpdates()
            motionManager.startGyroUpdates()
            motionManager.startMagnetometerUpdates()
            motionManager.startDeviceMotionUpdates()
            
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            
            captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
                guard let self = self, let frame = self.sceneView.session.currentFrame else { return }
                processFrame(frame)
            }
            
            captureTimerSensor = Timer.scheduledTimer(withTimeInterval: captureIntervalSensor, repeats: true) { [self]_ in
                processSensor()
            }
        }
        
        private func stopCaptureTimer() {
            
            self.logView.text = "stopped"

            captureTimer?.invalidate()
            captureTimer = nil
            
            captureTimerSensor?.invalidate()
            captureTimerSensor = nil
            
            motionManager.stopAccelerometerUpdates()
            motionManager.stopGyroUpdates()
            motionManager.stopMagnetometerUpdates()
            motionManager.stopDeviceMotionUpdates()

            self.locationManager.stopUpdatingLocation()
            self.locationManager.stopUpdatingHeading()
            
        }
        
        func processFrame(_ frame: ARFrame) {
            
            depthMapWidth = Int(frame.camera.imageResolution.width)
            depthMapHeight = Int(frame.camera.imageResolution.height)
            
            DispatchQueue.global(qos: .userInitiated).async {
                if (self.isCollecting) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    let safeTS = dateFormatter.string(from: Date())
                    let timestamp = NSDate().timeIntervalSince1970 * 1000
                    self.saveTransformation(from: frame, timestamp: timestamp, timestamp_str: safeTS, safeFileName: "transform.json")
                }
            }
            
            if self.isCollecting {
                frameCount += 1
                self.logView.text = String(format: "%d frames", frameCount)
            }
        }
        
        func processSensor() {
            DispatchQueue.global(qos: .userInitiated).async {
                
                if (self.isCollecting) {
                    if (self.motionManager.isAccelerometerActive
                        && self.motionManager.isGyroActive
                        && self.motionManager.isDeviceMotionActive
                        && self.motionManager.isMagnetometerActive
                        
                        && self.motionManager.isAccelerometerAvailable
                        && self.motionManager.isGyroAvailable
                        && self.motionManager.isDeviceMotionAvailable
                        && self.motionManager.isMagnetometerAvailable
                    ) {
                        let timestamp = NSDate().timeIntervalSince1970 * 1000
                        
                        let accelerometerData = self.motionManager.deviceMotion?.userAcceleration
                        let rotationRate = self.motionManager.deviceMotion?.rotationRate
                        let gyroData = self.motionManager.gyroData?.rotationRate
                        let attitudeData = self.motionManager.deviceMotion?.attitude
                        let gravityData = self.motionManager.deviceMotion?.gravity
                        let magData = self.motionManager.magnetometerData?.magneticField
                        
                        if (accelerometerData != nil
                        && rotationRate != nil
                        && gyroData != nil
                        && attitudeData != nil
                        && gravityData != nil
                        && magData != nil) {
                            
                            let save_string =
                            String(format: "%ld,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                                   Int(timestamp),
                                   attitudeData!.roll, attitudeData!.pitch, attitudeData!.yaw,
                                   rotationRate!.x, rotationRate!.y, rotationRate!.z,
                                   gravityData!.x, gravityData!.y, gravityData!.z,
                                   accelerometerData!.x, accelerometerData!.y, accelerometerData!.z,
                                   magData!.x, magData!.y, magData!.z)
                            
                            let save_dir =  DataManager.shared.getSubFolderURL(mainFolder: self.currentDataFolder!, subFolder: DataManager.SubFolder.sensor)
                            DataManager.shared.appendStringToFile(save_string, fileName: "imu.txt", in: save_dir)
                            
                        }
                    }
                }
            }
        }
    
//    MARK: CoreLocation Delegate Functions
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let timestamp = NSDate().timeIntervalSince1970 * 1000
        let gpsCache = String(format: "%@,%@,%@,%@,%@", String(timestamp), String(location.coordinate.latitude), String(location.coordinate.longitude), String(location.altitude), String(location.verticalAccuracy), String(location.horizontalAccuracy))
        
        let save_dir =  DataManager.shared.getSubFolderURL(mainFolder: currentDataFolder!, subFolder: DataManager.SubFolder.gps)
        let safeFileName = "gps.txt"
        
        DataManager.shared.appendStringToFile(gpsCache, fileName: safeFileName, in: save_dir)
//        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        
        let timestamp = NSDate().timeIntervalSince1970 * 1000
        let headingCache = String(format: "%@,%@,%@,%@", String(timestamp), String(newHeading.x), String(newHeading.y), String(newHeading.z))
        
        let save_dir =  DataManager.shared.getSubFolderURL(mainFolder: currentDataFolder!, subFolder: DataManager.SubFolder.gps)
        let safeFileName = "compass.txt"
        DataManager.shared.appendStringToFile(headingCache, fileName: safeFileName, in: save_dir)

    }
    
    
}

