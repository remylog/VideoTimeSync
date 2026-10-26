import Foundation

struct SyncOptions {
    /// 書き換え前に、先ファイルを同じフォルダの VideoTimeSync_Backup へコピーする
    var makeBackup: Bool = false
}

/// 元録画の日時を、編集後の動画へ反映する。
///
/// 処理順に意味がある:
/// 1. exiftool は書き込み時にファイルを書き直し、Finder上の日時が更新されてしまう。
///    そのため内部メタデータ（QuickTimeタグ）を先に書く。
/// 2. その後で作成日・更新日を設定する。
/// 3. 最後に実際の値を読み直して検証する。
struct SyncService {
    let exiftool: ExifToolRunner

    func sync(source: URL, destination: URL, options: SyncOptions) async throws {
        let fm = FileManager.default

        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw AppError("元と先が同じファイルです")
        }
        guard fm.fileExists(atPath: source.path) else {
            throw AppError("元ファイルが見つかりません")
        }
        guard fm.fileExists(atPath: destination.path) else {
            throw AppError("先ファイルが見つかりません")
        }

        // 元ファイルの日時を取得
        let sourceAttributes = try fm.attributesOfItem(atPath: source.path)
        guard let sourceModified = sourceAttributes[.modificationDate] as? Date else {
            throw AppError("元ファイルの更新日時を取得できません")
        }
        var sourceCreated = (sourceAttributes[.creationDate] as? Date) ?? sourceModified
        if sourceCreated > sourceModified {
            // コピーの都合で作成日のほうが新しくなっている場合は、より古い更新日時に合わせる
            sourceCreated = sourceModified
        }

        if options.makeBackup {
            try makeBackup(of: destination)
        }

        // 1. 内部メタデータ（UTCのまま扱うのでタイムゾーン変換は不要）
        let expectedTag: String
        if let sourceTag = try await exiftool.readQuickTimeCreateDate(of: source) {
            try await exiftool.copyQuickTimeDates(from: source, to: destination)
            expectedTag = sourceTag
        } else {
            // 元ファイルにタグが無い場合は、更新日時をUTCに直して書き込む
            let utc = Self.utcString(sourceModified)
            try await exiftool.writeQuickTimeDates(utc, to: destination)
            expectedTag = utc
        }

        // 2. Finderの作成日・更新日
        //    作成日 → 更新日の順に設定する（更新日が作成日より古いと、作成日が引きずられて変わるため）
        try fm.setAttributes([.creationDate: sourceCreated], ofItemAtPath: destination.path)
        try fm.setAttributes([.modificationDate: sourceModified], ofItemAtPath: destination.path)

        // 3. 検証
        let after = try fm.attributesOfItem(atPath: destination.path)
        let tolerance: TimeInterval = 2.5  // exFAT/FAT系ボリュームの時刻精度を考慮
        if let modified = after[.modificationDate] as? Date,
           abs(modified.timeIntervalSince(sourceModified)) > tolerance {
            throw AppError("検証失敗: 更新日時が一致しません")
        }
        if let created = after[.creationDate] as? Date,
           abs(created.timeIntervalSince(sourceCreated)) > tolerance {
            throw AppError("検証失敗: 作成日が一致しません（このボリュームは作成日の書き換えに非対応かもしれません）")
        }
        let writtenTag = try await exiftool.readQuickTimeCreateDate(of: destination)
        if writtenTag != expectedTag {
            throw AppError("検証失敗: メタデータの日時が一致しません")
        }
    }

    // MARK: - ヘルパー

    /// QuickTimeタグ用のUTC文字列（例: 2026:08:09 11:58:11）
    static func utcString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func makeBackup(of url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
            .appendingPathComponent("VideoTimeSync_Backup", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var target = directory.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: target.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            target = directory.appendingPathComponent("\(name)_\(stamp).\(ext)")
        }
        try fm.copyItem(at: url, to: target)
    }
}
