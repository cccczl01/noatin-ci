#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

PN_NAME=""
ZH_NAME=""
ZH_COMMENT=""
EXEC_PATH=""
ICON_PATH=""
CATEGORIES=""
EN_NAME=""
EN_COMMENT=""
ZH_KEYWORDS=""
MIME_TYPES=""
WM_CLASS=""
TERMINAL=""
OUTPUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/desktop/desktop.template"
PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]+$'

usage() {
local rc="${1:-1}"
cat <<'EOF'
用法: gen-desktop.sh --pkg-name <name> --zh-name <中文名> --zh-comment <中文注释>
--exec <可执行路径> --icon <图标路径>
[--categories <分类>] [--en-name <英文名>]
[--en-comment <英文注释>] [--zh-keywords <中文关键词>]
[--mime-types <MIME类型>] [--wm-class <窗口类名>]
[--terminal <true|false>] [--output-dir <目录>]

必填参数:
--pkg-name <name>       包名
--zh-name <中文名称>     .desktop 文件中文显示名称
--zh-comment <中文注释>  .desktop 文件中文简短描述
--exec <可执行路径>      可执行文件绝对路径 (如 /usr/bin/chatgpt-client)
--icon <图标路径>        图标文件路径 (如 /usr/share/pixmaps/com.github.chatgpt-client.png)

可选参数:
--categories <分类>     应用分类 (默认 Utility;)
--en-name <英文名称>    英文显示名称 (默认使用 toolname)
--en-comment <英文注释> 英文简短描述 (默认 "toolname for Noatin OS")
--zh-keywords <关键词>  中文搜索关键词 (分号分隔，如 AI;聊天;ChatGPT;)
--mime-types <MIME>     MIME 类型 (分号分隔，如 text/xml;application/json;)
--wm-class <窗口类名>   窗口管理器类名 (默认与 AppStream ID 一致)
--terminal <true|false> 是否在终端运行 (默认 false)
--output-dir <目录>     输出目录 (写入 DIR/usr/share/applications/，默认 stdout)

示例:
gen-desktop.sh --pkg-name chatgpt-client \
  --zh-name "ChatGPT 客户端" \
  --zh-comment "基于 Electron 的 ChatGPT 桌面客户端" \
  --exec /usr/bin/chatgpt-client \
  --icon /usr/share/pixmaps/com.github.chatgpt-client.png \
  --zh-keywords "AI;聊天;ChatGPT;" \
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
    --zh-comment)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --zh-comment 需要参数" >&2; usage; }
        ZH_COMMENT="$2"; shift 2 ;;
    --exec)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --exec 需要参数" >&2; usage; }
        EXEC_PATH="$2"; shift 2 ;;
    --icon)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --icon 需要参数" >&2; usage; }
        ICON_PATH="$2"; shift 2 ;;
    --categories)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --categories 需要参数" >&2; usage; }
        CATEGORIES="$2"; shift 2 ;;
    --en-name)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --en-name 需要参数" >&2; usage; }
        EN_NAME="$2"; shift 2 ;;
    --en-comment)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --en-comment 需要参数" >&2; usage; }
        EN_COMMENT="$2"; shift 2 ;;
    --zh-keywords)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --zh-keywords 需要参数" >&2; usage; }
        ZH_KEYWORDS="$2"; shift 2 ;;
    --mime-types)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --mime-types 需要参数" >&2; usage; }
        MIME_TYPES="$2"; shift 2 ;;
    --wm-class)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --wm-class 需要参数" >&2; usage; }
        WM_CLASS="$2"; shift 2 ;;
    --terminal)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --terminal 需要参数" >&2; usage; }
        TERMINAL="$2"; shift 2 ;;
    --output-dir)
        [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --output-dir 需要参数" >&2; usage; }
        OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "未知参数: $1" >&2; usage ;;
esac
done

require_arg "--pkg-name" "$PN_NAME"
require_arg "--zh-name" "$ZH_NAME"
require_arg "--zh-comment" "$ZH_COMMENT"
require_arg "--exec" "$EXEC_PATH"
require_arg "--icon" "$ICON_PATH"

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

if [[ -z "$CATEGORIES" ]]; then
    CATEGORIES="Utility;"
fi

if [[ -z "$EN_NAME" ]]; then
    EN_NAME="$TOOL_NAME"
fi

if [[ -z "$EN_COMMENT" ]]; then
    EN_COMMENT="$EN_NAME"
fi

if [[ -z "$TERMINAL" ]]; then
TERMINAL="false"
fi
if [[ "$TERMINAL" != "true" && "$TERMINAL" != "false" ]]; then
echo "错误: --terminal 仅接受 true 或 false，收到: '$TERMINAL'" >&2
exit 1
fi

desktop_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\$/\\$}"
    s="${s//$'\x60'/\\$'\x60'}"
    s="${s//\"/\\\"}"
    s="${s//;/\\;}"
    s="${s//=/\\=}"
    printf '%s' "$s"
}

