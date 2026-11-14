# AI Native base: Pi Agent + Firstmate + Herdr + no-mistakes

Bộ khung dùng lại cho mọi dự án AI Native. Một lệnh để dựng máy mới, một file mẫu để gắn no-mistakes vào repo bất kỳ.

## Dựng máy

```sh
ai-native/setup.sh --check   # chỉ báo thiếu gì
ai-native/setup.sh           # cài phần thiếu, không ghi đè cấu hình đã chỉnh
```

Script cài:
- Tool dòng lệnh của Firstmate (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, `tasks-axi`) và `no-mistakes`.
- 2 gói Pi dùng chung (`pi-web-access`, `cc-safety-net`) và cấu hình no-mistakes toàn máy.
- `config/backend=herdr`, `config/crew-harness=pi`, `config/crew-dispatch.json` (chép từ `presets/`, chỉ khi chưa có, không bao giờ ghi đè).

`git`, `gh`, `node`, `npm`, `jq`, `tmux`, `herdr`, `pi` phải có sẵn (script báo nếu thiếu).
`FM_HOME` và `NM_HOME` đổi thư mục `config/` của Firstmate và `~/.no-mistakes`, dùng để chạy thử trong sandbox.

## Gắn một dự án mới (mọi ngôn ngữ)

```sh
ai-native/new-project.sh <stack> <repo-dir>
```

Lệnh ghép `no-mistakes/project.no-mistakes.yaml` với đoạn của stack trong `no-mistakes/stacks/` thành `<repo-dir>/.no-mistakes.yaml`.
Lệnh không ghi đè file đã có.
Sau đó commit file này lên nhánh mặc định của repo và chạy `no-mistakes init`.

| Stack | Lệnh (prepare / lint / test) | Trạng thái |
| --- | --- | --- |
| `node` | `npm ci` / `npm run lint` / `npm test` | pnpm đã chạy pipeline thật; dạng npm cùng cấu trúc, chưa chạy riêng |
| `python` | `uv sync --frozen` / `uv run ruff check .` / `uv run pytest -q` | đã chạy pipeline thật |
| `go` | `go mod download` / `gofmt -l` + `go vet` / `go test ./...` | đã chạy pipeline thật |
| `rust` | `cargo fetch --locked` / `cargo fmt --check` + `cargo clippy -D warnings` / `cargo test` | đã chạy fixture và một pipeline cô lập |
| `cpp` | không có / `clang-format --dry-run` + `clang-tidy` / `make test` | lint và `make test` đã chạy trên fixture; dạng CMake chưa chạy (máy không có cmake) |
| `shopify` | không có / `shopify theme check` | **chưa kiểm chứng**, viết từ tài liệu; app Shopify dùng script npm của app |

Mỗi đoạn chỉ gồm `commands` và `ignore_patterns` của stack đó.
Stack mới chỉ cần thêm một file `stacks/<tên>.yaml`.

## Đã kiểm chứng

- `setup.sh --check` trên sandbox trống liệt kê mục thiếu và không ghi gì; chạy lần hai không làm gì thêm; file cấu hình đã sửa tay không bị đè.
- `bin/fm-bootstrap.sh` trong nhà Firstmate tạm không báo `CREW_DISPATCH` cho preset mới, và báo lỗi cho một file JSON hỏng cố ý; cả ba model id có trong `pi --list-models`.
- Mọi file `.no-mistakes.yaml` ghép ra (6 stack) qua bộ nạp thật của no-mistakes v1.106.1 (giải mã nghiêm ngặt và `LoadRepoFromBytes`) không báo lỗi.
- Rust, Go, Python, C++: trên repo giả tạm, lệnh lint của đoạn stack thoát khác 0 khi có lỗi cố ý (clippy, `go vet`, `gofmt`, ruff, clang-format, clang-tidy) và thoát 0 khi sạch; lệnh test thoát 0.
- Một pipeline no-mistakes cô lập (NM_HOME riêng, bỏ qua `pr` và `ci`, origin cục bộ) cho Rust: `prepare`, `test`, `lint` chạy đúng lệnh của đoạn stack và cả lượt qua.
  Lỗi cố ý bị bước review bắt và sửa trước bước lint, nên lint chạy sạch; việc lint bắt lỗi được chứng minh ở bước fixture ở trên.
- Chưa kiểm chứng: Shopify (không có Shopify CLI), dạng CMake của C++, dạng npm riêng của Node.
- `bin/fm-lint.sh ai-native/setup.sh ai-native/pi-primary.sh ai-native/new-project.sh` (ShellCheck 0.11.0) sạch; `bin/fm-doc-audience-check.sh` đạt.

## Chi phí token cố định mỗi yêu cầu của thuyền viên

Mỗi gói Pi cấp người dùng thêm schema công cụ vào mọi yêu cầu của mọi thuyền viên, kể cả agent của no-mistakes.
Số đo sau là ước lượng từ kích thước payload; chưa đo token tính tiền thật trên máy chủ.

| Gói | Công cụ | Token mỗi yêu cầu (ước lượng) |
| --- | --- | --- |
| `@juicesharp/rpiv-todo` | `todo` | khoảng 1,7k |
| `pi-mcp-adapter` | `mcp` | khoảng 1,1k |
| `pi-markdown-preview` | `preview_export` | khoảng 0,8k |
| `pi-web-access` | `web_enable` | khoảng 0,2k |
| `cc-safety-net` | không | 0 |

