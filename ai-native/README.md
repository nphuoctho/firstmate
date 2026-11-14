# AI Native base: Pi Agent + Firstmate + Herdr + no-mistakes

Bộ khung dùng lại cho mọi dự án AI Native. Một lệnh để dựng máy mới, một file mẫu để gắn no-mistakes vào repo bất kỳ.

## Dựng máy

```sh
ai-native/setup.sh --check   # chỉ báo thiếu gì
ai-native/setup.sh           # cài phần thiếu, không ghi đè cấu hình đã chỉnh
```

Script cài: tool dòng lệnh của Firstmate (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, `tasks-axi`), `no-mistakes`, 7 gói Pi, bản ast-grep cho pi-lens, cấu hình no-mistakes toàn máy, và `config/backend=herdr`, `config/crew-harness=pi`. `git`, `gh`, `node`, `npm`, `jq`, `tmux`, `herdr`, `pi` phải có sẵn (script báo nếu thiếu).

## Gói Pi (cấp người dùng)

| Gói | Dùng để |
| --- | --- |
| pi-open-tui | Giao diện toàn màn hình, cấu hình bằng `/open-tui` |
| pi-web-access | Tìm web và đọc liên kết |
| pi-mcp-adapter | Cổng MCP, tự tắt MCP tích hợp sẵn của Pi |
| pi-markdown-preview | Xuất Markdown ra PDF, HTML, PNG |
| @juicesharp/rpiv-todo | Danh sách việc cần làm |
| pi-lens | Chẩn đoán lỗi, điều hướng mã, ast-grep |
| cc-safety-net | Chặn lệnh nguy hiểm trước khi chạy |

pi-lens có thể gán nhầm schema (ví dụ AWS) cho file YAML cấu hình no-mistakes và báo lỗi giả. Dùng `no-mistakes doctor` làm chuẩn.

## no-mistakes

- `no-mistakes/global-config.yaml` thành `~/.no-mistakes/config.yaml`: agent Pi, model rẻ cho mọi bước sửa, model mạnh chỉ để review, giới hạn thời gian cứng cho mọi agent, `auto_fix.review: 0` để mọi phát hiện của review đều qua người duyệt.
- `no-mistakes/project.no-mistakes.yaml` thành `.no-mistakes.yaml` ở **nhánh mặc định** của repo, rồi `no-mistakes init`. Các trường điều khiển cổng (`commands`, `agent`, `gates`...) chỉ được đọc từ nhánh mặc định, nên phải merge file này trước khi chạy pipeline.
- Chỉ bật `disable_project_settings: true` cho repo điều phối agent như Firstmate. Repo thường cần để agent của cổng đọc `AGENTS.md` của chính nó.

## Quy ước

- Phiên chính chạy trong herdr, thuyền viên mở thành pane herdr và dùng Pi.
- Việc kiểm thử Herdr chỉ chạy qua `bin/fm-herdr-lab.sh` với phiên `fm-lab-*`, không động vào phiên herdr thật.
- Cấu hình riêng của máy nằm trong `config/`, `data/`, `state/` (đã gitignore), không commit.
