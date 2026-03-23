import customtkinter as ctk
import os
import subprocess
from datetime import datetime
from tkinter import filedialog

class VideoSyncApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        # --- ウィンドウ基本設定 ---
        self.title("Video Timestamp Sync")
        self.geometry("600x500")
        self.minsize(500, 450)
        
        self.main_font = ("SF Pro Display", 13)
        self.header_font = ("SF Pro Display", 18, "bold")

        # グリッド設定（オートスケール用）
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(4, weight=1)

        # --- UIパーツ ---
        self.label_head = ctk.CTkLabel(self, text="動画日時同期ツール", font=self.header_font)
        self.label_head.grid(row=0, column=0, padx=20, pady=(20, 10), sticky="w")

        # 元素材
        self.frame_src = ctk.CTkFrame(self, fg_color="transparent")
        self.frame_src.grid(row=1, column=0, padx=20, pady=5, sticky="ew")
        self.frame_src.grid_columnconfigure(0, weight=1)
        self.entry_src = ctk.CTkEntry(self.frame_src, placeholder_text="元素材（元の録画）のパス", font=self.main_font)
        self.entry_src.grid(row=0, column=0, padx=(0, 10), sticky="ew")
        self.btn_browse_src = ctk.CTkButton(self.frame_src, text="選択...", width=80, command=lambda: self.browse_file("src"))
        self.btn_browse_src.grid(row=0, column=1)

        # 書き出し後
        self.frame_dst = ctk.CTkFrame(self, fg_color="transparent")
        self.frame_dst.grid(row=2, column=0, padx=20, pady=5, sticky="ew")
        self.frame_dst.grid_columnconfigure(0, weight=1)
        self.entry_dst = ctk.CTkEntry(self.frame_dst, placeholder_text="書き出し後の動画パス", font=self.main_font)
        self.entry_dst.grid(row=0, column=0, padx=(0, 10), sticky="ew")
        self.btn_browse_dst = ctk.CTkButton(self.frame_dst, text="選択...", width=80, command=lambda: self.browse_file("dst"))
        self.btn_browse_dst.grid(row=0, column=1)

        # 実行ボタン
        self.btn_run = ctk.CTkButton(self, text="日時情報を同期実行", font=(self.main_font[0], 14, "bold"), 
                                     height=40, fg_color="#007AFF", hover_color="#0063CC", 
                                     command=self.sync_timestamps)
        self.btn_run.grid(row=3, column=0, padx=20, pady=20, sticky="ew")

        # ログ表示エリア
        self.log_area = ctk.CTkTextbox(self, font=("Menlo", 11), border_width=1)
        self.log_area.grid(row=4, column=0, padx=20, pady=(0, 20), sticky="nsew")

    def browse_file(self, target):
        path = filedialog.askopenfilename()
        if path:
            target_entry = self.entry_src if target == "src" else self.entry_dst
            target_entry.delete(0, 'end')
            target_entry.insert(0, path)

    def log(self, message):
        self.log_area.insert("end", f"[{datetime.now().strftime('%H:%M:%S')}] {message}\n")
        self.log_area.see("end")

    def sync_timestamps(self):
        src = self.entry_src.get().strip()
        dst = self.entry_dst.get().strip()

        if not os.path.exists(src) or not os.path.exists(dst):
            self.log("エラー: パスが正しくありません。")
            return

        try:
            # 1. Finder上の日時同期 (修正日・アクセス日)
            stats = os.stat(src)
            os.utime(dst, (stats.st_atime, stats.st_mtime))

            # 2. Finder上の作成日 (SetFile)
            creation_time = datetime.fromtimestamp(stats.st_ctime).strftime('%m/%d/%Y %H:%M:%S')
            subprocess.run(['SetFile', '-d', creation_time, dst], check=True)

            # 3. 内部メタデータ同期 (exiftool)
            dt_str = datetime.fromtimestamp(stats.st_mtime).strftime('%Y:%m:%d %H:%M:%S')
            subprocess.run([
                'exiftool', '-overwrite_original',
                f'-AllDates={dt_str}', f'-TrackCreateDate={dt_str}',
                f'-TrackModifyDate={dt_str}', f'-MediaCreateDate={dt_str}',
                f'-MediaModifyDate={dt_str}', dst
            ], check=True)
            
            self.log(f"完了: {os.path.basename(dst)}")
        except Exception as e:
            self.log(f"エラー: {str(e)}")

if __name__ == "__main__":
    app = VideoSyncApp()
    app.mainloop()