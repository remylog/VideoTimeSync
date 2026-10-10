import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SyncViewModel()
    @AppStorage("pairSuffix") private var suffix = "_ex"
    @AppStorage("makeBackup") private var makeBackup = false
    @State private var exiftoolMissing = false

    var body: some View {
        VStack(spacing: 14) {
            header
            dropZone
            pairList
            footer
            logView
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 640)
        // ウィンドウのどこにドロップしても、自動ペアリングして追加する
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addFiles(urls, suffix: suffix)
            return true
        }
        .onAppear {
            exiftoolMissing = (ExifToolRunner.locate() == nil)
        }
    }

    // MARK: - パーツ

    private var header: some View {
        HStack(spacing: 16) {
            Text("動画日時同期ツール")
                .font(.title2.bold())
            Spacer()
            HStack(spacing: 6) {
                Text("編集後の接尾辞")
                    .foregroundStyle(.secondary)
                TextField("_ex", text: $suffix)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            Toggle("実行前にバックアップ", isOn: $makeBackup)
                .toggleStyle(.checkbox)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            if exiftoolMissing {
                Label("exiftoolが見つかりません。同梱ビルドを使うか、brew install exiftool を実行してください。",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("元録画と編集後の動画を、まとめてここにドロップ")
                .font(.headline)
            Text("例: Video.mp4 と Video\(suffix).mp4 を自動で組み合わせます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(Color.secondary.opacity(0.6))
        )
    }

    private var pairList: some View {
        Group {
            if viewModel.pairs.isEmpty {
                Text("まだファイルがありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.pairs) { pair in
                        PairRow(
                            pair: pair,
                            onDropSource: { viewModel.setFile($0, pairID: pair.id, isSource: true) },
                            onDropDestination: { viewModel.setFile($0, pairID: pair.id, isSource: false) },
                            onSwap: { viewModel.swap(pairID: pair.id) },
                            onRemove: { viewModel.remove(pairID: pair.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.progressText)
                    .font(.callout)
                Spacer()
                if viewModel.incompletePairCount > 0 {
                    Button("未対応を再ペアリング") {
                        let merged = viewModel.mergeIncompletePairs(suffix: suffix)
                        viewModel.addLog(merged > 0
                            ? "\(merged) 組を自動で組み合わせました"
                            : "組み合わせられるファイルはありませんでした（接尾辞「\(suffix)」を確認してください）")
                    }
                    .disabled(viewModel.isRunning)
                }
                Button("クリア") { viewModel.clear() }
                    .disabled(viewModel.isRunning || viewModel.pairs.isEmpty)
                Button("同期を実行（\(viewModel.completePairCount)件）") {
                    Task { await viewModel.runAll(makeBackup: makeBackup) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning || viewModel.completePairCount == 0)
            }
            ProgressView(value: viewModel.progress)
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(viewModel.logLines.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                Color.clear.frame(height: 1).id("logBottom")
            }
            .frame(height: 110)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: viewModel.logLines.count) { _, _ in
                proxy.scrollTo("logBottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - 1行分の表示

struct PairRow: View {
    let pair: SyncPair
    let onDropSource: ([URL]) -> Void
    let onDropDestination: ([URL]) -> Void
    let onSwap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                FileSlot(title: "元（録画）", url: pair.source, onDrop: onDropSource)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                FileSlot(title: "先（編集後）", url: pair.destination, onDrop: onDropDestination)

                statusIcon
                    .frame(width: 22)

                Button(action: onSwap) { Image(systemName: "arrow.left.arrow.right") }
                    .help("元と先を入れ替える")
                    .buttonStyle(.borderless)
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .help("この行を削除")
                    .buttonStyle(.borderless)
            }

            if pair.isComplete {
                Text("更新日時  \(DateText.string(pair.destinationDate))  →  \(DateText.string(pair.sourceDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("元と先の両方を指定してください")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .failed(let message) = pair.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch pair.status {
        case .ready:
            Image(systemName: pair.isComplete ? "circle" : "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}

/// ファイル名を表示し、1ファイルを直接ドロップして差し替えられる枠
struct FileSlot: View {
    let title: String
    let url: URL?
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(url?.lastPathComponent ?? "ドロップして指定")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        }
    }
}
