#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

PN_NAME=""
ZH_NAME=""
ZH_SUMMARY=""
ZH_DESCRIPTION=""
EN_NAME=""
EN_DESCRIPTION=""
DEVELOPER_NAME=""
PROJECT_LICENSE=""
HOMEPAGE_URL=""
SCREENSHOT_URL=""
BINARY_NAME=""
VERSION=""
RELEASE_DATE=""
OUTPUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/metainfo/metainfo.template.xml"
PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]+$'

usage() {
cat <<'EOF'
用法: gen-metainfo.sh --pkg-name <name> --zh-name <中文名> --zh-summary <中文摘要>
                  --zh-description <中文描述> --developer-name <开发者>
                  --project-license <许可证> --version <版本>
                  [--homepage <URL>] [--screenshot-url <URL>]
                  [--binary-name <名称>] [--release-date <日期>]
                  [--output-dir <目录>]

必填参数:
  --pkg-name <name>          包名
  --zh-name <中文名称>        AppStream 中文名称
  --zh-summary <中文摘要>     AppStream 中文摘要
  --zh-description <中文描述> AppStream 中文详细描述 (\n 换行自动转 <p> 段落)
  --developer-name <名称>    开发者名称
  --project-license <许可证>  项目许可证 (如 MIT, GPL-3.0-or-later)
  --version <版本号>         应用版本号

可选参数:
  --en-name <英文名称>        AppStream 英文显示名称 (默认为 pkg-name)
  --en-description <英文描述> AppStream 英文详细描述 (\n 换行自动转 <p> 段落，默认用英文摘要)
  --homepage <URL>           项目主页 URL
  --screenshot-url <URL>     截图 URL (默认留空，不生成 screenshots 块)
  --binary-name <名称>       可执行文件名 (默认与 pkg-name 一致)
  --release-date <日期>      发布日期 (默认当天，格式 YYYY-MM-DD)
  --output-dir <目录>        输出目录 (写入 DIR/metainfo/，默认 stdout)

示例:
  gen-metainfo.sh --pkg-name chatgpt-client \
    --zh-name "ChatGPT 客户端" \
    --zh-summary "基于 Electron 的 ChatGPT 桌面客户端" \
    --zh-description "提供 ChatGPT 桌面访问体验\n集成语音输入功能" \
    --developer-name "Noatin OS Team" \
    --project-license "MIT" \
    --version 1.0.0 \
    --output-dir /tmp/out
EOF
exit 1
}

require_arg() {
    local label="$1" value="$2"
    if [[ -z "$value" ]]; then
        echo "错误: $label 为必填项" >&2
        usage
    fi
}

while [[ $# -gt 0 ]]; do
case "$1" in
    --pkg-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --pkg-name 需要参数" >&2; usage; }
        PN_NAME="$2"; shift 2 ;;
    --zh-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --zh-name 需要参数" >&2; usage; }
        ZH_NAME="$2"; shift 2 ;;
    --zh-summary)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --zh-summary 需要参数" >&2; usage; }
        ZH_SUMMARY="$2"; shift 2 ;;
    --zh-description)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --zh-description 需要参数" >&2; usage; }
        ZH_DESCRIPTION="$2"; shift 2 ;;
    --en-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --en-name 需要参数" >&2; usage; }
        EN_NAME="$2"; shift 2 ;;
    --en-description)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --en-description 需要参数" >&2; usage; }
        EN_DESCRIPTION="$2"; shift 2 ;;
    --developer-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --developer-name 需要参数" >&2; usage; }
        DEVELOPER_NAME="$2"; shift 2 ;;
    --project-license)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --project-license 需要参数" >&2; usage; }
        PROJECT_LICENSE="$2"; shift 2 ;;
    --homepage)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --homepage 需要参数" >&2; usage; }
        HOMEPAGE_URL="$2"; shift 2 ;;
    --screenshot-url)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --screenshot-url 需要参数" >&2; usage; }
        SCREENSHOT_URL="$2"; shift 2 ;;
    --binary-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --binary-name 需要参数" >&2; usage; }
        BINARY_NAME="$2"; shift 2 ;;
    --version)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --version 需要参数" >&2; usage; }
        VERSION="$2"; shift 2 ;;
    --release-date)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --release-date 需要参数" >&2; usage; }
        RELEASE_DATE="$2"; shift 2 ;;
    --output-dir)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --output-dir 需要参数" >&2; usage; }
        OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
esac
done

require_arg "--pkg-name" "$PN_NAME"
require_arg "--zh-name" "$ZH_NAME"
require_arg "--zh-summary" "$ZH_SUMMARY"
require_arg "--zh-description" "$ZH_DESCRIPTION"
require_arg "--developer-name" "$DEVELOPER_NAME"
require_arg "--project-license" "$PROJECT_LICENSE"
require_arg "--version" "$VERSION"

