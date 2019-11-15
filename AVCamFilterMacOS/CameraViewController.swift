/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The view controller for the AVCamFilter camera interface.
*/

import Cocoa
import AVFoundation

class CameraViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
  @IBOutlet weak private var previewView: PreviewMetalView!
  private let captureSession = AVCaptureSession()
  private var videoInput: AVCaptureDeviceInput!
  private let videoDataOutput = AVCaptureVideoDataOutput()
  private var videoFilter = RosyMetalRenderer()
  private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
  private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
  private var renderingEnabled = true
  private var isSessionRunning = false

  private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
  }

  private var setupResult: SessionSetupResult = .success
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
          // The user has previously granted access to the camera
          break

        case .notDetermined:
          /*
           The user has not yet been presented with the option to grant video access
           Suspend the SessionQueue to delay session setup until the access request has completed
           */
          sessionQueue.suspend()
          AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
            if !granted {
              self.setupResult = .notAuthorized
            }
            self.sessionQueue.resume()
          })

        default:
          // The user has previously denied access
          setupResult = .notAuthorized
      }

      sessionQueue.async {
        self.configureSession()
      }
    }
    
    override func viewWillAppear() {
      super.viewWillAppear()

      sessionQueue.async {
        switch self.setupResult {
          case .success:
            self.dataOutputQueue.async {
              self.renderingEnabled = true
            }

            self.captureSession.startRunning()
            self.isSessionRunning = self.captureSession.isRunning
          case .notAuthorized:
            NSLog("Not authorized")
          case .configurationFailed:
            NSLog("Configuration failed")
        }
      }
    }
    
    override func viewWillDisappear() {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.captureSession.stopRunning()
                self.isSessionRunning = self.captureSession.isRunning
            }
        }
    }
    
    // MARK: - Session Management
    
    // Call this on the SessionQueue
    private func configureSession() {
      if setupResult != .success {
        return
      }

      let defaultVideoDevice = AVCaptureDevice.default(for: AVMediaType.video)

      guard let videoDevice = defaultVideoDevice else {
        print("Could not find any video device")
        setupResult = .configurationFailed
        return
      }

      do {
        videoInput = try AVCaptureDeviceInput(device: videoDevice)
      } catch {
        print("Could not create video device input: \(error)")
        setupResult = .configurationFailed
        return
      }

      let formatDescription = videoDevice.activeFormat.formatDescription
      let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
      let resolution = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
      DispatchQueue.main.async {
        self.view.window?.contentAspectRatio = resolution
      }

      captureSession.beginConfiguration()

      //    captureSession.sessionPreset = AVCaptureSession.Preset.low

      guard captureSession.canAddInput(videoInput) else {
        print("Could not add video device input to the session")
        setupResult = .configurationFailed
        captureSession.commitConfiguration()
        return
      }
      captureSession.addInput(videoInput)

      if captureSession.canAddOutput(videoDataOutput) {
        captureSession.addOutput(videoDataOutput)
        videoDataOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
          kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
      } else {
        print("Could not add video data output to the session")
        setupResult = .configurationFailed
        captureSession.commitConfiguration()
        return
      }

      captureSession.commitConfiguration()
    }
    
    // MARK: - Video Data Output Delegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processVideo(sampleBuffer: sampleBuffer)
    }
    
  func processVideo(sampleBuffer: CMSampleBuffer) {
    if !renderingEnabled {
      return
    }

    guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        return
    }

    var finalVideoPixelBuffer = videoPixelBuffer

    if !videoFilter.isPrepared {
      /*
       outputRetainedBufferCountHint is the number of pixel buffers the renderer retains. This value informs the renderer
       how to size its buffer pool and how many pixel buffers to preallocate. Allow 3 frames of latency to cover the dispatch_async call.
       */
      videoFilter.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
    }

    // Send the pixel buffer through the filter
    guard let filteredBuffer = videoFilter.render(pixelBuffer: finalVideoPixelBuffer) else {
      print("Unable to filter video buffer")
      return
    }

    finalVideoPixelBuffer = filteredBuffer

    previewView.pixelBuffer = finalVideoPixelBuffer
  }
}
