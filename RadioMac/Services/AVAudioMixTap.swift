import AVFoundation
import AudioToolbox
import MediaToolbox

/// Owns the native equalizer for one AVPlayer audio tap.
final class NativeTapContext: @unchecked Sendable {
    let equalizer: NativeEqualizer

    init(equalizer: NativeEqualizer) {
        self.equalizer = equalizer
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && format.mBitsPerChannel == 32
        let nonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        equalizer.setFormat(
            sampleRate: Int(format.mSampleRate),
            channels: Int(format.mChannelsPerFrame),
            nonInterleaved: nonInterleaved,
            isFloat: isFloat
        )
    }

    func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        equalizer.process(bufferList: bufferList, frames: frames)
    }
}

private func nativeTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ storageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    storageOut.pointee = clientInfo
}

private func nativeTapFinalize(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<NativeTapContext>.fromOpaque(storage).release()
}

private func nativeTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ format: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<NativeTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.prepare(format.pointee)
}

private func nativeTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func nativeTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    guard status == noErr, numberFramesOut.pointee > 0 else { return }
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<NativeTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.process(bufferListInOut, frames: Int(numberFramesOut.pointee))
}

enum AudioMixTapFactory {
    static func make(
        track: AVAssetTrack,
        equalizer: NativeEqualizer
    ) -> (mix: AVAudioMix, tap: MTAudioProcessingTap)? {
        let context = NativeTapContext(equalizer: equalizer)
        let clientInfo = Unmanaged.passRetained(context).toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: nativeTapInit,
            finalize: nativeTapFinalize,
            prepare: nativeTapPrepare,
            unprepare: nativeTapUnprepare,
            process: nativeTapProcess
        )

        var tap: MTAudioProcessingTap?
        let status: OSStatus
#if compiler(>=6.2)
        status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
#else
        // Xcode 16 imports the out-parameter as Unmanaged.
        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &unmanagedTap
        )
        if let unmanagedTap {
            tap = unmanagedTap.takeRetainedValue()
        }
#endif
        guard status == noErr, let tap else {
            Unmanaged<NativeTapContext>.fromOpaque(clientInfo).release()
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return (mix, tap)
    }
}