`--exclude-tools` của Firstmate chỉ ẩn công cụ cho Pi của thuyền viên do Firstmate dựng, không áp dụng cho agent của no-mistakes và không giảm chi phí khi gói vẫn cài cấp người dùng.
Vì vậy kit bỏ `presets/crew-exclude-tools` và chuyển ba gói trên sang chỉ chạy ở phiên chính.
Phần lớn chi phí còn lại (khoảng 12 nghìn token) là danh sách skill cấp người dùng trong `~/.agents/skills`; rút bớt skill ở đó thuộc máy của anh nên kit không tự đổi.

## Gói Pi

| Gói | Chạy ở | Dùng để |
| --- | --- | --- |
| pi-web-access | mọi phiên | Tìm web và đọc liên kết |
| cc-safety-net | mọi phiên | Chặn lệnh nguy hiểm trước khi chạy |
| pi-open-tui | phiên chính | Giao diện toàn màn hình, cấu hình bằng `/open-tui` |
| pi-mcp-adapter | phiên chính | Cổng MCP, tự tắt MCP tích hợp sẵn của Pi |
| pi-markdown-preview | phiên chính | Xuất Markdown ra PDF, HTML, PNG |
| @juicesharp/rpiv-todo | phiên chính | Danh sách việc cần làm |
| pi-lens | phiên chính, tùy chọn | Chẩn đoán lỗi, điều hướng mã, ast-grep |

Hai gói đầu cài cấp người dùng và nạp cho cả thuyền viên.
Năm gói còn lại chỉ chạy ở phiên chính, bật bằng `ai-native/pi-primary.sh` (`LENS=1` để thêm pi-lens); `setup.sh` gỡ bản cấp người dùng của chúng nếu có.
- pi-open-tui thay khung nhập của Pi nên Firstmate không đọc được ô nhập; chuông báo steer có thể bị nhét vào đoạn người đang gõ dở.
- pi-lens tốn khoảng 0,6 đến 1,2 GB bộ nhớ cho mỗi thuyền viên.
- todo, mcp và preview_export tốn token mỗi yêu cầu như bảng trên.

cc-safety-net chỉ chặn lệnh git hủy thay đổi do thuyền viên tự gõ, không chặn script của Firstmate.
Nó từ chối khoảng 3,4 phần trăm lệnh thật của thuyền viên, chủ yếu `git reset --hard`.
Nới lỏng chính sách (`workflow.worktree_mode`) là quyết định của anh và phải do anh áp dụng trong terminal của mình (xem `data/pi-worker-compat/report.md`).

pi-lens có thể gán nhầm schema (ví dụ AWS) cho file YAML cấu hình no-mistakes và báo lỗi giả.
Dùng `no-mistakes doctor` làm chuẩn.

## Phân tầng model cho thuyền viên

`presets/crew-dispatch.json` (giữ `shared_quota: true`, harness `pi`):

| Việc | Model |
| --- | --- |
| Bảo trì cơ học (rebase, version bump, đổi tên) | Haiku 5.5, medium |
| Mọi việc còn lại (mặc định) | Sonnet 5.5, medium |
| Scout, quét, điều tra, kiểm toán | Sonnet 5.5, high |
| Lập kế hoạch việc lớn hoặc rủi ro, review mã chỉ đọc | Opus 5.5, xhigh |

## no-mistakes

- `no-mistakes/global-config.yaml` thành `~/.no-mistakes/config.yaml`: agent Pi, model rẻ cho mọi bước sửa, model mạnh chỉ để review, giới hạn thời gian cứng cho mọi agent, `auto_fix.review: 0` để mọi phát hiện của review đều qua người duyệt (không dùng `axi run --yes`, cờ này bỏ qua cổng đó).
- `no-mistakes/project.no-mistakes.yaml` ghép với đoạn stack (`new-project.sh`, xem trên) thành `.no-mistakes.yaml` ở **nhánh mặc định** của repo, rồi `no-mistakes init`. Các trường điều khiển cổng (`commands`, `agent`, `gates`...) chỉ được đọc từ nhánh mặc định, nên phải merge file này trước khi chạy pipeline.
- Bắt buộc có khối `commands` (prepare, lint, test) cho từng repo, các đoạn stack đã điền sẵn: môi trường chạy không có `node_modules` hay `.venv`, để trống thì lint có thể không chạy mà lượt vẫn qua. `ignore_patterns` dùng dạng `dist/**`, `*.lock`; dạng `**/dist/**` không khớp gì.
- `max_concurrent_runs` trong `global-config.yaml` là 6 (số làn thuyền viên đồng thời): một run giữ slot khi đang dừng chờ quyết định ở cổng và khi theo dõi CI, nên giữ cap ≥ số làn; bộ nhớ chủ yếu do lệnh test và typecheck của từng dự án (khoảng 2,5-3 GB mỗi lệnh, jest còn hơn) chứ không do agent, nên chỉ nâng khi còn dư bộ nhớ.
- Chỉ bật `disable_project_settings: true` cho repo điều phối agent như Firstmate. Repo thường cần để agent của cổng đọc `AGENTS.md` của chính nó.

## Quy ước

- Phiên chính chạy trong herdr, thuyền viên mở thành pane herdr và dùng Pi.
- Việc kiểm thử Herdr chỉ chạy qua `bin/fm-herdr-lab.sh` với phiên `fm-lab-*`, không động vào phiên herdr thật.
- Cấu hình riêng của máy nằm trong `config/`, `data/`, `state/` (đã gitignore), không commit.
