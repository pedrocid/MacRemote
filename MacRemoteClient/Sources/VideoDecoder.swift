import Foundation
import VideoToolbox
import CoreMedia
import UIKit

/// Decodes H.264 video frames received from the server
final class VideoDecoder {

    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?

    // Cached CIContext for efficient image conversion (creating per-frame is expensive)
    private let ciContext = CIContext()

    // Callback for decoded frames
    var onFrameDecoded: ((UIImage) -> Void)?

    // Track frame dimensions
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    deinit {
        cleanup()
    }

    // MARK: - Public Interface

    func decodeFrame(_ frame: ScreenFrame) {
        // Check if we need to recreate the decoder (dimensions changed or first frame)
        if frame.width != currentWidth || frame.height != currentHeight || decompressionSession == nil {
            cleanup()
            do {
                try setupDecoder(width: frame.width, height: frame.height)
                currentWidth = frame.width
                currentHeight = frame.height
            } catch {
                print("[VideoDecoder] Failed to setup decoder: \(error)")
                return
            }
        }

        // For keyframes, we might need to extract and parse SPS/PPS
        if frame.isKeyFrame {
            parseAndSetupFormatDescription(from: frame.data, width: frame.width, height: frame.height)
        }

        decodeNALUnit(frame.data, timestamp: frame.timestamp)
    }

    func cleanup() {
        if let session = decompressionSession {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
    }

    // MARK: - Private Setup

    private func setupDecoder(width: Int, height: Int) throws {
        // Create a basic format description for H.264
        // This will be updated when we receive SPS/PPS in keyframes
        var formatDesc: CMVideoFormatDescription?

        // Create a placeholder format description
        // Real SPS/PPS will be extracted from keyframes
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        guard status == noErr, let desc = formatDesc else {
            throw VideoDecoderError.formatDescriptionCreationFailed
        }

        formatDescription = desc
        try createDecompressionSession()
    }

    private func parseAndSetupFormatDescription(from data: Data, width: Int, height: Int) {
        // Try to extract SPS and PPS from the NAL units
        // H.264 NAL units in Annex B format start with 0x00 0x00 0x00 0x01 or 0x00 0x00 0x01

        var sps: Data?
        var pps: Data?

        data.withUnsafeBytes { buffer in
            guard let basePtr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let length = buffer.count

            var i = 0
            while i < length - 4 {
                // Look for start codes
                if basePtr[i] == 0x00 && basePtr[i + 1] == 0x00 {
                    var startCodeLength = 0
                    if basePtr[i + 2] == 0x01 {
                        startCodeLength = 3
                    } else if basePtr[i + 2] == 0x00 && i + 3 < length && basePtr[i + 3] == 0x01 {
                        startCodeLength = 4
                    }

                    if startCodeLength > 0 {
                        let nalStart = i + startCodeLength
                        if nalStart < length {
                            let nalType = basePtr[nalStart] & 0x1F

                            // Find the end of this NAL unit (next start code or end of data)
                            var nalEnd = length
                            for j in (nalStart + 1)..<(length - 2) {
                                if basePtr[j] == 0x00 && basePtr[j + 1] == 0x00 &&
                                   (basePtr[j + 2] == 0x01 || (j + 3 < length && basePtr[j + 2] == 0x00 && basePtr[j + 3] == 0x01)) {
                                    nalEnd = j
                                    break
                                }
                            }

                            let nalData = Data(bytes: basePtr + nalStart, count: nalEnd - nalStart)

                            if nalType == 7 { // SPS
                                sps = nalData
                            } else if nalType == 8 { // PPS
                                pps = nalData
                            }

                            i = nalEnd
                            continue
                        }
                    }
                }
                i += 1
            }
        }

        // If we found both SPS and PPS, create a proper format description
        if let spsData = sps, let ppsData = pps {
            createFormatDescription(sps: spsData, pps: ppsData)
        }
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        var formatDesc: CMVideoFormatDescription?

        sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                let spsPtr = spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let ppsPtr = ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)

                var pointers = [spsPtr, ppsPtr]
                var sizes = [sps.count, pps.count]

                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )

