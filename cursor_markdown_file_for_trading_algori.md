# Markdown file for trading algorithm explanation
_Exported on 5/24/2026 at 04:08:47 GMT+7 from Cursor (3.5.33)_

---

**User**

@bot.mq5 tạo file md giải thích rõ thuật toán trade của bot này

---

**Cursor**

Đang đọc `bot.mq5` và các file liên quan để nắm thuật toán giao dịch, rồi viết tài liệu markdown giải thích.


Đang tạo tài liệu markdown chi tiết về thuật toán giao dịch của `bot.mq5`.


Đã tạo file **`mq5/bot_algorithm.md`** — tài liệu giải thích thuật toán trade của `bot.mq5`.

### Nội dung chính

1. **Chiến lược** — Chỉ **SELL** bằng **Sell Limit** tại kháng cự (M1), sau đợt tăng rồi nến giảm mạnh + MACD xác nhận.
2. **Luồng `OnTick`** — Sơ đồ Mermaid: lỗ ngày → cooldown 60s → không chồng lệnh → spread → MACD → vùng giảm → S/R → FVG → đặt lệnh → breakeven.
3. **9 điều kiện** — Bảng chi tiết (giống báo cáo % trong log định kỳ).
4. **Tín hiệu** — MACD cắt xuống, `DetectBearishZone`, fractal hỗ trợ/kháng cự, FVG căn kháng cự.
5. **Entry / SL / TP** — Công thức: SL = resistance + 50% biên S/R; TP = `MinRiskReward` × (entry − support).
6. **Lot & rủi ro** — `RiskAmount`, trần 5% equity, `MaxDailyLoss`, breakeven khi lãi ≥ 1R.
7. **Hạn chế** — Chỉ bán, limit có thể không khớp, lỗ ngày không tự reset lúc 00:00.

File cùng thư mục với EA: [`mq5/bot_algorithm.md`](mq5/bot_algorithm.md).