if [[ -n "$ZH_KEYWORDS" ]]; then
KEYWORDS_BLOCK="Keywords=$(desktop_escape "$EN_NAME");"
KEYWORDS_ZH_BLOCK="Keywords[zh_CN]=$(desktop_escape "$ZH_KEYWORDS")"
else
KEYWORDS_BLOCK=""
KEYWORDS_ZH_BLOCK=""
fi

if [[ -n "$MIME_TYPES" ]]; then
MIME_TYPES_BLOCK="MimeType=$(desktop_escape "$MIME_TYPES")"
else
MIME_TYPES_BLOCK=""
fi

if [[ -n "$WM_CLASS" ]]; then
WM_CLASS_BLOCK="StartupWMClass=$(desktop_escape "$WM_CLASS")"
else
WM_CLASS_BLOCK=""
fi

OUTPUT_FILE=""
if [[ -n "$OUTPUT_DIR" ]]; then
    if ! mkdir -p "$OUTPUT_DIR/usr/share/applications"; then
        echo "错误: 无法创建输出目录: $OUTPUT_DIR/usr/share/applications" >&2
        exit 1
    fi
    OUTPUT_FILE="$OUTPUT_DIR/usr/share/applications/${APPSTREAM_ID}.desktop"
fi

is_conditional_block() {
    local line="$1"
    [[ "$line" == *'${KEYWORDS_BLOCK}'* ]] && return 0
    [[ "$line" == *'${KEYWORDS_ZH_BLOCK}'* ]] && return 0
    [[ "$line" == *'${MIME_TYPES_BLOCK}'* ]] && return 0
    [[ "$line" == *'${WM_CLASS_BLOCK}'* ]] && return 0
    return 1
}

emit_conditional() {
    local line="$1"
    if [[ "$line" == *'${KEYWORDS_BLOCK}'* ]]; then
        if [[ -n "$KEYWORDS_BLOCK" ]]; then
            echo "$KEYWORDS_BLOCK"
        fi
        return
    fi
    if [[ "$line" == *'${KEYWORDS_ZH_BLOCK}'* ]]; then
        if [[ -n "$KEYWORDS_ZH_BLOCK" ]]; then
            echo "$KEYWORDS_ZH_BLOCK"
        fi
        return
    fi
    if [[ "$line" == *'${MIME_TYPES_BLOCK}'* ]]; then
        if [[ -n "$MIME_TYPES_BLOCK" ]]; then
            echo "$MIME_TYPES_BLOCK"
        fi
        return
    fi
    if [[ "$line" == *'${WM_CLASS_BLOCK}'* ]]; then
        if [[ -n "$WM_CLASS_BLOCK" ]]; then
            echo "$WM_CLASS_BLOCK"
        fi
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
while IFS= read -r line || [[ -n "$line" ]]; do
if is_conditional_block "$line"; then
emit_conditional "$line"
continue
fi
line=$(replace_placeholder "$line" '${EN_NAME}' "$(desktop_escape "$EN_NAME")")
line=$(replace_placeholder "$line" '${ZH_NAME}' "$(desktop_escape "$ZH_NAME")")
line=$(replace_placeholder "$line" '${EN_COMMENT}' "$(desktop_escape "$EN_COMMENT")")
line=$(replace_placeholder "$line" '${ZH_COMMENT}' "$(desktop_escape "$ZH_COMMENT")")
line=$(replace_placeholder "$line" '${ICON_PATH}' "$(desktop_escape "$ICON_PATH")")
line=$(replace_placeholder "$line" '${EXEC_PATH}' "$(desktop_escape "$EXEC_PATH")")
line=$(replace_placeholder "$line" '${CATEGORIES}' "$(desktop_escape "$CATEGORIES")")
line=$(replace_placeholder "$line" '${TERMINAL}' "$(desktop_escape "$TERMINAL")")
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

if [[ -n "$OUTPUT_FILE" ]] && command -v desktop-file-validate &>/dev/null; then
    echo "--- 运行 desktop-file-validate ---"
    VALIDATE_OUTPUT=""
    VALIDATE_OUTPUT=$(desktop-file-validate "$OUTPUT_FILE" 2>&1) || true
    echo "$VALIDATE_OUTPUT"
    if [[ -n "$VALIDATE_OUTPUT" ]]; then
        echo "警告: desktop-file-validate 发现问题，请检查生成文件" >&2
    else
        echo "✓ desktop-file-validate 通过"
    fi
fi
