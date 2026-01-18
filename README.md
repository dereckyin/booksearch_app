# 書架管理 (Flutter)

輕量書架拍攝與撿貨展示 App，支援拍照上傳、離線佇列，以及撿貨清單 mock（後續可接正式後端）。

## 功能速覽
- 拍照上傳：使用 `camera` 拍攝，預覽可橫向，完成後自動上傳。
- 直傳或 presign：未設定 `PRESIGN_ENDPOINT` 時，直接 POST `multipart/form-data` 到 `https://apiport.taaze.tw/api/v1/upload/photo`，欄位 `photoFile` + `folder=user_photos`。若有 presign，則用預簽 URL PUT 上傳。
- 離線/重試：拍攝結果存本地佇列（sqflite），恢復網路會自動重傳；重試按鈕在 AppBar。
- 撿貨單 mock：`撿貨單` 按鈕進入列表，可點卡片預覽兩張本地示意圖（`temp_images`），之後再串後端。
- Manifest（可選）：如有 `MANIFEST_ENDPOINT`，上傳後回報尺寸/時間等資訊。

## 主要畫面
- `CaptureScreen`：相機預覽、拍照、離線佇列管理、重試上傳。
- `PickListScreen`：撿貨清單（目前 mock），點擊卡片進入 `PickItemPreviewScreen` 以本地圖示意。

## 目錄與資源
- 程式碼：`lib/`
  - `screens/`：`capture_screen.dart`, `pick_list_screen.dart`
  - `services/`：`upload_service.dart`, `presign_client.dart`, `picklist_service.dart`, `capture_queue.dart`
  - `models/`：`capture_record.dart`, `pick_list_item.dart`
  - `widgets/`：`capture_overlay.dart`
- 本地示意圖：`temp_images/1293467_0_annotated_gemini_pro.jpg`, `temp_images/1293468_0_annotated_gemini_pro.jpg`

## 環境與執行
1) 安裝依賴：`flutter pub get`
2) 直接啟動：`flutter run`
3) （可選）指定後端與環境：
   - `--dart-define=APP_ENV=testing` 會改用 `http://127.0.0.0:8000` 做直傳（路徑 `/api/v1/upload/photo`）。不指定則為 production（`https://apiport.taaze.tw`）。
   - `--dart-define=PRESIGN_ENDPOINT=<url>`
   - `--dart-define=MANIFEST_ENDPOINT=<url>`
   若未設定 presign/manifest，會走直傳 API。

## 上傳流程摘要
1. 拍照 → 本地壓縮/縮圖（`Preprocessor`）。
2. 入佇列（sqflite）並嘗試上傳。
3. 有 presign：用預簽 URL PUT；無 presign：`MultipartRequest` 欄位 `photoFile`、`folder=user_photos`。
4. 狀態非 2xx 或 422 會記錄錯誤訊息，待後續重試。
5. 若設定 `MANIFEST_ENDPOINT`，成功後送出 metadata。

## 撿貨單 mock
- 服務：`PickListService.fetchPickList()` 回傳假資料。
- 點卡片 → `PickItemPreviewScreen`，用 `temp_images` 兩張本地圖供預覽；未來接後端改為網路圖片即可。

## 取景與 UI
- 相機預覽使用裝置回報的 `aspectRatio`，並在版面上給預覽較大比例（`Expanded(flex: 5)`）。
- App 標題/名稱統一為「書架管理」。

## 已知限制
- iOS 模擬器無法拍照，請用實機或 Android 模擬器。
- 直傳 API 目前依賴 `photoFile`/`folder` 欄位約定，如後端調整需同步更新 `upload_service.dart`。

## 之後可做
- 串接真實撿貨單 API，加入狀態/篩選。
- 上傳進度條與縮圖裁切指引。
- 錯誤上報與 Sentry 等遙測。 
