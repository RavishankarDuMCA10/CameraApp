//
//  CameraController.swift
//  CameraApp
//
//  Created by Ravi Shankar on 8/7/18.
//  Copyright © 2018 Ravi Shankar. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import CoreMedia

protocol CameraControllerDelegate:class {
    func capturedImage(image: UIImage)
}

class CameraController: UIViewController {
    
    
    private var detector: CIDetector?
    private var glkView:GLKView!
    private var ciContext: CIContext!
    private var videoDisplayViewBounds: CGRect!
    private var captureSession: AVCaptureSession!
    weak var delegate: CameraControllerDelegate?
    private var ciImage:CIImage? = nil
    private var capturedFeatures:[CIFeature]? = nil
    
    private var captureImageTimer:Timer = Timer()
    
    private lazy var rectDetector: CIDetector =
        {
            return CIDetector(ofType: CIDetectorTypeRectangle,
                              context: self.ciContext,
                              options: [CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorAspectRatio: 1.0])!
            }()

    private let sampleBufferQueue = DispatchQueue.global(qos: .userInteractive)
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureGLKView()
    }
    
    func configureGLKView() {
        glkView = GLKView(frame: self.view.bounds, context: EAGLContext(api: .openGLES2)!)
        glkView.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
        glkView.frame = self.view.bounds
        self.view.addSubview(glkView)
        self.view.sendSubview(toBack: glkView)
        
        ciContext = CIContext(eaglContext: glkView.context)
        
        glkView.bindDrawable()
        videoDisplayViewBounds = CGRect(x: 200, y: 0, width: glkView.drawableWidth - 500, height: glkView.drawableHeight)
        initCaptureSession()
    }

    func initCaptureSession()
    {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        
        guard captureSession.inputs.isEmpty else { return }
        var defaultVideoDevice: AVCaptureDevice?
        
        // Choose the back dual camera if available, otherwise default to a wide angle camera.
        if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            defaultVideoDevice = dualCameraDevice
        } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            // If the back dual camera is not available, default to the back wide angle camera.
            defaultVideoDevice = backCameraDevice
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
            captureSession.addInput(cameraInput)
            
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_32BGRA] as! [String : Any]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            
            let connection = videoOutput.connection(with: AVFoundation.AVMediaType.video)
            connection?.videoOrientation = .portrait
            
            if captureSession.canAddOutput(videoOutput)
            {
                captureSession.addOutput(videoOutput)
            }
            
            detector = prepareRectangleDetector()
            
            captureSession.startRunning()
            
        } catch let e {
            print("Error creating capture session: \(e)")
            return
        }
    }

    func prepareRectangleDetector() -> CIDetector {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorAspectRatio: 1.0]
        return CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: options)!
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}



extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Force the type change - pass through opaque buffer
        let opaqueBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer).toOpaque()
        let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueBuffer).takeUnretainedValue()
        
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        
        // Do some detection on the image
        let detectionResult = performRectangleDetection(image: sourceImage)
        
        var outputImage = sourceImage
        if detectionResult != nil {
            outputImage = detectionResult!
        }
        
        // Do some clipping
        var drawFrame = outputImage.extent
        let imageAR = drawFrame.width / drawFrame.height
        let viewAR = videoDisplayViewBounds.width / videoDisplayViewBounds.height
        if imageAR > viewAR {
            drawFrame.origin.x += (drawFrame.width - drawFrame.height * viewAR) / 2.0
            drawFrame.size.width = drawFrame.height / viewAR
        } else {
            drawFrame.origin.y += (drawFrame.height - drawFrame.width / viewAR) / 2.0
            drawFrame.size.height = drawFrame.width / viewAR
        }
        
        glkView.bindDrawable()
        if glkView.context != EAGLContext.current() {
            EAGLContext.setCurrent(glkView.context)
        }
        
        // clear eagl view to black
        glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(0x00004000)
        
        // set the blend mode to "source over" so that CI will use that
        glEnable(0x0BE2);
        glBlendFunc(1, 0x0303);
        
        ciContext.draw(outputImage, in: videoDisplayViewBounds, from: drawFrame)
        
        glkView.display()
    }
    
    func performRectangleDetection(image: CIImage) -> CIImage? {
        var resultImage: CIImage?
        if let detector = detector {
            // Get the detections
            let features = detector.features(in: image)
            if !features.isEmpty {
                ciImage = image
                capturedFeatures = features
                
                if !(captureImageTimer.isValid) {
                    DispatchQueue.main.async {
                        self.captureImageTimer = Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(self.captureImageAction(_:)), userInfo: nil, repeats: false)
                    }
                }

                for feature in features as! [CIRectangleFeature] {
                    resultImage = drawHighlightOverlayForPoints(image: image, topLeft: feature.topLeft, topRight: feature.topRight,
                                                            bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
                }
            } else {
                ciImage = nil
                capturedFeatures = nil
            }
        }
        return resultImage
    }
    
    func drawHighlightOverlayForPoints(image: CIImage, topLeft: CGPoint, topRight: CGPoint,
                                       bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        var overlay = CIImage(color: CIColor(red: 17/255, green: 231/255, blue: 255/255, alpha: 0.5))
        overlay = overlay.cropped(to: image.extent)
        overlay = overlay.applyingFilter("CIPerspectiveTransformWithExtent",
                                         parameters: [
                                                    "inputExtent": CIVector(cgRect: image.extent),
                                                    "inputTopLeft": CIVector(cgPoint: topLeft),
                                                    "inputTopRight": CIVector(cgPoint: topRight),
                                                    "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                                                    "inputBottomRight": CIVector(cgPoint: bottomRight)
            ])
        return overlay.composited(over: image)
    }

    
    func imagePerspectiveCorrection(image: CIImage, topLeft: CGPoint, topRight: CGPoint,bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        
        return image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight)
            ])
        
    }
    
    @objc func captureImageAction(_:Timer) {
        
        var resultImage: UIImage?
        if let features = capturedFeatures {
            if let capturedImage = ciImage {
                for feature in features as! [CIRectangleFeature] {
                    
                    let correctedImage:CIImage =  self.imagePerspectiveCorrection(image: capturedImage, topLeft: feature.topLeft, topRight: feature.topRight,bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)

                    UIGraphicsBeginImageContext(CGSize(width: correctedImage.extent.size.height, height: correctedImage.extent.size.width))
                    UIImage(ciImage:correctedImage,scale:1.0,orientation:.right).draw(in: CGRect(x: 0, y: 0, width: correctedImage.extent.size.height, height: correctedImage.extent.size.width))
                    
                    resultImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()

                }
                if let image = resultImage {
                    captureSession.stopRunning()
                    delegate?.capturedImage(image: image)
                    captureImageTimer.invalidate()
                    self.dismiss(animated: true, completion: nil)
                }
            }
        }
    }
}
