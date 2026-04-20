import BookmarkModel
import Foundation
import MergeEngine
import Store

public struct SyncCoordinator {
    private let store: any BookmarkStoreClient
    private let adapters: [SyncBrowser: any BrowserSyncAdapter]
    private let antiChurnStateStore: any AntiChurnStateStore
    private let mergeEngine: MergeEngine
    private let signatureBuilder: BookmarkSemanticSignatureBuilder
    private let sorter: BookmarkSorter

    public init(
        store: any BookmarkStoreClient,
        adapters: [SyncBrowser: any BrowserSyncAdapter],
        antiChurnStateStore: any AntiChurnStateStore,
        mergeEngine: MergeEngine = MergeEngine(),
        signatureBuilder: BookmarkSemanticSignatureBuilder = BookmarkSemanticSignatureBuilder(),
        sorter: BookmarkSorter = BookmarkSorter()
    ) {
        self.store = store
        self.adapters = adapters
        self.antiChurnStateStore = antiChurnStateStore
        self.mergeEngine = mergeEngine
        self.signatureBuilder = signatureBuilder
        self.sorter = sorter
    }

    // swiftlint:disable function_body_length
    public func runCycle(request: SyncCycleRequest) throws -> SyncCycleResult {
        let orderedConfigs = request.browsers.sorted(by: browserConfigSort)
        let importConfigs = orderedConfigs.filter(\.direction.isImportEnabled)
        let exportConfigs = orderedConfigs.filter(\.direction.isExportEnabled)

        let snapshots = try importConfigs.map { config in
            try ImportSnapshot(config: config, localItems: adapter(for: config.browser).read(config: config))
        }

        let initialDocument = try store.load()
        let initialItems = initialDocument?.items ?? []
        let initialRevision = initialDocument?.metadata.storeRevision ?? 0
        let initialClients = initialDocument?.metadata.clients ?? []

        let reduced = reduceImports(baseItems: initialItems, snapshots: snapshots)
        let sortedItems = request.sortAfterImport ? sorter.sorted(items: reduced.items) : reduced.items

        let writeOutcome: WriteOutcome
        if sortedItems == initialItems {
            let noOpDocument = initialDocument ?? StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: initialRevision,
                    writtenByClientID: request.writerClientID,
                    updatedAt: request.now,
                    clients: initialClients
                ),
                items: initialItems
            )
            writeOutcome = WriteOutcome(
                didWriteStore: false,
                document: noOpDocument,
                items: sortedItems,
                importedBrowsers: reduced.importedBrowsers,
                skippedByAntiChurn: reduced.skippedByAntiChurn
            )
        } else {
            writeOutcome = try writeWithSingleRetry(
                items: sortedItems,
                snapshots: snapshots,
                baseItems: initialItems,
                initialRevision: initialRevision,
                initialClients: initialClients,
                request: request,
                importedBrowsers: reduced.importedBrowsers,
                skippedByAntiChurn: reduced.skippedByAntiChurn
            )
        }

        for config in exportConfigs {
            try adapter(for: config.browser).write(items: writeOutcome.items, config: config)
            let signature = signatureBuilder.signature(items: writeOutcome.items, clientID: config.clientID)
            antiChurnStateStore.setLastExportSignature(signature, for: config.clientID)
        }

        return SyncCycleResult(
            didWriteStore: writeOutcome.didWriteStore,
            storeRevision: writeOutcome.document.metadata.storeRevision,
            importedBrowsers: writeOutcome.importedBrowsers,
            exportedBrowsers: exportConfigs.map(\.browser),
            skippedByAntiChurn: writeOutcome.skippedByAntiChurn
        )
    }

    // swiftlint:enable function_body_length

    private func reduceImports(baseItems: [BookmarkItem], snapshots: [ImportSnapshot]) -> ImportReduction {
        var canonical = baseItems
        var importedBrowsers: [SyncBrowser] = []
        var skippedByAntiChurn: [SyncBrowser] = []

        for snapshot in snapshots {
            let signature = signatureBuilder.signature(items: snapshot.localItems, clientID: snapshot.config.clientID)
            if antiChurnStateStore.lastExportSignature(for: snapshot.config.clientID) == signature {
                skippedByAntiChurn.append(snapshot.config.browser)
                continue
            }

            let merged = mergeEngine.merge(
                canonicalItems: canonical,
                localItems: snapshot.localItems,
                clientID: snapshot.config.clientID,
                mode: .steadyState
            )

            canonical = reconciledItemsAfterClientDeletion(
                mergedItems: merged.mergedItems,
                localItems: snapshot.localItems,
                clientID: snapshot.config.clientID
            )
            importedBrowsers.append(snapshot.config.browser)
        }

        return ImportReduction(
            items: canonical,
            importedBrowsers: importedBrowsers,
            skippedByAntiChurn: skippedByAntiChurn
        )
    }

    private func reconciledItemsAfterClientDeletion(
        mergedItems: [BookmarkItem],
        localItems: [BookmarkItem],
        clientID: String
    ) -> [BookmarkItem] {
        let localIDs = Set(localItems.map(\.id))
        let itemsByID = Dictionary(uniqueKeysWithValues: mergedItems.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: mergedItems, by: \.parentID)

        var deletions: Set<String> = Set(
            mergedItems.compactMap { item in
                guard let mappedID = item.identifierMap[clientID], !mappedID.isEmpty else { return nil }
                guard !localIDs.contains(mappedID) else { return nil }
                guard !(item.type == .folder && item.parentID == nil) else { return nil }
                return item.id
            }
        )

        var queue = Array(deletions)
        while let current = queue.popLast() {
            for child in childrenByParent[current] ?? [] where !deletions.contains(child.id) {
                deletions.insert(child.id)
                queue.append(child.id)
            }
        }

        if deletions.isEmpty {
            return mergedItems
        }

        return mergedItems
            .filter { !deletions.contains($0.id) }
            .map { item in
                guard let parentID = item.parentID, deletions.contains(parentID) else {
                    return item
                }
                return BookmarkItem(
                    id: item.id,
                    type: item.type,
                    parentID: nil,
                    position: item.position,
                    title: item.title,
                    url: item.url,
                    dateAdded: item.dateAdded,
                    dateModified: item.dateModified,
                    identifierMap: item.identifierMap
                )
            }
            .filter { item in
                if item.parentID == nil {
                    return item.type == .folder
                }
                return itemsByID[item.parentID!] != nil
            }
    }

    // swiftlint:disable function_parameter_count function_body_length
    private func writeWithSingleRetry(
        items: [BookmarkItem],
        snapshots: [ImportSnapshot],
        baseItems: [BookmarkItem],
        initialRevision: Int,
        initialClients: [StoreClient],
        request: SyncCycleRequest,
        importedBrowsers: [SyncBrowser],
        skippedByAntiChurn: [SyncBrowser]
    ) throws -> WriteOutcome {
        do {
            try enforceSafeSyncLimit(
                changeCount: effectiveChangeCount(baseItems: baseItems, candidateItems: items),
                limit: request.safeSyncLimit
            )
            let written = try store.write(
                items: items,
                writerClientID: request.writerClientID,
                clients: initialClients,
                expectedStoreRevision: initialRevision,
                now: request.now
            )
            return WriteOutcome(
                didWriteStore: true,
                document: written,
                items: items,
                importedBrowsers: importedBrowsers,
                skippedByAntiChurn: skippedByAntiChurn
            )
        } catch BookmarkStoreError.revisionConflict {
            let refreshed = try store.load()
            let refreshedItems = refreshed?.items ?? []
            let refreshedRevision = refreshed?.metadata.storeRevision ?? 0
            let refreshedClients = refreshed?.metadata.clients ?? initialClients

            let replay = reduceImports(baseItems: refreshedItems, snapshots: snapshots)
            let replayedItems = request.sortAfterImport ? sorter.sorted(items: replay.items) : replay.items

            if replayedItems == refreshedItems {
                let noOp = refreshed ?? StoreDocument(
                    metadata: StoreMetadata(
                        schemaVersion: BookmarkStore.schemaVersion,
                        storeRevision: refreshedRevision,
                        writtenByClientID: request.writerClientID,
                        updatedAt: request.now,
                        clients: refreshedClients
                    ),
                    items: replayedItems
                )
                return WriteOutcome(
                    didWriteStore: false,
                    document: noOp,
                    items: replayedItems,
                    importedBrowsers: replay.importedBrowsers,
                    skippedByAntiChurn: replay.skippedByAntiChurn
                )
            }

            try enforceSafeSyncLimit(
                changeCount: effectiveChangeCount(baseItems: refreshedItems, candidateItems: replayedItems),
                limit: request.safeSyncLimit
            )
            let written = try store.write(
                items: replayedItems,
                writerClientID: request.writerClientID,
                clients: refreshedClients,
                expectedStoreRevision: refreshedRevision,
                now: request.now
            )
            return WriteOutcome(
                didWriteStore: true,
                document: written,
                items: replayedItems,
                importedBrowsers: replay.importedBrowsers,
                skippedByAntiChurn: replay.skippedByAntiChurn
            )
        }
    }

    // swiftlint:enable function_parameter_count function_body_length

    private func adapter(for browser: SyncBrowser) throws -> any BrowserSyncAdapter {
        guard let adapter = adapters[browser] else {
            throw SyncCoordinatorError.missingAdapter(browser)
        }
        return adapter
    }

    private func browserConfigSort(_ lhs: SyncBrowserConfig, _ rhs: SyncBrowserConfig) -> Bool {
        if lhs.browser == rhs.browser {
            return lhs.clientID < rhs.clientID
        }
        return lhs.browser.rawValue < rhs.browser.rawValue
    }

    private func effectiveChangeCount(baseItems: [BookmarkItem], candidateItems: [BookmarkItem]) -> Int {
        let baseByID = Dictionary(uniqueKeysWithValues: baseItems.map { ($0.id, $0) })
        let candidateByID = Dictionary(uniqueKeysWithValues: candidateItems.map { ($0.id, $0) })

        let baseIDs = Set(baseByID.keys)
        let candidateIDs = Set(candidateByID.keys)

        let addedCount = candidateIDs.subtracting(baseIDs).count
        let deletedCount = baseIDs.subtracting(candidateIDs).count
        let updatedCount = baseIDs.intersection(candidateIDs).count(where: { id in
            baseByID[id] != candidateByID[id]
        })

        return addedCount + updatedCount + deletedCount
    }

    private func enforceSafeSyncLimit(changeCount: Int, limit: Int) throws {
        if changeCount > limit {
            throw SyncCoordinatorError.safeSyncLimitExceeded(limit: limit, actual: changeCount)
        }
    }
}

