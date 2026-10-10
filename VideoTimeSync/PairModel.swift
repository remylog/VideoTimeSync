import Foundation

/// 1ペアごとの処理状態
enum SyncStatus: Equatable {
    case ready
    case running
    case done
    case failed(String)
}

/// 元録画(source)と、編集後の動画(destination)の1組
struct SyncPair: Identifiable {
    let id = UUID()
    var source: URL?
    var destination: URL?
    var status: SyncStatus = .ready
    /// プレビュー表示用: 各ファイルの現在の更新日時
    var sourceDate: Date?
    var destinationDate: Date?

    var isComplete: Bool { source != nil && destination != nil }
}

/// 日時の表示用フォーマッタ（日本語環境の見慣れた形式）
enum DateText {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    static func string(_ date: Date?) -> String {
        guard let date else { return "--" }
        return formatter.string(from: date)
    }
}

/// ファイルの更新日時を取得する小さなヘルパー
enum FileDates {
    static func modificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
