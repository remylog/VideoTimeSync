import customtkinter as ctk
import os
import subprocess
import shutil
from datetime import datetime
from tkinter import filedialog
import time

# ドラッグ&ドロップ用ライブラリ
from tkinterdnd2 import DND_FILES, TkinterDnD

class CTkDnD(ctk.CTk, TkinterDnD.DnDWrapper):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # tkdnd を明示ロード
        self.TkdndVersion = TkinterDnD._require(self)

class VideoSyncApp(CTkDnD):
    def __init__(self):
        super().__init__()
        self.title("Video Timestamp Sync - 一括処理版")
        self.geometry("800x720")
        self.minsize(750, 600)
        
        self.main_font = ("SF Pro Display", 13)
        self.header_font = ("SF Pro Display", 18, "bold")

        self.rows = []

        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(2, weight=1)

        self.label_head = ctk.CTkLabel(self, text="動画日時同期ツール (一括変換)", font=self.header_font)
        self.label_head.grid(row=0, column=0, padx=20, pady=20, sticky="w")

        self.frame_controls = ctk.CTkFrame(self, fg_color="transparent")
        self.frame_controls.grid(row=1, column=0, padx=20, pady=(0, 10), sticky="ew")
        
        self.btn_add_row = ctk.CTkButton(self.frame_controls, text="+ 行を追加", width=100, command=self.add_row)
        self.btn_add_row.pack(side="left", padx=5)
        
        self.btn_reset = ctk.CTkButton(self.frame_controls, text="リセット", width=100, 
        fg_color="#444444", hover_color="#333333", command=self.reset_all)
        self.btn_reset.pack(side="left", padx=15)

        self.btn_run = ctk.CTkButton(self.frame_controls, text="すべて実行", fg_color="#007AFF", 
        font=(self.main_font[0], 13, "bold"), command=self.run_all_sync)
        self.btn_run.pack(side="right", padx=5)

        self.scroll_frame = ctk.CTkScrollableFrame(self, label_text="同期ペアリスト (ファイルをドラッグ＆ドロップしてください)")
        self.scroll_frame.grid(row=2, column=0, padx=20, pady=10, sticky="nsew")
        self.scroll_frame.columnconfigure(0, weight=1)
        self.scroll_frame.columnconfigure(1, weight=1)

        self.progress_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.progress_frame.grid(row=3, column=0, padx=20, pady=(10, 0), sticky="ew")
        
        self.progress_label = ctk.CTkLabel(self.progress_frame, text="待機中...", font=self.main_font)
        self.progress_label.pack(side="left")

        self.progress_bar = ctk.CTkProgressBar(self)
        self.progress_bar.grid(row=4, column=0, padx=20, pady=(5, 15), sticky="ew")
        self.progress_bar.set(0)

        self.log_area = ctk.CTkTextbox(self, height=120, font=("Menlo", 11), state="disabled")
        self.log_area.grid(row=5, column=0, padx=20, pady=(0, 20), sticky="ew")

        self.reset_all()

    def add_row(self):
        """新しい入力行を追加する (プレビューラベル付き)"""
        row_idx = len(self.rows)
        row_frame = ctk.CTkFrame(self.scroll_frame, fg_color="transparent")
        row_frame.grid(row=row_idx, column=0, columnspan=3, pady=10, sticky="ew") # 余白を少し広げた
        row_frame.columnconfigure(0, weight=1)
        row_frame.columnconfigure(1, weight=1)

        # --- 左側: オリジナル素材 ---
        col0_frame = ctk.CTkFrame(row_frame, fg_color="transparent")
        col0_frame.grid(row=0, column=0, padx=5, sticky="ew")
        col0_frame.columnconfigure(0, weight=1)

        entry_src = ctk.CTkEntry(col0_frame, placeholder_text="[元] オリジナル素材をドロップ")
        entry_src.grid(row=0, column=0, sticky="ew")
        
        label_src_date = ctk.CTkLabel(col0_frame, text="日時: --", font=(self.main_font[0], 10), text_color="gray")
        label_src_date.grid(row=1, column=0, sticky="w", padx=2)

        # --- 右側: 同期させる動画 ---
        col1_frame = ctk.CTkFrame(row_frame, fg_color="transparent")
        col1_frame.grid(row=0, column=1, padx=5, sticky="ew")
        col1_frame.columnconfigure(0, weight=1)

        entry_dst = ctk.CTkEntry(col1_frame, placeholder_text="[先] 同期させる動画をドロップ")
        entry_dst.grid(row=0, column=0, sticky="ew")
        
        label_dst_date = ctk.CTkLabel(col1_frame, text="日時: --", font=(self.main_font[0], 10), text_color="gray")
        label_dst_date.grid(row=1, column=0, sticky="w", padx=2)

        # 削除ボタン
        btn_del = ctk.CTkButton(row_frame, text="×", width=30, fg_color="#FF3B30", hover_color="#D32F2F",
                                command=lambda: self.remove_row(row_frame, row_data))
        btn_del.grid(row=0, column=2, padx=5, sticky="n")

        row_data = {
            "frame": row_frame, 
            "src_entry": entry_src, "dst_entry": entry_dst, 
            "src_path": "", "dst_path": "",
            "src_label": label_src_date, "dst_label": label_dst_date # ラベルを保持
        }
        
        # DNDバインド
        entry_src.drop_target_register(DND_FILES)
        entry_src.dnd_bind('<<Drop>>', lambda e: self.handle_drop(e, entry_src, row_data, "src"))
        entry_dst.drop_target_register(DND_FILES)
        entry_dst.dnd_bind('<<Drop>>', lambda e: self.handle_drop(e, entry_dst, row_data, "dst"))

        self.rows.append(row_data)

    def handle_drop(self, event, entry_widget, row_data, type):
        """ドロップ時にファイル名を表示し、日時プレビューを更新する"""
        path = event.data.strip('{}')
        filename = os.path.basename(path)
        
        # 日時情報の取得
        try:
            mtime = os.path.getmtime(path)
            date_str = datetime.fromtimestamp(mtime).strftime('%Y/%m/%d %H:%M:%S')
        except:
            date_str = "取得失敗"

        if type == "src":
            row_data["src_path"] = path
            row_data["src_label"].configure(text=f"日時: {date_str}", text_color="#aaaaaa")
        else:
            row_data["dst_path"] = path
            row_data["dst_label"].configure(text=f"日時: {date_str}", text_color="#aaaaaa")
            
        entry_widget.delete(0, 'end')
        entry_widget.insert(0, filename)

    def remove_row(self, frame, data):
        frame.destroy()
        if data in self.rows:
            self.rows.remove(data)

    def log(self, message):
        self.log_area.configure(state="normal")
        self.log_area.insert("end", f"[{datetime.now().strftime('%H:%M:%S')}] {message}\n")
        self.log_area.see("end")
        self.log_area.configure(state="disabled")

    def reset_all(self):
        for row in self.rows:
            row["frame"].destroy()
        self.rows.clear()
        self.progress_label.configure(text="待機中...")
        self.progress_bar.set(0)
        self.log_area.configure(state="normal")
        self.log_area.delete("1.0", "end")
        self.log_area.configure(state="disabled")
        for _ in range(3):
            self.add_row()
        self.log("リストをリセットしました。")

    def get_exiftool_path(self):
        path = shutil.which("exiftool")
        if path: return path
        for p in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]:
            if os.path.exists(p): return p
        return None

    # --- インデントを修正した run_all_sync メソッド ---
    def run_all_sync(self):
        """進捗表示をより分かりやすく更新しながら実行"""
        exiftool_path = self.get_exiftool_path()
        if not exiftool_path:
            self.log("エラー: exiftoolが見つかりません。")
            return

        active_rows = [r for r in self.rows if r["src_path"] and r["dst_path"]]
        if not active_rows:
            self.log("実行エラー: ファイルが入力されていません。")
            return

        total = len(active_rows)
        self.btn_run.configure(state="disabled")
        self.btn_reset.configure(state="disabled")
        
        self.log(f"--- {total}件の同期を開始します ---")

        for i, row in enumerate(active_rows):
            src = row["src_path"]
            dst = row["dst_path"]
            filename = os.path.basename(dst)

            # --- ステップ1: ファイル準備 ---
            self.progress_label.configure(text=f"[{i+1}/{total}] 準備中: {filename}")
            # 視覚的な動きを出すために一旦左右に動かす
            self.progress_bar.configure(mode="indeterminate")
            self.progress_bar.start()
            self.update()
            time.sleep(0.3) # 動きを見せるための「タメ」

            try:
                # バーを通常モードに戻す
                self.progress_bar.stop()
                self.progress_bar.configure(mode="determinate")
                
                # --- ステップ2: システム日時 ---
                self.progress_label.configure(text=f"[{i+1}/{total}] システム日時を同期中...")
                stats = os.stat(src)
                os.utime(dst, (stats.st_atime, stats.st_mtime))
                self.progress_bar.set((i / total) + 0.1 / total)
                self.update()
                time.sleep(0.2)

                # --- ステップ3: Finder作成日 ---
                self.progress_label.configure(text=f"[{i+1}/{total}] Finder作成日を修正中...")
                creation_time = datetime.fromtimestamp(stats.st_ctime).strftime('%m/%d/%Y %H:%M:%S')
                subprocess.run(['SetFile', '-d', creation_time, dst], check=True, capture_output=True)
                self.progress_bar.set((i / total) + 0.3 / total)
                self.update()
                time.sleep(0.2)

                # --- ステップ4: メタデータ同期 ---
                self.progress_label.configure(text=f"[{i+1}/{total}] メタデータを書き込み中 (exiftool)...")
                dt_str = datetime.fromtimestamp(stats.st_mtime).strftime('%Y:%m:%d %H:%M:%S')
                subprocess.run([
                    exiftool_path, '-overwrite_original',
                    f'-AllDates={dt_str}', f'-TrackCreateDate={dt_str}',
                    f'-TrackModifyDate={dt_str}', f'-MediaCreateDate={dt_str}',
                    f'-MediaModifyDate={dt_str}', dst
                ], check=True, capture_output=True)

                # 1ファイル完了
                self.progress_bar.set((i + 1) / total)
                self.log(f"成功: {filename}")
                self.update()
                time.sleep(0.1)

            except Exception as e:
                self.log(f"エラー: {filename} - {str(e)}")

        self.progress_label.configure(text=f"完了: 合計{total}件の処理が終わりました")
        self.btn_run.configure(state="normal")
        self.btn_reset.configure(state="normal")
        self.log(f"--- すべての工程が完了しました ---")

if __name__ == "__main__":
    app = VideoSyncApp()
    app.mainloop()