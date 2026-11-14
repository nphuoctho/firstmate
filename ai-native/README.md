# AI Native base: Pi Agent + Firstmate + Herdr + no-mistakes

Bộ khung dùng lại cho mọi dự án AI Native. Một lệnh để dựng máy mới, một file mẫu để gắn no-mistakes vào repo bất kỳ.

## Dựng máy

```sh
ai-native/setup.sh --check   # chỉ báo thiếu gì
ai-native/setup.sh           # cài phần thiếu, không ghi đè cấu hình đã chỉnh
```

Script cài: tool dòng lệnh của Firstmate (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, `tasks-axi`), `no-mistakes`, 5 gói Pi dùng chung, cấu hình no-mistakes toàn máy, và `config/backend=herdr`, `config/crew-harness=pi`, `config/crew-dispatch.json`, `config/crew-exclude-tools` (chép từ `presets/`, chỉ khi chưa có, không bao giờ ghi đè). `git`, `gh`, `node`, `npm`, `jq`, `tmux`, `herdr`, `pi` phải có sẵn (script báo nếu thiếu). `FM_HOME` và `NM_HOME` đổi thư mục `config/` của Firstmate và `~/.no-mistakes`, dùng để chạy thử trong sandbox.

## Đã kiểm chứng

- `setup.sh --check` trên sandbox trống liệt kê 10 mục thiếu và không ghi gì; chạy lần hai không làm gì thêm; file cấu hình đã sửa tay không bị đè.
- `bin/fm-bootstrap.sh` không báo `CREW_DISPATCH` hay lỗi nào về preset; mọi model id trong preset có trong `pi --list-models`.
- Trong phòng thử Herdr (`bin/fm-herdr-lab.sh`), lệnh Pi như Firstmate dựng (`--model anthropic/claude-sonnet-5-5 --thinking medium --exclude-tools preview_export,mcp`) chạy bằng `claude-sonnet-5-5`, và `mcp`, `preview_export` không còn trong danh sách công cụ.
- `bin/fm-lint.sh ai-native/setup.sh ai-native/pi-primary.sh` (ShellCheck 0.11.0) sạch; `bin/fm-doc-audience-check.sh` đạt.

## Chi phí token cố định mỗi yêu cầu của thuyền viên

Đo bằng `pi -p --mode json` (tổng token đầu vào cho lời nhắc 1 câu, ổn định giữa các lần chạy):

| Cấu hình | Token | Chênh |
| --- | --- | --- |
| Mặc định | 18.925 | |
| `crew-exclude-tools` (`mcp`, `preview_export`) | 16.653 | -2.272 (-12%) |
| Chỉ bỏ `mcp` / chỉ bỏ `preview_export` | 17.521 / 18.057 | -1.404 / -868 |
| Thêm `--no-skills` (không áp dụng được: thuyền viên cần skill `no-mistakes`) | 6.562 | -12.363 |

Lưu ý: `mcp` và `preview_export` chỉ có mặt khi pi-mcp-adapter và pi-markdown-preview được nạp (đã đo trên Pi 1.5.2 với 5 gói cấp người dùng); trên máy thiếu hai gói này, mức tiết kiệm 2.272 chỉ mang tính tham khảo và danh sách loại không có tác dụng.

Phần lớn chi phí còn lại (khoảng 12 nghìn token) là danh sách skill cấp người dùng trong `~/.agents/skills`; rút bớt skill ở đó là cách tiết kiệm lớn nhất, nhưng thuộc máy của anh nên kit không tự đổi. Không thêm `todo` vào danh sách loại (tiết kiệm 1.800 nhưng thuyền viên dùng nó); không loại `web_enable` (loại nó lại mở toàn bộ công cụ web, tăng 1.800).

## Gói Pi

| Gói | Chạy ở | Dùng để |
| --- | --- | --- |
| pi-open-tui | phiên chính | Giao diện toàn màn hình, cấu hình bằng `/open-tui` |
| pi-web-access | mọi phiên | Tìm web và đọc liên kết |
| pi-mcp-adapter | mọi phiên | Cổng MCP, tự tắt MCP tích hợp sẵn của Pi |
| pi-markdown-preview | mọi phiên | Xuất Markdown ra PDF, HTML, PNG |
| @juicesharp/rpiv-todo | mọi phiên | Danh sách việc cần làm |
| pi-lens | phiên chính, tùy chọn | Chẩn đoán lỗi, điều hướng mã, ast-grep |
| cc-safety-net | mọi phiên | Chặn lệnh nguy hiểm trước khi chạy |

Gói cấp người dùng được nạp cho cả thuyền viên. Hai gói chỉ chạy ở phiên chính, bật bằng `ai-native/pi-primary.sh` (`LENS=1` để thêm pi-lens):
- pi-open-tui thay khung nhập của Pi nên Firstmate không đọc được ô nhập; chuông báo steer có thể bị nhét vào đoạn người đang gõ dở.
- pi-lens tốn khoảng 0,6 đến 1,2 GB bộ nhớ cho mỗi thuyền viên.

cc-safety-net chỉ chặn lệnh git hủy thay đổi do thuyền viên tự gõ, không chặn script của Firstmate. Chính sách nới lỏng trong worktree (`workflow.worktree_mode`) là tùy chọn và phải do anh áp dụng trong terminal của mình (xem `data/pi-worker-compat/report.md`).

pi-lens có thể gán nhầm schema (ví dụ AWS) cho file YAML cấu hình no-mistakes và báo lỗi giả. Dùng `no-mistakes doctor` làm chuẩn.

## no-mistakes

- `no-mistakes/global-config.yaml` thành `~/.no-mistakes/config.yaml`: agent Pi, model rẻ cho mọi bước sửa, model mạnh chỉ để review, giới hạn thời gian cứng cho mọi agent, `auto_fix.review: 0` để mọi phát hiện của review đều qua người duyệt (không dùng `axi run --yes`, cờ này bỏ qua cổng đó).
- `no-mistakes/project.no-mistakes.yaml` thành `.no-mistakes.yaml` ở **nhánh mặc định** của repo, rồi `no-mistakes init`. Các trường điều khiển cổng (`commands`, `agent`, `gates`...) chỉ được đọc từ nhánh mặc định, nên phải merge file này trước khi chạy pipeline.
- Bắt buộc điền khối `commands` (prepare, lint, test) cho từng repo: môi trường chạy không có `node_modules` hay `.venv`, để trống thì lint có thể không chạy mà lượt vẫn qua. `ignore_patterns` dùng dạng `dist/**`, `*.lock`; dạng `**/dist/**` không khớp gì.
- Chỉ bật `disable_project_settings: true` cho repo điều phối agent như Firstmate. Repo thường cần để agent của cổng đọc `AGENTS.md` của chính nó.

## Quy ước

- Phiên chính chạy trong herdr, thuyền viên mở thành pane herdr và dùng Pi.
- Việc kiểm thử Herdr chỉ chạy qua `bin/fm-herdr-lab.sh` với phiên `fm-lab-*`, không động vào phiên herdr thật.
- Cấu hình riêng của máy nằm trong `config/`, `data/`, `state/` (đã gitignore), không commit.
