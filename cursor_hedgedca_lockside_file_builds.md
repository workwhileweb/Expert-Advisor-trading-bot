# HedgeDCA LockSide file builds
_Exported on 5/24/2026 at 04:09:09 GMT+7 from Cursor (3.5.33)_

---

**User**

@mq5/HedgeDCA_LockSide_core.mqh @mq5/HedgeDCA_LockSide_p0.mq5 @mq5/HedgeDCA_LockSide_p0p1.mq5 @mq5/HedgeDCA_LockSide_p0p1p2.mq5 @mq5/HedgeDCA_LockSide_p0p2.mq5 @mq5/HedgeDCA_LockSide_p1.mq5 @mq5/HedgeDCA_LockSide_p1p2.mq5 @mq5/HedgeDCA_LockSide_p2.mq5 @mq5/HedgeDCA_LockSide_p3.mq5 @mq5/HedgeDCA_LockSide_p4.mq5 pls builds

---

**Cursor**

Exploring the project for how MQ5 files are built and running the build.



Compiling the `.mq5` variants with MetaEditor. `HedgeDCA_LockSide_core.mqh` is a header included by those EAs, not a separate compile target.



Investigating preprocessor errors in `HedgeDCA_LockSide_core.mqh` (MQL5 doesn't accept the current `#if` usage).



MQL5's preprocessor doesn't support `#if` with numeric expressions like `#if HDCA_VARIANT == 10`. Replacing those with `#ifdef` feature flags. Searching the file for all `HDCA_VARIANT` usages.



Refactoring the core: MQL5's preprocessor doesn't support `#if` with numeric expressions. Using per-build macros (`HDCA_BUILD_*`) and `#ifdef`-only conditionals.



Applying refactor: replacing unsupported `#if` expressions with `#ifdef` build macros and derived flags.



Updating all EA stubs to use the new build macros and compiling.



## Build result

Đã chạy **MetaEditor64** biên dịch tất cả `.mq5` liên quan (và thêm `HedgeDCA_LockSide.mq5` cho đồng bộ với core). **Kết quả: 0 errors, 0 warnings** cho từng file.

| File | Kết quả |
|------|--------|
| `HedgeDCA_LockSide.mq5` | OK |
| `HedgeDCA_LockSide_p0.mq5` … `p4.mq5` | OK |
| `HedgeDCA_LockSide_p0p1.mq5`, `p0p2`, `p0p1p2`, `p1p2` | OK |

`HedgeDCA_LockSide_core.mqh` **không** biên dịch riêng; nó được include từ các EA trên.

Log chi tiết: `mq5/HedgeDCA_LockSide*.mq5` → cùng tên `_compile.log` trong `mq5/`. File `.ex5` thường nằm dưới thư mục **MQL5\Experts** của terminal MT5 (theo cấu hình MetaEditor), không nhất thiết trong repo.

## Sửa để build được

Trình biên dịch MQL5 **không hỗ trợ** `#if HDCA_VARIANT == 10 || …` (và `#elif` tương tự), nên build trước đó báo lỗi preprocessor.

Đã đổi sang **một macro build** trên mỗi EA, chỉ dùng `#ifdef`:

- `HDCA_BUILD_BASE`, `HDCA_BUILD_P0` … `HDCA_BUILD_P4`, `HDCA_BUILD_P0P1`, `HDCA_BUILD_P0P2`, `HDCA_BUILD_P1P2`, `HDCA_BUILD_P0P1P2`

Core map các macro đó sang `HDCA_NEED_*` / `HDCA_USE_RISK_FREEZE` / `HDCA_BUILD_LOG_ID`. Nhánh P3 bỏ `(void)0;` (MQL5 không chấp nhận).

Nếu bạn muốn cập nhật mô tả trong `HedgeDCA_LockSide_algorithm.md` theo macro mới, nói để chỉnh tiếp (hiện chưa đụng file `.md`).

---

**User**

gom chung p0-p4 vào 1 bản pAll có input bật tắt các p, build lại

---

**Cursor**

Đang đọc `HedgeDCA_LockSide_core.mqh` để thêm bản `pAll` với input bật/tắt P0–P4 và logic runtime.



Thêm macro `HDCA_BUILD_PALL`, input bật/tắt P0–P4, logic runtime (helper + nhánh `Risk_ShouldFreezeDca`), chỉnh `TryOpenInitialPair`, `CheckMaxDD`, `TryDca*`, `HdcaCore_OnInitCommon`. Tạo `HedgeDCA_LockSide_pAll.mq5` và biên dịch.



Đã làm xong: một EA **`mq5/HedgeDCA_LockSide_pAll.mq5`** (`#define HDCA_BUILD_PALL`) gộp đủ input P0–P4 và nhóm **bật/tắt từng lớp**.

### Input mới (chỉ bản pAll)
Trong `HedgeDCA_LockSide_core.mqh`, nhóm **`=== Risk PAll — bật/tắt từng lớp ===`**:

- `InpPAll_EnableP0` … `InpPAll_EnableP4` (mặc định `true`)

Ý nghĩa runtime:
- **P0**: chỉ khi `InpPAll_EnableP0` **và** `InpRiskGovP0_Enable` (cờ P0 chi tiết vẫn dùng như bản p0).
- **P1**: soft DD + recovery (cooldown / lot recovery) chỉ khi `InpPAll_EnableP1`.
- **P2**: spread freeze chỉ khi `InpPAll_EnableP2` (vẫn dùng `InpP2MaxSpreadPoints > 0` để bật ngưỡng).
- **P3**: giới hạn giây giữa hai DCA chỉ khi `InpPAll_EnableP3`.
- **P4**: lỗ nổi toàn tài khoản chỉ khi `InpPAll_EnableP4` (vẫn cần `InpP4MaxAccountFloatingLossUSD > 0`).

Thứ tự kiểm tra freeze (giống combo P0+P1+P2, thêm P4): P2 → P1 → P0 → P4.

### File / build
- **`mq5/HedgeDCA_LockSide_pAll.mq5`**: EA mới.
- **`mq5/HedgeDCA_LockSide_core.mqh`**: macro `HDCA_BUILD_PALL` / `HDCA_BUILD_IS_PALL`, `Risk_ShouldFreezeDca` cho pAll, helper `HdcaPAll_GetInitialPairLot`, chỉnh `TryOpenInitialPair`, `CheckMaxDD`, P3 trong `TryDca*`, cảnh báo `OnInit` khi P1 bật.

Đã **build lại** toàn bộ dòng HedgeDCA (BASE, p0–p4, combo, **pAll**): **0 errors, 0 warnings** cho tất cả.

Các bản **`HedgeDCA_LockSide_p0.mq5` … `p4.mq5`** giữ nguyên (một macro build mỗi file); nếu sau này chỉ muốn một file trên chart thì dùng **`HedgeDCA_LockSide_pAll.mq5`** và tắt các `InpPAll_Enable*` không cần.

