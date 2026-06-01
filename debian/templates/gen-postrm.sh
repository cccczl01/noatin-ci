#!/bin/bash
set -euo pipefail

PN_NAME=""
OUTPUT_DIR=""
HAS_DESKTOP="yes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/DEBIAN/postrm.template"
PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]+$'

usage() {
    cat <<'EOF'
用法: gen-postrm.sh --pkg-name <name> [--output-dir <dir>] [--has-desktop <yes|no>]

必填参数:
  --pkg-name <name>      包名 (自动添加 noatin- 前缀，除非已有)

可选参数:
  --output-dir <dir>     输出目录 (写入 DIR/DEBIAN/postrm，默认 stdout)
  --has-desktop <yes|no> 是否包含 desktop 文件 (默认 yes, CLI 工具用 no)

示例:
  gen-postrm.sh --pkg-name chatgpt-client
  gen-postrm.sh --pkg-name chatgpt-client --output-dir /tmp/out
  gen-postrm.sh --pkg-name openclaw --has-desktop no --output-dir /tmp/out
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg-name)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --pkg-name 需要参数" >&2; usage; }
            PN_NAME="$2"; shift 2 ;;
        --output-dir)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --output-dir 需要参数" >&2; usage; }
            OUTPUT_DIR="$2"; shift 2 ;;
        --has-desktop)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --has-desktop 需要参数" >&2; usage; }
            HAS_DESKTOP="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "未知参数: $1" >&2; usage ;;
    esac
done

if [[ -z "$PN_NAME" ]]; then
    echo "错误: --pkg-name 为必填项" >&2
    usage
fi

if [[ ! "$PN_NAME" =~ ^noatin- ]]; then
    PN_NAME="noatin-${PN_NAME}"
fi

if [[ ! "$PN_NAME" =~ $PKG_NAME_RE ]]; then
    echo "错误: 包名 '$PN_NAME' 不符合 Debian Policy (仅小写字母、数字、+.- 字符)" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "错误: 模板文件不存在: $TEMPLATE" >&2
    exit 1
fi

OUTPUT_FILE=""
if [[ -n "$OUTPUT_DIR" ]]; then
    if ! mkdir -p "$OUTPUT_DIR/DEBIAN"; then
        echo "错误: 无法创建输出目录: $OUTPUT_DIR/DEBIAN" >&2
        exit 1
    fi
    OUTPUT_FILE="$OUTPUT_DIR/DEBIAN/postrm"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//\$\{PKG_NAME\}/$PN_NAME}"
        line="${line//\$\{HAS_DESKTOP\}/$HAS_DESKTOP}"
        echo "$line"
    done < "$TEMPLATE" > "$OUTPUT_FILE"
    chmod 755 "$OUTPUT_FILE"
else
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//\$\{PKG_NAME\}/$PN_NAME}"
        line="${line//\$\{HAS_DESKTOP\}/$HAS_DESKTOP}"
        echo "$line"
    done < "$TEMPLATE"
fi
