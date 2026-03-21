import Foundation
import os

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "DirectoryMonitor")

/// Watches directories for filesystem changes using FSEvents and calls a handler.
final class DirectoryMonitor: Sendable {
    private let paths: [String]
    private let handler: @Sendable () -> Void

    private nonisolated(unsafe) var stream: FSEventStreamRef?
    private nonisolated(unsafe) var retainedBox: Unmanaged<CallbackBox>?

    init(directories: [URL], handler: @escaping @Sendable () -> Void) {
        self.paths = directories.map { $0.path(percentEncoded: false) }
        self.handler = handler
    }

    func start() {
        guard stream == nil else {
            logger.notice("already started")
            return
        }
        logger.notice("starting for paths: \(self.paths)")

        let box = Unmanaged.passRetained(CallbackBox(handler))
        let context = UnsafeMutableRawPointer(box.toOpaque())

        var fsContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let newStream = FSEventStreamCreate(
            nil,
            DirectoryMonitor.callback,
            &fsContext,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1-second latency before coalescing events
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            box.release()
            return
        }

        retainedBox = box
        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(newStream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        retainedBox?.release()
        retainedBox = nil
    }

    deinit {
        stop()
    }

    // MARK: - FSEvents callback

    private static let callback: FSEventStreamCallback = {
        _, clientCallBackInfo, _, _, _, _ in
        guard let info = clientCallBackInfo else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
        logger.notice("FSEvent fired")
        box.handler()
    }
}

/// Box to pass the handler closure through the C callback context pointer.
private final class CallbackBox: Sendable {
    let handler: @Sendable () -> Void
    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}
