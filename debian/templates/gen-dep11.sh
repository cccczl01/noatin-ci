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
ICON_URL=""
CATEGORIES=""
BINARY_NAME=""
VERSION=""
RELEASE_DATE=""
DESKTOP_ID=""
APPSTREAM_ID_OVERRIDE=""
OUTPUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/dep11/dep11.template.yml"
PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]+$'

usage() {
    local rc="${1:-1}"
    cat <<'EOF'
用法: gen-dep11.sh --pkg-name <name> --zh-name <中文名> --zh-summary <中文摘要>
    --zh-description <中文描述> --developer-name <开发者>
    --project-license <许可证> --version <版本> --icon-url <图标URL>
    [--homepage <URL>] [--screenshot-url <URL>]
    [--en-name <英文名>] [--en-description <英文描述>]
    [--categories <分类>] [--binary-name <名称>]
    [--release-date <日期>] [--output-dir <目录>]
  [--desktop-id <desktop文件名>] [--appstream-id <ID>]

必填参数:
  --pkg-name <name>           包名
  --zh-name <中文名称>        DEP-11 中文名称
  --zh-summary <中文摘要>     DEP-11 中文摘要
  --zh-description <中文描述> DEP-11 中文详细描述 (\n 换行自动转 YAML >- 折叠块)
  --developer-name <名称>     开发者名称
  --project-license <许可证>  项目许可证 (如 MIT, GPL-3.0-or-later)
  --version <版本号>          应用版本号
  --icon-url <URL>            图标 Gitee raw URL (如 https://gitee.com/.../icon.png)

可选参数:
  --en-name <英文名称>        DEP-11 英文显示名称 (默认为 pkg-name)
  --en-description <英文描述> DEP-11 英文详细描述 (\n 换行自动转 YAML >- 折叠块，默认用英文摘要)
  --homepage <URL>            项目主页 URL
  --screenshot-url <URL>      截图 URL (默认留空，不生成 Screenshots 块)
  --categories <分类列表>     分类列表，逗号分隔 (默认 Utility)
  --binary-name <名称>        可执行文件名 (默认与 pkg-name 一致)
  --release-date <日期>       发布日期 (默认当天，格式 YYYY-MM-DD)
  --output-dir <目录>         输出目录 (写入 DIR/dep11/，默认 stdout)
  --desktop-id <名称>         desktop 文件名 (如 chat-gpt.desktop，默认 ${APPSTREAM_ID}.desktop)
  --appstream-id <ID>          AppStream 组件 ID (默认 com.github.${TOOL_NAME})

示例:
  gen-dep11.sh --pkg-name chatgpt-client \
    --zh-name "ChatGPT 客户端" \
    --zh-summary "基于 Electron 的 ChatGPT 桌面客户端" \
    --zh-description "提供 ChatGPT 桌面访问体验\n集成语音输入功能" \
    --developer-name "Noatin OS Team" \
    --project-license "MIT" \
    --version 1.0.0 \
    --icon-url "https://gitee.com/noatin/noatin-repo/raw/main/chatgpt-client/assets/icon.png" \
    --output-dir /tmp/out
EOF
    exit "$rc"
}

require_arg() {
    local label="$1" value="$2"
    if [[ -z "$value" ]]; then
        echo "错误: $label 为必填项" >&2
        usage 1
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
    --icon-url)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --icon-url 需要参数" >&2; usage; }
        ICON_URL="$2"; shift 2 ;;
    --categories)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --categories 需要参数" >&2; usage; }
        CATEGORIES="$2"; shift 2 ;;
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
    --desktop-id)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --desktop-id 需要参数" >&2; usage; }
        DESKTOP_ID="$2"; shift 2 ;;
    --appstream-id)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --appstream-id 需要参数" >&2; usage; }
        APPSTREAM_ID_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
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
require_arg "--icon-url" "$ICON_URL"

if [[ ! "$PN_NAME" =~ $PKG_NAME_RE ]]; then
    echo "错误: 包名 '$PN_NAME' 不符合 Debian Policy (仅小写字母、数字、+.- 字符)" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "错误: 模板文件不存在: $TEMPLATE" >&2
    exit 1
fi

TOOL_NAME="${PN_NAME}"
if [[ -n "$APPSTREAM_ID_OVERRIDE" ]]; then
    APPSTREAM_ID="$APPSTREAM_ID_OVERRIDE"
