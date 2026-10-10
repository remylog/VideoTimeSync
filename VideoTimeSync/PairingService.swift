import Foundation

/// ファイル名のルールで、「元」と「先」を判定してペアにする
enum PairingService {
    /// 対応する拡張子（exiftoolでQuickTimeタグを書ける形式）
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - ファイル名の判定

    /// 例: suffix が "_ex" のとき、Video_ex.mp4 は「先（編集後）」、Video.mp4 は「元（録画）」と判定する。
    /// 大文字・小文字は区別しない。ファイル名が接尾辞だけの場合（_ex.mp4 など）は「元」として扱う。
    static func isDestinationName(_ url: URL, suffix: String) -> Bool {
        guard !suffix.isEmpty else { return false }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let suffixLower = suffix.lowercased()
        return stem.hasSuffix(suffixLower) && stem.count > suffixLower.count
    }

    /// 元と先を結びつけるキー。接尾辞を取り除いた小文字のファイル名（拡張子なし）。
    /// 例: Video.mp4 と Video_ex.mp4 は、どちらも "video"
    static func matchKey(for url: URL, suffix: String) -> String {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if isDestinationName(url, suffix: suffix) {
            return String(stem.dropLast(suffix.lowercased().count))
        }
        return stem
    }

    // MARK: - ペアの作成

    /// 渡されたファイル群を、ファイル名で元と先に振り分けてペアにする。
    /// 対応する相手が見つからないファイルは、片側だけ埋まったペアとして残す。
    static func makePairs(from urls: [URL], suffix: String) -> [SyncPair] {
        var sources: [(key: String, url: URL)] = []
        var destinations: [(key: String, url: URL)] = []

        for url in urls {
            let key = matchKey(for: url, suffix: suffix)
            if isDestinationName(url, suffix: suffix) {
                destinations.append((key, url))
            } else {
                sources.append((key, url))
            }
        }

        var pairs: [SyncPair] = []
        var usedDestinations = Set<Int>()

        for source in sources {
            let match = destinations.indices.first {
                !usedDestinations.contains($0) && destinations[$0].key == source.key
            }
            if let index = match {
                usedDestinations.insert(index)
                pairs.append(SyncPair(source: source.url, destination: destinations[index].url))
            } else {
                pairs.append(SyncPair(source: source.url, destination: nil))
            }
        }

        for (index, destination) in destinations.enumerated() where !usedDestinations.contains(index) {
            pairs.append(SyncPair(source: nil, destination: destination.url))
        }

        return pairs
    }
}
