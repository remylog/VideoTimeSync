import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// exiftool の実行を担当する。
/// アプリに同梱した exiftool（Perlスクリプト）を優先し、無ければ Homebrew 等の exiftool を使う。
struct ExifToolRunner {
    let executableURL: URL
    /// perl 経由で同梱スクリプトを動かす場合の先頭引数（スクリプトのパス）
    let leadingArguments: [String]

    /// QuickTime系の日時タグ。グループを明示して、XMPなど余計な場所に書かないようにする
    private static let dateTags = [
        "QuickTime:CreateDate", "QuickTime:ModifyDate",
        "QuickTime:TrackCreateDate", "QuickTime:TrackModifyDate",
        "QuickTime:MediaCreateDate", "QuickTime:MediaModifyDate",
    ]

    // MARK: - 探索

    static func locate() -> ExifToolRunner? {
        let fm = FileManager.default

        // 1. アプリ同梱版（Resources/exiftool/exiftool を /usr/bin/perl で実行）
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("exiftool", isDirectory: true) {
            let script = dir.appendingPathComponent("exiftool")
            if fm.fileExists(atPath: script.path), fm.isExecutableFile(atPath: "/usr/bin/perl") {
                return ExifToolRunner(
                    executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                    leadingArguments: [script.path]
                )
            }
        }

        // 2. Homebrew などにインストール済みのもの
        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"] {
            if fm.isExecutableFile(atPath: path) {
                return ExifToolRunner(executableURL: URL(fileURLWithPath: path), leadingArguments: [])
            }
        }
        return nil
    }

    // MARK: - 操作

    /// QuickTime:CreateDate の生の値（UTC）を読む。タグが無い・無効な場合は nil
    func readQuickTimeCreateDate(of url: URL) async throws -> String? {
        let output = try await run(["-charset", "filename=utf8", "-s3", "-QuickTime:CreateDate", url.path])
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.hasPrefix("0000") { return nil }
        return value
    }

    /// 元ファイルの日時タグを、そのまま（UTCのまま）先ファイルへコピーする
    func copyQuickTimeDates(from source: URL, to destination: URL) async throws {
        var args = ["-charset", "filename=utf8", "-overwrite_original", "-tagsFromFile", source.path]
        args += Self.dateTags.map { "-\($0)" }
        args.append(destination.path)
        try await run(args)
    }

    /// 元ファイルにタグが無いときのフォールバック。UTC文字列（yyyy:MM:dd HH:mm:ss）を直接書き込む
    func writeQuickTimeDates(_ utcValue: String, to destination: URL) async throws {
        var args = ["-charset", "filename=utf8", "-overwrite_original"]
        args += Self.dateTags.map { "-\($0)=\(utcValue)" }
        args.append(destination.path)
        try await run(args)
    }

    // MARK: - プロセス実行

    @discardableResult
    private func run(_ arguments: [String]) async throws -> String {
        let executableURL = self.executableURL
        let fullArguments = leadingArguments + arguments
        return try await Task.detached(priority: .userInitiated) {
            try Self.runSync(executableURL: executableURL, arguments: fullArguments)
        }.value
    }

    private static func runSync(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppError("exiftoolを起動できませんでした: \(error.localizedDescription)")
        }

        // exiftoolの出力は短いので、順番に読み切って問題ない
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError("exiftoolがエラーを返しました: \(detail)")
        }
        return out
    }
}
