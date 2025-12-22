import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreMedia

/// Manages screen capture and H.264 encoding for streaming
@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {

    @Published var isStreaming = false
    @Published var hasScreenRecordingPermission = false

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var compressionSession: VTCompressionSession?
    private var currentQuality: RemoteMessage.StreamQuality = .medium

    // Callback for encoded frames
    var onFrameEncoded: ((ScreenFrame) -> Void)?

    // Frame timing
    private var frameCount: UInt64 = 0
    private var startTime: UInt64 = 0

    override init() {
        super.init()
        Task {
            await checkPermission()
        }
    }

    // MARK: - Permission

    func checkPermission() async {
        do {
            // This will trigger permission dialog if not granted
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            hasScreenRecordingPermission = true
        } catch {
            hasScreenRecordingPermission = false
            print("[ScreenCapture] Permission check failed: \(error)")
        }
    }

    // MARK: - Stream Control

    func startStreaming(quality: RemoteMessage.StreamQuality) async throws {
        guard !isStreaming else { return }

        currentQuality = quality

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }

        // Configure stream based on quality
        let (width, height, frameRate, bitrate) = qualitySettings(for: quality, displaySize: CGSize(width: display.width, height: display.height))

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        // Setup video encoder
        try setupEncoder(width: width, height: height, bitrate: bitrate)

        // Create stream output handler
        streamOutput = StreamOutput { [weak self] sampleBuffer in
            self?.processSampleBuffer(sampleBuffer)
        }

        // Create and start stream
        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream?.startCapture()

        frameCount = 0
        startTime = mach_absolute_time()
        isStreaming = true

        print("[ScreenCapture] Started streaming at \(width)x\(height) @ \(frameRate)fps")
    }

    func stopStreaming() async {
        guard isStreaming else { return }

        do {
            try await stream?.stopCapture()
        } catch {
            print("[ScreenCapture] Error stopping stream: \(error)")
        }

        stream = nil
        streamOutput = nil

        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }

        isStreaming = false
        print("[ScreenCapture] Stopped streaming")
    }

    // MARK: - Quality Settings

    private func qualitySettings(for quality: RemoteMessage.StreamQuality, displaySize: CGSize) -> (width: Int, height: Int, frameRate: Int, bitrate: Int) {
        let aspectRatio = displaySize.width / displaySize.height

        switch quality {
        case .low:
            let height = 480
            let width = Int(Double(height) * aspectRatio)
            return (width, height, 15, 500_000)  // 500 kbps
        case .medium:
            let height = 720
            let width = Int(Double(height) * aspectRatio)
            return (width, height, 30, 2_000_000)  // 2 Mbps
        case .high:
            let height = 1080
            let width = Int(Double(height) * aspectRatio)
            return (width, height, 30, 5_000_000)  // 5 Mbps
        }
    }

    // MARK: - Video Encoder

    private func setupEncoder(width: Int, height: Int, bitrate: Int) throws {
        // Clean up existing session
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
        }

        var session: VTCompressionSession?

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw ScreenCaptureError.encoderCreationFailed
        }

        // Configure encoder for low-latency streaming
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        // Prepare for encoding
        VTCompressionSessionPrepareToEncodeFrames(session)

        compressionSession = session
        print("[ScreenCapture] Encoder configured: \(width)x\(height), \(bitrate / 1000) kbps")
    }

    // MARK: - Frame Processing

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let session = compressionSession,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        // Request keyframe periodically (every 2 seconds at 30fps = every 60 frames)
        var properties: [String: Any]? = nil
        if frameCount % 60 == 0 {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
        }

        var infoFlags = VTEncodeInfoFlags()

        let encodeStatus = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: properties as CFDictionary?,
            infoFlagsOut: &infoFlags,
            outputHandler: { [weak self] status, infoFlags, sampleBuffer in
                guard status == noErr, let sampleBuffer = sampleBuffer else {
                    if status != noErr {
                        print("[ScreenCapture] Encode callback error: \(status)")
                    }
                    return
                }
                self?.handleEncodedFrame(sampleBuffer)
            }
        )

        if encodeStatus != noErr {
            print("[ScreenCapture] Encode error: \(encodeStatus)")
        }

        frameCount += 1
    }

    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        // Get format description for dimensions and SPS/PPS
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        // Check if keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil

        // Get frame data
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer, length > 0 else {
            return
        }

        var frameData = Data()

        // For keyframes, prepend SPS and PPS in Annex B format
        if isKeyFrame {
            // Extract SPS
            var spsSize: Int = 0
            var spsCount: Int = 0
            var spsPointer: UnsafePointer<UInt8>?

            var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: &spsPointer,
                parameterSetSizeOut: &spsSize,
                parameterSetCountOut: &spsCount,
                nalUnitHeaderLengthOut: nil
            )

            if status == noErr, let sps = spsPointer {
                // Annex B start code
                frameData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                frameData.append(Data(bytes: sps, count: spsSize))
            }

            // Extract PPS
            var ppsSize: Int = 0
            var ppsPointer: UnsafePointer<UInt8>?

            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPointer,
                parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )

            if status == noErr, let pps = ppsPointer {
                // Annex B start code
                frameData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                frameData.append(Data(bytes: pps, count: ppsSize))
            }
        }

        // Convert AVCC NAL units to Annex B format
        let avccData = Data(bytes: pointer, count: length)
        var offset = 0
        while offset < avccData.count - 4 {
            // Read 4-byte NAL unit length (big-endian)
            let nalLength = Int(avccData[offset]) << 24 |
                           Int(avccData[offset + 1]) << 16 |
                           Int(avccData[offset + 2]) << 8 |
                           Int(avccData[offset + 3])

            offset += 4

            if nalLength > 0 && offset + nalLength <= avccData.count {
                // Annex B start code
                frameData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                // NAL unit data
                frameData.append(avccData[offset..<offset + nalLength])
                offset += nalLength
            } else {
                break
            }
        }

        // Calculate timestamp in milliseconds
        let timestamp = UInt64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)

        let frame = ScreenFrame(
            data: frameData,
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            timestamp: timestamp,
            isKeyFrame: isKeyFrame
        )

        onFrameEncoded?(frame)
    }
}

// MARK: - Stream Output Handler

private class StreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}

// MARK: - Errors

enum ScreenCaptureError: Error, LocalizedError {
    case noDisplayFound
    case encoderCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for capture"
        case .encoderCreationFailed:
            return "Failed to create video encoder"
        case .permissionDenied:
            return "Screen recording permission denied"
        }
    }
}
