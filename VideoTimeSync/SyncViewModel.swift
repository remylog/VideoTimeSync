import Foundation
import SwiftUI

@MainActor
final class SyncViewModel: ObservableObject {
    @Published var pairs: [SyncPair] = []
    @Published var logLines: [String] = []
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var progressText = "待機中"

    var completePairCount: Int { pairs.filter { $0.isComplete }.count }
    var incompletePairCount: Int { pairs.filter { !$0.isComplete }.count }

    // MARK: - ファイルの追加

    /// 複数ファイルをまとめてドロップしたとき: 接尾辞ルールで自動ペアリングして追加する
    func addFiles(_ urls: [URL], suffix: String) {
        let supported = urls.filter { PairingService.isSupported($0) }
        let skipped = urls.count - supported.count
        if skipped > 0 {
            addLog("対応していない形式の \(skipped) 件を無視しました（対応: mp4 / mov / m4v）")
        }

        // すでにリストにあるファイルは追加しない
        var existing = Set<URL>()
        for pair in pairs {
            if let url = pair.source { existing.insert(url.standardizedFileURL) }
            if let url = pair.destination { existing.insert(url.standardizedFileURL) }
        }
        let fresh = supported.filter { !existing.contains($0.standardizedFileURL) }
        guard !fresh.isEmpty else { return }

        var newPairs = PairingService.makePairs(from: fresh, suffix: suffix)
        for index in newPairs.indices {
            newPairs[index].sourceDate = newPairs[index].source.flatMap(FileDates.modificationDate(of:))
            newPairs[index].destinationDate = newPairs[index].destination.flatMap(FileDates.modificationDate(of:))
        }
        pairs.append(contentsOf: newPairs)

        // 別々にドロップされた「元」と「先」も、ファイル名が対応していれば1組にまとめる
        let merged = mergeIncompletePairs(suffix: suffix)

        addLog("\(fresh.count) 件を追加（現在: ペア成立 \(completePairCount) 組 / 片側のみ \(incompletePairCount) 組）")
        if merged > 0 {
            addLog("先にドロップ済みのファイルと \(merged) 組を自動で組み合わせました")
        }
    }

    /// 片側だけ埋まっている行どうしを、ファイル名のキーが一致するものから1行にまとめる。
    /// 「元」だけの行に、同じキーの「先」だけの行を統合する。統合した組数を返す。
    @discardableResult
    func mergeIncompletePairs(suffix: String) -> Int {
        let sourceOnly = pairs.filter { $0.source != nil && $0.destination == nil }
        let destinationOnly = pairs.filter { $0.source == nil && $0.destination != nil }

        var usedDestinationIDs = Set<UUID>()
        var merged = 0

        for sourcePair in sourceOnly {
            guard let sourceURL = sourcePair.source else { continue }
            let key = PairingService.matchKey(for: sourceURL, suffix: suffix)

            let candidate = destinationOnly.first { pair in
                guard !usedDestinationIDs.contains(pair.id),
                      let url = pair.destination else { return false }
                return PairingService.matchKey(for: url, suffix: suffix) == key
            }
            guard let match = candidate,
                  let index = pairs.firstIndex(where: { $0.id == sourcePair.id }) else { continue }

            pairs[index].destination = match.destination
            pairs[index].destinationDate = match.destinationDate
            pairs[index].status = .ready
            usedDestinationIDs.insert(match.id)
            merged += 1
        }

        if !usedDestinationIDs.isEmpty {
            pairs.removeAll { usedDestinationIDs.contains($0.id) }
        }
        return merged
    }

    /// 特定の行の「元」または「先」に、1ファイルを直接ドロップしたとき
    func setFile(_ urls: [URL], pairID: UUID, isSource: Bool) {
        guard let url = urls.first(where: { PairingService.isSupported($0) }),
              let index = pairs.firstIndex(where: { $0.id == pairID }) else { return }
        if isSource {
            pairs[index].source = url
            pairs[index].sourceDate = FileDates.modificationDate(of: url)
        } else {
            pairs[index].destination = url
            pairs[index].destinationDate = FileDates.modificationDate(of: url)
        }
        pairs[index].status = .ready
    }

    // MARK: - 行の操作

    func swap(pairID: UUID) {
        guard let index = pairs.firstIndex(where: { $0.id == pairID }) else { return }
        let source = pairs[index].source
        let sourceDate = pairs[index].sourceDate
        pairs[index].source = pairs[index].destination
        pairs[index].sourceDate = pairs[index].destinationDate
        pairs[index].destination = source
        pairs[index].destinationDate = sourceDate
        pairs[index].status = .ready
    }

    func remove(pairID: UUID) {
        pairs.removeAll { $0.id == pairID }
    }

    func clear() {
        guard !isRunning else { return }
        pairs.removeAll()
        logLines.removeAll()
        progress = 0
        progressText = "待機中"
    }

    // MARK: - 実行

    func runAll(makeBackup: Bool) async {
        guard !isRunning else { return }

        guard let exiftool = ExifToolRunner.locate() else {
            addLog("エラー: exiftoolが見つかりません（同梱版もHomebrew版もありません）")
            return
        }

        let targetIDs = pairs.filter { $0.isComplete && $0.status != .done }.map { $0.id }
        guard !targetIDs.isEmpty else {
            addLog("実行できるペアがありません（元と先の両方が必要です）")
            return
        }

        isRunning = true
        progress = 0
        let total = targetIDs.count
        var finished = 0
        var failures = 0
        let service = SyncService(exiftool: exiftool)
        addLog("--- \(total) 件の同期を開始します ---")

        for id in targetIDs {
            guard let index = pairs.firstIndex(where: { $0.id == id }),
                  let source = pairs[index].source,
                  let destination = pairs[index].destination else { continue }

            pairs[index].status = .running
            progressText = "[\(finished + 1)/\(total)] \(destination.lastPathComponent)"

            do {
                try await service.sync(source: source, destination: destination,
                                       options: SyncOptions(makeBackup: makeBackup))
                if let i = pairs.firstIndex(where: { $0.id == id }) {
                    pairs[i].status = .done
                    pairs[i].destinationDate = FileDates.modificationDate(of: destination)
                }
                addLog("成功: \(destination.lastPathComponent)")
            } catch {
                failures += 1
                if let i = pairs.firstIndex(where: { $0.id == id }) {
                    pairs[i].status = .failed(error.localizedDescription)
                }
                addLog("失敗: \(destination.lastPathComponent) - \(error.localizedDescription)")
            }

            finished += 1
            progress = Double(finished) / Double(total)
        }

        progressText = failures == 0
            ? "完了: \(total) 件すべて成功"
            : "完了: 成功 \(total - failures) 件 / 失敗 \(failures) 件"
        addLog("--- 完了 ---")
        isRunning = false
    }

    // MARK: - ログ

    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("[\(formatter.string(from: Date()))] \(message)")
    }
}