                if status == noErr, let desc = formatDesc {
                    // Only update if different from current
                    if self.formatDescription == nil || !CMFormatDescriptionEqual(self.formatDescription!, otherFormatDescription: desc) {
                        self.formatDescription = desc
                        do {
                            try self.createDecompressionSession()
                        } catch {
                            print("[VideoDecoder] Failed to recreate session: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func createDecompressionSession() throws {
        guard let formatDesc = formatDescription else {
            throw VideoDecoderError.noFormatDescription
        }

        // Clean up existing session
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }

        // Output buffer attributes
        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        // Create callback record
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in

                guard status == noErr, let imageBuffer = imageBuffer else {
                    if status != noErr {
                        print("[VideoDecoder] Decompression failed with status: \(status)")
                    }
                    return
                }

                // Call back on main thread with the decoder's cached context
                if let refCon = decompressionOutputRefCon {
                    let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()

                    // Convert CVPixelBuffer to UIImage using cached CIContext
                    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    if let cgImage = decoder.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        let uiImage = UIImage(cgImage: cgImage)
                        DispatchQueue.main.async {
                            decoder.onFrameDecoded?(uiImage)
                        }
                    }
                }
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )

        guard status == noErr, let newSession = session else {
            throw VideoDecoderError.decompressionSessionCreationFailed
        }

        decompressionSession = newSession
        print("[VideoDecoder] Decompression session created")
    }

    // MARK: - Decoding

    private func decodeNALUnit(_ data: Data, timestamp: UInt64) {
        guard let session = decompressionSession else {
            return
        }

        // Convert Annex B format to AVCC format if needed
        let avccData = convertAnnexBToAVCC(data)

        guard !avccData.isEmpty else {
            return
        }

        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        avccData.withUnsafeBytes { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }

            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return }

            status = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }

        guard let buffer = blockBuffer else {
            return
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccData.count
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: Int64(timestamp), timescale: 1000),
            decodeTimeStamp: .invalid
        )

        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sample = sampleBuffer else {
            return
        }

        // Decode frame
        var infoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        if decodeStatus != noErr {
            print("[VideoDecoder] Decode error: \(decodeStatus)")
        }
    }

    private func convertAnnexBToAVCC(_ data: Data) -> Data {
        // Convert from Annex B (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01 start codes)
        // to AVCC (4-byte length prefix)

        var result = Data()

        data.withUnsafeBytes { buffer in
            guard let basePtr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let length = buffer.count

            var i = 0
            while i < length {
                // Find start code
                var startCodeLength = 0
                if i + 3 < length && basePtr[i] == 0x00 && basePtr[i + 1] == 0x00 && basePtr[i + 2] == 0x00 && basePtr[i + 3] == 0x01 {
                    startCodeLength = 4
                } else if i + 2 < length && basePtr[i] == 0x00 && basePtr[i + 1] == 0x00 && basePtr[i + 2] == 0x01 {
                    startCodeLength = 3
                }

                if startCodeLength > 0 {
                    let nalStart = i + startCodeLength

                    // Find end of NAL unit
                    var nalEnd = length
                    for j in nalStart..<(length - 2) {
                        if basePtr[j] == 0x00 && basePtr[j + 1] == 0x00 {
                            if j + 2 < length && basePtr[j + 2] == 0x01 {
                                nalEnd = j
                                break
                            } else if j + 3 < length && basePtr[j + 2] == 0x00 && basePtr[j + 3] == 0x01 {
                                nalEnd = j
                                break
                            }
                        }
                    }

                    let nalLength = nalEnd - nalStart
                    if nalLength > 0 {
                        // Skip SPS (7) and PPS (8) NAL units for AVCC format
                        // They're handled separately in the format description
                        let nalType = basePtr[nalStart] & 0x1F
                        if nalType != 7 && nalType != 8 {
                            // Write 4-byte big-endian length
                            var lengthBE = UInt32(nalLength).bigEndian
                            result.append(Data(bytes: &lengthBE, count: 4))
                            result.append(Data(bytes: basePtr + nalStart, count: nalLength))
                        }
                    }

                    i = nalEnd
                } else {
                    i += 1
                }
            }
        }

        return result
    }
}

// MARK: - Errors

enum VideoDecoderError: Error, LocalizedError {
    case formatDescriptionCreationFailed
    case decompressionSessionCreationFailed
    case noFormatDescription

    var errorDescription: String? {
        switch self {
        case .formatDescriptionCreationFailed:
            return "Failed to create format description"
        case .decompressionSessionCreationFailed:
            return "Failed to create decompression session"
        case .noFormatDescription:
            return "No format description available"
        }
    }
}