else
    APPSTREAM_ID="com.github.${TOOL_NAME}"
fi
if [[ -z "$DESKTOP_ID" ]]; then
    DESKTOP_ID="${APPSTREAM_ID}.desktop"
fi

if [[ -z "$BINARY_NAME" ]]; then
    BINARY_NAME="$PN_NAME"
fi

if [[ -z "$RELEASE_DATE" ]]; then
    RELEASE_DATE=$(date +%Y-%m-%d)
fi

if [[ ! "$RELEASE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误: 日期格式无效 '$RELEASE_DATE'，需要 YYYY-MM-DD（如 2026-01-01）" >&2
    exit 1
fi

if [[ -z "$EN_NAME" ]]; then
    EN_NAME="$TOOL_NAME"
fi
EN_SUMMARY="$TOOL_NAME for Noatin OS"

if [[ -z "$EN_DESCRIPTION" ]]; then
    EN_DESCRIPTION="$EN_SUMMARY"
fi

yaml_quote() {
    local s="$1"
    if [[ -z "$s" ]]; then
        printf '""'
        return
    fi
    if [[ "$s" =~ ^[\"]#\[\{*\&!%] ]] || \
       [[ "$s" =~ ^\  ]] || \
       [[ "$s" =~ ^[\`@] ]] || \
       [[ "$s" == *": "* ]] || \
       [[ "$s" == *" #"* ]] || \
       [[ "$s" =~ ^(true|false|yes|no|on|off)$ ]] || \
       [[ "$s" =~ ^[0-9]+$ ]]; then
        printf '"%s"' "${s//\"/\\\"}"
        return
    fi
    printf '%s' "$s"
}

build_folded_block() {
    local input="$1"
    local saved_ifs="$IFS"
    IFS=$'\n'
    mapfile -t segs <<< "${input//\\n/$'\n'}"
    IFS="$saved_ifs"
    local result=""
    for seg in "${segs[@]}"; do
        if [[ -z "$seg" ]]; then continue; fi
        if [[ -n "$result" ]]; then
            result="${result} "
        fi
        result="${result}$(yaml_quote "$seg")"
    done
    printf '%s' "$result"
}

ZH_DESCRIPTION_FOLDED=$(build_folded_block "$ZH_DESCRIPTION")
EN_DESCRIPTION_FOLDED=$(build_folded_block "$EN_DESCRIPTION")

build_categories_block() {
    local cats="$1"
    local result=""
    local saved_ifs="$IFS"
    IFS=','
    mapfile -t cat_arr <<< "$cats"
    IFS="$saved_ifs"
    for cat in "${cat_arr[@]}"; do
        cat="${cat## }"
        cat="${cat%% }"
        if [[ -z "$cat" ]]; then continue; fi
        result="${result}    - $(yaml_quote "$cat")"$'\n'
    done
    printf '%s' "$result"
}

if [[ -z "$CATEGORIES" ]]; then
    CATEGORIES="Utility"
fi
CATEGORIES_BLOCK=$(build_categories_block "$CATEGORIES")

build_icon_block() {
    local url="$1"
    local result=""
    result="    remote:"$'\n'
    result="${result}    - url: $(yaml_quote "$url")"$'\n'
    result="${result}      width: 64"$'\n'
    result="${result}      height: 64"$'\n'
    result="${result}    - url: $(yaml_quote "$url")"$'\n'
    result="${result}      width: 128"$'\n'
    result="${result}      height: 128"
    printf '%s' "$result"
}

ICON_BLOCK=$(build_icon_block "$ICON_URL")

if [[ -n "$SCREENSHOT_URL" ]]; then
    SCREENSHOTS_BLOCK="Screenshots:"$'\n'
    SCREENSHOTS_BLOCK="${SCREENSHOTS_BLOCK}  - source_image:"$'\n'
    SCREENSHOTS_BLOCK="${SCREENSHOTS_BLOCK}      url: $(yaml_quote "$SCREENSHOT_URL")"$'\n'
    SCREENSHOTS_BLOCK="${SCREENSHOTS_BLOCK}      lang: C"
else
    SCREENSHOTS_BLOCK=""
fi

if [[ -n "$HOMEPAGE_URL" ]]; then
    HOMEPAGE_BLOCK="Url:"$'\n'
    HOMEPAGE_BLOCK="${HOMEPAGE_BLOCK}    homepage: $(yaml_quote "$HOMEPAGE_URL")"
else
    HOMEPAGE_BLOCK=""
fi

OUTPUT_FILE=""
if [[ -n "$OUTPUT_DIR" ]]; then
    if ! mkdir -p "$OUTPUT_DIR/dep11"; then
        echo "错误: 无法创建输出目录: $OUTPUT_DIR/dep11" >&2
        exit 1
    fi
    OUTPUT_FILE="$OUTPUT_DIR/dep11/${APPSTREAM_ID}.yml"
fi

is_conditional_block() {
    local line="$1"
    [[ "$line" == *'${SCREENSHOTS_BLOCK}'* ]] && return 0
    [[ "$line" == *'${HOMEPAGE_BLOCK}'* ]] && return 0
    return 1
}

emit_conditional() {
    local line="$1"
    if [[ "$line" == *'${SCREENSHOTS_BLOCK}'* ]]; then
        if [[ -n "$SCREENSHOTS_BLOCK" ]]; then
            echo "$SCREENSHOTS_BLOCK"
        fi
        return
    fi
    if [[ "$line" == *'${HOMEPAGE_BLOCK}'* ]]; then
        if [[ -n "$HOMEPAGE_BLOCK" ]]; then
            echo "$HOMEPAGE_BLOCK"
        fi
        return
    fi
}

is_multiline_block() {
    local line="$1"
    [[ "$line" == *'${CATEGORIES_BLOCK}'* ]] && return 0
    [[ "$line" == *'${ICON_BLOCK}'* ]] && return 0
    return 1
}

emit_multiline() {
    local line="$1"
    if [[ "$line" == *'${CATEGORIES_BLOCK}'* ]]; then
        printf '%s' "$CATEGORIES_BLOCK"
        return
    fi
    if [[ "$line" == *'${ICON_BLOCK}'* ]]; then
        printf '%s' "$ICON_BLOCK"
        return
    fi
}

replace_placeholder() {
    local line="$1" placeholder="$2" value="$3"
    printf '%s' "${line//"$placeholder"/"$value"}"
}

emit_output() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        if is_conditional_block "$line"; then
            emit_conditional "$line"
            continue
        fi
        if is_multiline_block "$line"; then
            emit_multiline "$line"
            echo ""
            continue
        fi
        line=$(replace_placeholder "$line" '${APPSTREAM_ID}' "$(yaml_quote "$APPSTREAM_ID")")
        line=$(replace_placeholder "$line" '${EN_NAME}' "$(yaml_quote "$EN_NAME")")
        line=$(replace_placeholder "$line" '${ZH_NAME}' "$(yaml_quote "$ZH_NAME")")
        line=$(replace_placeholder "$line" '${EN_SUMMARY}' "$(yaml_quote "$EN_SUMMARY")")
        line=$(replace_placeholder "$line" '${ZH_SUMMARY}' "$(yaml_quote "$ZH_SUMMARY")")
        line=$(replace_placeholder "$line" '${EN_DESCRIPTION}' "$EN_DESCRIPTION_FOLDED")
        line=$(replace_placeholder "$line" '${ZH_DESCRIPTION}' "$ZH_DESCRIPTION_FOLDED")
        line=$(replace_placeholder "$line" '${DEVELOPER_NAME}' "$(yaml_quote "$DEVELOPER_NAME")")
        line=$(replace_placeholder "$line" '${PROJECT_LICENSE}' "$(yaml_quote "$PROJECT_LICENSE")")
        line=$(replace_placeholder "$line" '${BINARY_NAME}' "$(yaml_quote "$BINARY_NAME")")
        line=$(replace_placeholder "$line" '${DESKTOP_ID}' "$(yaml_quote "$DESKTOP_ID")")
        line=$(replace_placeholder "$line" '${VERSION}' "$(yaml_quote "$VERSION")")
        line=$(replace_placeholder "$line" '${RELEASE_DATE}' "$(yaml_quote "$RELEASE_DATE")")
        line=$(replace_placeholder "$line" '${HOMEPAGE_URL}' "$(yaml_quote "$HOMEPAGE_URL")")
        printf '%s\n' "$line"
    done < "$TEMPLATE"
}

if [[ -n "$OUTPUT_FILE" ]]; then
    emit_output > "$OUTPUT_FILE"
    chmod 644 "$OUTPUT_FILE"
    echo "已生成: $OUTPUT_FILE"
else
    emit_output
fi
