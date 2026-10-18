import Foundation

#if canImport(Photos)
import Photos
import Vision
#endif

/// The only Photos boundary consumed by Pastport's deterministic photo code.
public protocol PhotoLibraryReading: Sendable {
    func records(since: Date, limit: Int) async throws -> [PhotoRecord]
}

public enum PhotoLibraryError: Error, Equatable, Sendable {
    case unavailable
    case denied
    case empty
    case invalidLimit
}

/// A bounded, read-only Photos adapter. It never asks for permission and never
/// downloads an iCloud-only image. Screenshot assets contribute counts only;
/// their pixels are never passed to Vision classification.
public struct PhotoLibraryProvider: PhotoLibraryReading {
    private let read: @Sendable (Date, Int) async throws -> [PhotoRecord]

    public init() {
        self.read = { since, limit in
            try await Self.readPhotos(since: since, limit: limit)
        }
    }

    init(
        metadata: @escaping @Sendable (Date, Int) async throws -> [PhotoAssetMetadata],
        classify: @escaping @Sendable (Data) async throws -> [PhotoLabel]
    ) {
        self.read = { since, limit in
            let assets = try await metadata(since, limit)
            return try await Self.makeRecords(assets, classify: classify)
        }
    }

    public func records(since: Date, limit: Int = 500) async throws -> [PhotoRecord] {
        guard (1...500).contains(limit) else { throw PhotoLibraryError.invalidLimit }
        try Task.checkCancellation()
        let records = try await read(since, limit)
        // A source may finish successfully just as its caller is cancelled. Do not
        // publish that stale result across the public boundary.
        try Task.checkCancellation()
        guard !records.isEmpty else { throw PhotoLibraryError.empty }
        return records
    }

    #if canImport(Photos)
    private static func readPhotos(since: Date, limit: Int) async throws -> [PhotoRecord] {
        try Task.checkCancellation()
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            throw PhotoLibraryError.denied
        case .notDetermined:
            throw PhotoLibraryError.unavailable
        @unknown default:
            throw PhotoLibraryError.unavailable
        }

        let options = PHFetchOptions()
        options.fetchLimit = limit
        options.sortDescriptors = [NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: true)]
        options.predicate = NSPredicate(
            format: "%K >= %@", #keyPath(PHAsset.creationDate), since as NSDate
        )
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var records: [PhotoRecord] = []
        records.reserveCapacity(min(assets.count, limit))
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            guard let time = asset.creationDate else { continue }
            let screenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            var labels: [String] = []
            if screenshot {
                labels = []
            } else {
                do {
                    let data = try await localImageData(for: asset)
                    try Task.checkCancellation()
                    let observations = try await classifyImage(data)
                    try Task.checkCancellation()
                    labels = Self.reduceLabels(observations)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    labels = []
                }
            }
            records.append(PhotoRecord(time: time, isScreenshot: screenshot, labels: labels))
        }
        guard !records.isEmpty else { throw PhotoLibraryError.empty }
        return records
    }

    private static func classifyImage(_ data: Data) async throws -> [PhotoLabel] {
        guard #available(macOS 15, *) else { return [] }
        guard !Task.isCancelled else { throw CancellationError() }
        let observations = try await ClassifyImageRequest().perform(on: data)
        // Preserve the raw Vision observations here. Confidence filtering,
        // ordering, and capping belong solely to reduceLabels below so the
        // production and synthetic paths cannot drift.
        return observations.map { PhotoLabel(identifier: $0.identifier, confidence: $0.confidence) }
    }

    private static func localImageData(for asset: PHAsset) async throws -> Data {
        let manager = PHImageManager.default()
        let state = ImageDataRequestState(manager: manager)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let options = PHImageRequestOptions()
                options.version = .current
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = false
                let requestID = manager.requestImageDataAndOrientation(
                    for: asset, options: options
                ) { data, _, _, info in
                    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
                        state.finish(.failure(CancellationError()))
                    } else if let data {
                        state.finish(.success(data))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else {
                        state.finish(.failure(PhotoLibraryError.unavailable))
                    }
                }
                state.setRequestID(requestID)
            }
        }, onCancel: {
            state.cancel()
        })
    }

    private final class ImageDataRequestState: @unchecked Sendable {
        private let lock = NSLock()
        private let manager: PHImageManager
        private var requestID = PHInvalidImageRequestID
        private var continuation: CheckedContinuation<Data, Error>?
        private var pending: Result<Data, Error>?
        private var completed = false

        init(manager: PHImageManager) { self.manager = manager }

        func install(_ continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            if let pending {
                self.pending = nil
                lock.unlock()
                resume(pending, with: continuation)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func setRequestID(_ requestID: PHImageRequestID) {
            lock.lock()
            self.requestID = requestID
            let cancel = completed && requestID != PHInvalidImageRequestID
            lock.unlock()
            if cancel { manager.cancelImageRequest(requestID) }
        }

        func cancel() { finish(.failure(CancellationError())) }

        func finish(_ result: Result<Data, Error>) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil { pending = result }
            let requestID = self.requestID
            lock.unlock()
            if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID) }
            if let continuation { resume(result, with: continuation) }
        }

        private func resume(_ result: Result<Data, Error>, with continuation: CheckedContinuation<Data, Error>) {
            switch result {
            case .success(let data): continuation.resume(returning: data)
            case .failure(let error): continuation.resume(throwing: error)
            }
        }
    }
    #else
    private static func readPhotos(since: Date, limit: Int) async throws -> [PhotoRecord] {
        throw PhotoLibraryError.unavailable
    }
    #endif

    private static func makeRecords(
        _ assets: [PhotoAssetMetadata],
        classify: @Sendable (Data) async throws -> [PhotoLabel]
    ) async throws -> [PhotoRecord] {
        var records: [PhotoRecord] = []
        records.reserveCapacity(assets.count)
        for asset in assets {
            try Task.checkCancellation()
            let labels: [String]
            if asset.isScreenshot {
                labels = []
            } else if let data = asset.imageData, !data.isEmpty {
                do {
                    let observations = try await classify(data)
                    try Task.checkCancellation()
                    labels = Self.reduceLabels(observations)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    labels = []
                }
            } else {
                labels = []
            }
            records.append(PhotoRecord(time: asset.time, isScreenshot: asset.isScreenshot, labels: labels))
        }
        guard !records.isEmpty else { throw PhotoLibraryError.empty }
        return records
    }

    /// Keep production Vision output and injected test output under the same
    /// confidence, ordering, and cardinality contract.
    static func reduceLabels(_ labels: [PhotoLabel]) -> [String] {
        labels
            .filter { $0.confidence >= 0.5 }
            .sorted { $0.confidence != $1.confidence
                ? $0.confidence > $1.confidence
                : $0.identifier < $1.identifier }
            .prefix(5)
            .map(\.identifier)
    }
}

struct PhotoAssetMetadata: Sendable {
    let time: Date
    let isScreenshot: Bool
    let imageData: Data?
}

struct PhotoLabel: Sendable {
    let identifier: String
    let confidence: Float
}
