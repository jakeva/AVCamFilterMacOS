/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 The motion-detect filter renderer, implemented with Metal.
 */

import CoreMedia
import CoreVideo
import Metal
import MetalPerformanceShaders

class MotionDetectMetalRenderer: FilterRenderer {
  var description: String = "Motion Detect"
  var isPrepared = false
  private(set) var inputFormatDescription: CMFormatDescription?
  private(set) var outputFormatDescription: CMFormatDescription?
  private var outputPixelBufferPool: CVPixelBufferPool?
  private let metalDevice = MTLCreateSystemDefaultDevice()!
  private var computePipelineState: MTLComputePipelineState?
  private var textureCache: CVMetalTextureCache!
//  private let detectionQueue = DispatchQueue(label: "DetectionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
  

  private lazy var commandQueue: MTLCommandQueue? = {
    return self.metalDevice.makeCommandQueue()
  }()

  required init() {
    let defaultLibrary = metalDevice.makeDefaultLibrary()!
    let kernelFunction = defaultLibrary.makeFunction(name: "motionDetect")
    do {
      computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction!)
    } catch {
      print("Could not create pipeline state: \(error)")
    }
  }

  func prepare(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
    reset()

    (outputPixelBufferPool, _, outputFormatDescription) = allocateOutputBufferPool(with: formatDescription,
                                                                                   outputRetainedBufferCountHint: outputRetainedBufferCountHint)
    if outputPixelBufferPool == nil {
      return
    }
    inputFormatDescription = formatDescription

    var metalTextureCache: CVMetalTextureCache?
    if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
      assertionFailure("Unable to allocate texture cache")
    } else {
      textureCache = metalTextureCache
    }

    isPrepared = true
  }

  func reset() {
    outputPixelBufferPool = nil
    outputFormatDescription = nil
    inputFormatDescription = nil
    textureCache = nil
    isPrepared = false
  }

  /// - Tag: FilterMetalMotionDetect
  func render(lastPixelBuffer: CVPixelBuffer, currentPixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    if !isPrepared {
      assertionFailure("Invalid state: Not prepared.")
      return nil
    }

    var newPixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPixelBuffer)
    guard let outputPixelBuffer = newPixelBuffer else {
      print("Allocation failure: Could not get pixel buffer from pool. (\(self.description))")
      return nil
    }
    guard let lastFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: lastPixelBuffer, textureFormat: .bgra8Unorm),
      let currentFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: currentPixelBuffer, textureFormat: .bgra8Unorm),
      let outputTexture = makeTextureFromCVPixelBuffer(pixelBuffer: outputPixelBuffer, textureFormat: .bgra8Unorm) else {
        return nil
    }

    // Set up command queue, buffer, and encoder.
    guard let commandQueue = commandQueue,
      let commandBuffer = commandQueue.makeCommandBuffer() else {
        print("Failed to create a Metal command queue.")
        CVMetalTextureCacheFlush(textureCache!, 0)
        return nil
    }

    var newCurrentSmoothedPixelBuffer: CVPixelBuffer?
    var newPreviousSmoothedPixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newCurrentSmoothedPixelBuffer)
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPreviousSmoothedPixelBuffer)
    guard let currentSmoothedPixelBuffer = newCurrentSmoothedPixelBuffer,
      let previousSmoothedPixelBuffer = newPreviousSmoothedPixelBuffer else {
      print("Allocation failure: Could not get pixel buffer from pool. (\(self.description))")
      return nil
    }

    guard let currentSmoothedFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: currentSmoothedPixelBuffer, textureFormat: .bgra8Unorm),
      let lastSmoothedFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: previousSmoothedPixelBuffer, textureFormat: .bgra8Unorm) else {
        return nil
    }

    let gaussianBlur = MPSImageGaussianBlur.init(device: self.metalDevice, sigma: 1.5)
    gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: lastFrameTexture, destinationTexture: lastSmoothedFrameTexture)
    gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: currentFrameTexture, destinationTexture: currentSmoothedFrameTexture)

    guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
           print("Failed to create a Metal command encoder.")
           CVMetalTextureCacheFlush(textureCache!, 0)
           return nil
       }

    commandEncoder.label = "Motion Detect Metal"
    commandEncoder.setComputePipelineState(computePipelineState!)
    commandEncoder.setTexture(lastSmoothedFrameTexture, index: 0)
    commandEncoder.setTexture(currentSmoothedFrameTexture, index: 1)
    commandEncoder.setTexture(outputTexture, index: 2)

    // Set up the thread groups.
    let width = computePipelineState!.threadExecutionWidth
    let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
    let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
    let threadgroupsPerGrid = MTLSize(width: (lastFrameTexture.width + width - 1) / width,
                                      height: (lastFrameTexture.height + height - 1) / height,
                                      depth: 1)
    commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    commandEncoder.endEncoding()
    commandBuffer.commit()

    return outputPixelBuffer
  }

  func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // Create a Metal texture from the image buffer.
    var cvTextureOut: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)
    guard status == kCVReturnSuccess else {
      print(status)

      CVMetalTextureCacheFlush(textureCache, 0)
      return nil
    }

    guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
      CVMetalTextureCacheFlush(textureCache, 0)

      return nil
    }

    return texture
  }
}