if [ -n "${HOMEPAGE_URL}" ] && [[ ! "${HOMEPAGE_URL}" =~ ^https?:// ]]; then
    echo "错误: --homepage 需要以 http:// 或 https:// 开头的有效 URL" >&2
    exit 1
fi

if [ -n "${SCREENSHOT_URL}" ] && [[ ! "${SCREENSHOT_URL}" =~ ^https?:// ]]; then
    echo "错误: --screenshot-url 需要以 http:// 或 https:// 开头的有效 URL" >&2
    exit 1
fi

if [[ ! "$PN_NAME" =~ $PKG_NAME_RE ]]; then
    echo "错误: 包名 '$PN_NAME' 不符合 Debian Policy (仅小写字母、数字、+.- 字符)" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "错误: 模板文件不存在: $TEMPLATE" >&2
    exit 1
fi

TOOL_NAME="${PN_NAME}"
APPSTREAM_ID="com.github.${TOOL_NAME}"

if [[ -z "$BINARY_NAME" ]]; then
    BINARY_NAME="$PN_NAME"
fi

if [[ -z "$RELEASE_DATE" ]]; then
    RELEASE_DATE=$(date +%Y-%m-%d)
fi

if [[ -z "$EN_NAME" ]]; then
    EN_NAME="$TOOL_NAME"
fi
EN_SUMMARY="${TOOL_NAME}"
DEVELOPER_ID="com.github"

if [[ -z "$EN_DESCRIPTION" ]]; then
    EN_DESCRIPTION="$EN_SUMMARY"
fi

xml_escape() {
    local s="$1"
    s="${s//&/__AMP__}"
    s="${s//</__LT__}"
    s="${s//>/__GT__}"
    s="${s//\"/__QUOT__}"
    s="${s//\'/__APOS__}"
    s="${s//__AMP__/\&amp;}"
    s="${s//__LT__/\&lt;}"
    s="${s//__GT__/\&gt;}"
    s="${s//__QUOT__/\&quot;}"
    s="${s//__APOS__/\&apos;}"
    echo "$s"
}

build_paragraphs() {
    local input="$1" lang_attr="$2" result=""
    local saved_ifs="$IFS"
    IFS=$'\n'
    mapfile -t segs <<< "${input//\\n/$'\n'}"
    IFS="$saved_ifs"
for seg in "${segs[@]}"; do
    if [[ -z "$seg" ]]; then continue; fi
    local escaped_seg
    escaped_seg=$(xml_escape "$seg")
    if [[ -n "$lang_attr" ]]; then
        result="${result} <p xml:lang=\"${lang_attr}\">${escaped_seg}</p>"$'\n'
    else
        result="${result} <p>${escaped_seg}</p>"$'\n'
    fi
done
    if [[ -n "$result" ]]; then
        result="${result%$'\n'}"
    fi
    echo "$result"
}

ZH_DESCRIPTION_PARAGRAPHS=$(build_paragraphs "$ZH_DESCRIPTION" "zh_CN")
EN_DESCRIPTION_PARAGRAPHS=$(build_paragraphs "$EN_DESCRIPTION" "")

if [[ -n "$HOMEPAGE_URL" ]]; then
    E_HOMEPAGE=$(xml_escape "$HOMEPAGE_URL")
    HOMEPAGE_BLOCK=" <url type=\"homepage\">${E_HOMEPAGE}</url>"
else
    HOMEPAGE_BLOCK=""
fi

if [[ -n "$SCREENSHOT_URL" ]]; then
E_SCREENSHOT=$(xml_escape "$SCREENSHOT_URL")
    SCREENSHOTS_BLOCK=" <screenshots>"$'\n'"  <screenshot type=\"default\">"$'\n'"   <image type=\"source\">${E_SCREENSHOT}</image>"$'\n'"  </screenshot>"$'\n'" </screenshots>"
else
    SCREENSHOTS_BLOCK=""
fi

if [[ -n "$SCREENSHOT_URL" ]]; then
    SCREENSHOTS_BLOCK="  <screenshots>"$'\n'"    <screenshot type=\"default\">"$'\n'"      <image type=\"source\">${SCREENSHOT_URL}</image>"$'\n'"    </screenshot>"$'\n'"  </screenshots>"
else
    SCREENSHOTS_BLOCK=""
fi

OUTPUT_FILE=""
if [[ -n "$OUTPUT_DIR" ]]; then
    if ! mkdir -p "$OUTPUT_DIR/metainfo"; then
        echo "错误: 无法创建输出目录: $OUTPUT_DIR/metainfo" >&2
        exit 1
    fi
    OUTPUT_FILE="$OUTPUT_DIR/metainfo/${APPSTREAM_ID}.metainfo.xml"
fi

is_multiline_placeholder() {
    local line="$1"
    [[ "$line" == *'${ZH_DESCRIPTION_PARAGRAPHS}'* ]] && return 0
    [[ "$line" == *'${EN_DESCRIPTION_PARAGRAPHS}'* ]] && return 0
    [[ "$line" == *'${SCREENSHOTS_BLOCK}'* ]] && return 0
    return 1
}

emit_multiline() {
    local line="$1"
    if [[ "$line" == *'${ZH_DESCRIPTION_PARAGRAPHS}'* ]]; then
        echo "$ZH_DESCRIPTION_PARAGRAPHS"
        return
    fi
    if [[ "$line" == *'${EN_DESCRIPTION_PARAGRAPHS}'* ]]; then
        echo "$EN_DESCRIPTION_PARAGRAPHS"
        return
    fi
    if [[ "$line" == *'${SCREENSHOTS_BLOCK}'* ]]; then
        echo "$SCREENSHOTS_BLOCK"
        return
    fi
}

replace_placeholder() {
    local line="$1" placeholder="$2" value="$3"
    local result="" before after
    while true; do
        before="${line%%"$placeholder"*}"
        if [[ "$before" == "$line" ]]; then
            result="${result}${line}"
            break
        fi
        after="${line#*"$placeholder"}"
        result="${result}${before}${value}"
        line="$after"
    done
    printf '%s' "$result"
}

emit_output() {
local e_appstream_id e_en_name e_zh_name e_en_summary e_zh_summary
local e_project_license e_developer_id e_developer_name e_binary_name e_version e_release_date
e_appstream_id=$(xml_escape "$APPSTREAM_ID")
e_en_name=$(xml_escape "$EN_NAME")
e_zh_name=$(xml_escape "$ZH_NAME")
e_en_summary=$(xml_escape "$EN_SUMMARY")
e_zh_summary=$(xml_escape "$ZH_SUMMARY")
e_project_license=$(xml_escape "$PROJECT_LICENSE")
e_developer_id=$(xml_escape "$DEVELOPER_ID")
e_developer_name=$(xml_escape "$DEVELOPER_NAME")
e_binary_name=$(xml_escape "$BINARY_NAME")
e_version=$(xml_escape "$VERSION")
e_release_date=$(xml_escape "$RELEASE_DATE")
while IFS= read -r line || [[ -n "$line" ]]; do
if is_multiline_placeholder "$line"; then
emit_multiline "$line"
continue
fi
line=$(replace_placeholder "$line" '${APPSTREAM_ID}' "$e_appstream_id")
line=$(replace_placeholder "$line" '${EN_NAME}' "$e_en_name")
line=$(replace_placeholder "$line" '${ZH_NAME}' "$e_zh_name")
line=$(replace_placeholder "$line" '${EN_SUMMARY}' "$e_en_summary")
line=$(replace_placeholder "$line" '${ZH_SUMMARY}' "$e_zh_summary")
line=$(replace_placeholder "$line" '${PROJECT_LICENSE}' "$e_project_license")
line=$(replace_placeholder "$line" '${DEVELOPER_ID}' "$e_developer_id")
line=$(replace_placeholder "$line" '${DEVELOPER_NAME}' "$e_developer_name")
line=$(replace_placeholder "$line" '${HOMEPAGE_BLOCK}' "$HOMEPAGE_BLOCK")
line=$(replace_placeholder "$line" '${HOMEPAGE_URL}' "$HOMEPAGE_URL")
line=$(replace_placeholder "$line" '${BINARY_NAME}' "$e_binary_name")
line=$(replace_placeholder "$line" '${VERSION}' "$e_version")
line=$(replace_placeholder "$line" '${RELEASE_DATE}' "$e_release_date")
        echo "$line"
    done < "$TEMPLATE"
}

if [[ -n "$OUTPUT_FILE" ]]; then
    emit_output > "$OUTPUT_FILE"
    chmod 644 "$OUTPUT_FILE"
    echo "已生成: $OUTPUT_FILE"
else
    emit_output
fi

if [[ -n "$OUTPUT_FILE" ]] && command -v appstreamcli &>/dev/null; then
    echo "--- 运行 appstreamcli validate ---"
    VALIDATE_OUTPUT=""
    VALIDATE_OUTPUT=$(appstreamcli validate --no-net "$OUTPUT_FILE" 2>&1) || true
    echo "$VALIDATE_OUTPUT"
    if echo "$VALIDATE_OUTPUT" | grep -q '^E:'; then
        echo "警告: appstreamcli validate 发现 error 级别问题，请检查生成文件" >&2
    else
        echo "✓ appstreamcli validate 通过 (无 error)"
    fi
fi