public enum SyncCoordinatorError: Error, Equatable {
    case missingAdapter(SyncBrowser)
    case safeSyncLimitExceeded(limit: Int, actual: Int)
}

extension SyncCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingAdapter(browser):
            "missing browser adapter: \(browser.rawValue)"
        case let .safeSyncLimitExceeded(limit, actual):
            "safe sync limit exceeded: limit=\(limit) actual=\(actual)"
        }
    }
}

public struct BookmarkSemanticSignatureBuilder {
    private let normalizer = URLNormalizer()

    public init() {}

    public func signature(items: [BookmarkItem], clientID: String) -> String {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let components = items.map { item -> SignatureComponent in
            let projectedID = projectedIdentifier(item: item, clientID: clientID)
            let projectedParentID: String = {
                guard let parentID = item.parentID, let parent = byID[parentID] else {
                    return ""
                }
                return projectedIdentifier(item: parent, clientID: clientID)
            }()

            return SignatureComponent(
                id: projectedID,
                type: item.type.rawValue,
                parentID: projectedParentID,
                position: item.position,
                title: item.title,
                url: item.url.map(normalizer.storageNormalized) ?? "",
                mappedID: item.identifierMap[clientID] ?? ""
            )
        }
        .sorted(by: signatureSort)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(components)) ?? Data()
        return data.base64EncodedString()
    }

    private func projectedIdentifier(item: BookmarkItem, clientID: String) -> String {
        item.identifierMap[clientID] ?? item.id
    }

    private func signatureSort(_ lhs: SignatureComponent, _ rhs: SignatureComponent) -> Bool {
        if lhs.parentID != rhs.parentID { return lhs.parentID < rhs.parentID }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        if lhs.type != rhs.type { return lhs.type < rhs.type }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }
}

private struct SignatureComponent: Codable {
    let id: String
    let type: String
    let parentID: String
    let position: Int
    let title: String
    let url: String
    let mappedID: String
}

private struct ImportSnapshot {
    let config: SyncBrowserConfig
    let localItems: [BookmarkItem]
}

private struct ImportReduction {
    let items: [BookmarkItem]
    let importedBrowsers: [SyncBrowser]
    let skippedByAntiChurn: [SyncBrowser]
}

private struct WriteOutcome {
    let didWriteStore: Bool
    let document: StoreDocument
    let items: [BookmarkItem]
    let importedBrowsers: [SyncBrowser]
    let skippedByAntiChurn: [SyncBrowser]
}
