#!/bin/bash
set -euo pipefail

PKG_NAME=""
VERSION=""
DEPENDS=""
DESCRIPTION=""
LONG_DESC=""
HOMEPAGE=""
STAGING_DIR=""
OUTPUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/DEBIAN/control.template"

MAINTAINER="Noatin OS Team <repo@cccczl.top>"
ARCHITECTURE="amd64"
SECTION="utils"
PRIORITY="optional"
STANDARDS_VERSION="4.7.0"

PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]+$'
VERSION_RE='^[0-9][a-zA-Z0-9.+~:-]*-[a-zA-Z0-9.+~]+$'

usage() {
    cat <<'EOF'
用法: gen-control.sh --pkg-name <name> --version <ver> --description <desc> [options]

必填参数:
  --pkg-name <name>       包名 (自动添加 noatin- 前缀，除非已有)
  --version <ver>         Debian 版本号 (如 1.0.0-1)
  --description <desc>    简短描述 (≤60 字符，中文)
  --long-desc <desc>      长描述 (支持 \n 换行，每行自动缩进)

可选参数:
  --depends <list>        逗号分隔的运行时依赖 (为空时不生成 Depends 字段)
  --homepage <url>        项目主页 URL
  --staging-dir <dir>     staging 目录 (用于计算 Installed-Size)
  --output-dir <dir>      输出目录 (写入 DIR/DEBIAN/control，默认 stdout)

示例:
  gen-control.sh --pkg-name chatgpt-client --version 1.0.0-1 \\
    --description "ChatGPT 桌面客户端" \\
    --long-desc "基于 Electron 的 ChatGPT 桌面客户端
支持多会话管理" \\
    --depends "libgtk-3-0, libglib2.0-0" \\
    --staging-dir /tmp/build-root \\
    --output-dir /tmp/out
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg-name)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --pkg-name 需要参数" >&2; usage; }
            PKG_NAME="$2"; shift 2 ;;
        --version)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --version 需要参数" >&2; usage; }
            VERSION="$2"; shift 2 ;;
        --depends)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --depends 需要参数" >&2; usage; }
            DEPENDS="$2"; shift 2 ;;
        --description)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --description 需要参数" >&2; usage; }
            DESCRIPTION="$2"; shift 2 ;;
        --long-desc)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --long-desc 需要参数" >&2; usage; }
            LONG_DESC="$2"; shift 2 ;;
        --homepage)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --homepage 需要参数" >&2; usage; }
            HOMEPAGE="$2"; shift 2 ;;
        --staging-dir)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --staging-dir 需要参数" >&2; usage; }
            STAGING_DIR="$2"; shift 2 ;;
        --output-dir)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --output-dir 需要参数" >&2; usage; }
            OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "未知参数: $1" >&2; usage ;;
    esac
done

if [[ -z "$PKG_NAME" || -z "$VERSION" || -z "$DESCRIPTION" || -z "$LONG_DESC" ]]; then
    echo "错误: --pkg-name, --version, --description, --long-desc 为必填项" >&2
    usage
fi

if [[ ! "$PKG_NAME" =~ ^noatin- ]]; then
    PKG_NAME="noatin-${PKG_NAME}"
fi

if [[ ! "$PKG_NAME" =~ ^${PKG_NAME_RE}$ ]]; then
    echo "错误: 无效的包名 '$PKG_NAME'。包名只能包含小写字母、数字和 + - . 字符" >&2
    exit 1
fi

if [[ ! "$VERSION" =~ ^${VERSION_RE}$ ]]; then
    echo "错误: 无效的版本号 '$VERSION'。格式应为 {upstream}-{debian_revision}" >&2
    exit 1
fi

INSTALLED_SIZE=""
if [[ -n "$STAGING_DIR" ]]; then
    if [[ -d "$STAGING_DIR" ]]; then
        INSTALLED_SIZE=$(du -sk --apparent-size "$STAGING_DIR" 2>/dev/null | awk '{print $1}') || true
        if [[ -z "$INSTALLED_SIZE" || "$INSTALLED_SIZE" =~ [^0-9] ]]; then
            echo "错误: 无法计算 staging-dir 的磁盘占用: $STAGING_DIR" >&2
            exit 1
        fi
    else
        echo "错误: staging-dir 不存在或不是目录: $STAGING_DIR" >&2
        exit 1
    fi
fi

FORMATTED_LONG_DESC=""
while IFS= read -r line; do
    FORMATTED_LONG_DESC+=" ${line}"$'\n'
done < <(printf '%b\n' "$LONG_DESC")

validate_depends() {
    local dep="$1"
    if [[ ! "$dep" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
        echo "    警告: 依赖包名 '$dep' 格式不符合 Debian 包名规范，跳过校验" >&2
        return 0
    fi
    if command -v apt-cache &>/dev/null; then
        if ! apt-cache show "$dep" &>/dev/null; then
            echo "    错误: 依赖 '$dep' 在 apt 缓存中未找到" >&2
            return 1
        fi
    fi
    return 0
}

wrap_depends() {
    local raw="$1"
    local current_line="Depends:"
    local first=1
    local -a items
    IFS=',' read -ra items <<< "$raw"
    for item in "${items[@]}"; do
        local trimmed="${item#"${item%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ -z "$trimmed" ]]; then
            continue
        fi
        if [[ $first -eq 1 ]]; then
            local candidate="${current_line} ${trimmed}"
            if [[ ${#candidate} -gt 80 ]]; then
                echo "${current_line}"
                echo " ${trimmed}"
                current_line=""
            else
                current_line="${candidate}"
            fi
            first=0
        else
            local with_comma="${current_line}, ${trimmed}"
            if [[ ${#with_comma} -gt 80 ]]; then
                echo "${current_line},"
                current_line=" ${trimmed}"
            else
                current_line="${with_comma}"
            fi
        fi
    done
    if [[ -n "$current_line" ]]; then
        echo "$current_line"
    fi
}

DEPENDS_BLOCK=""
if [[ -n "$DEPENDS" ]]; then
    dep_has_error=0
    IFS=',' read -ra dep_array <<< "$DEPENDS"
    for d in "${dep_array[@]}"; do
        trimmed="${d#"${d%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ -z "$trimmed" ]]; then
            continue
        fi
        if ! validate_depends "$trimmed"; then
            dep_has_error=1
        fi
    done
    if [[ $dep_has_error -eq 1 ]]; then
        echo "错误: 依赖校验失败，请确认所有声明的依赖包名在 Debian trixie 仓库中存在" >&2
        exit 1
    fi
    DEPENDS_BLOCK=$(wrap_depends "$DEPENDS")
fi

HOMEPAGE_BLOCK=""
if [[ -n "$HOMEPAGE" ]]; then
    HOMEPAGE_BLOCK="Homepage: ${HOMEPAGE}"
fi

OUTPUT_FILE=""
if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR/DEBIAN"
    OUTPUT_FILE="$OUTPUT_DIR/DEBIAN/control"
    exec 3>&1
    exec > "$OUTPUT_FILE"
    trap 'exec >&3 2>/dev/null' EXIT
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    line="${line//\$\{PKG_NAME\}/$PKG_NAME}"
    line="${line//\$\{VERSION\}/$VERSION}"
    line="${line//\$\{ARCHITECTURE\}/$ARCHITECTURE}"
    line="${line//\$\{MAINTAINER\}/$MAINTAINER}"
    line="${line//\$\{DESCRIPTION\}/$DESCRIPTION}"
    line="${line//\$\{INSTALLED_SIZE\}/$INSTALLED_SIZE}"
    line="${line//\$\{SECTION\}/$SECTION}"
    line="${line//\$\{PRIORITY\}/$PRIORITY}"
    line="${line//\$\{STANDARDS_VERSION\}/$STANDARDS_VERSION}"

    if [[ "$line" == *'${DEPENDS}'* ]]; then
        if [[ -n "$DEPENDS_BLOCK" ]]; then
            echo "$DEPENDS_BLOCK"
        fi
        continue
    fi

    if [[ "$line" == *'${HOMEPAGE}'* ]]; then
        if [[ -n "$HOMEPAGE_BLOCK" ]]; then
            echo "$HOMEPAGE_BLOCK"
        fi
        continue
    fi

    if [[ "$line" == *'${LONG_DESC}'* ]]; then
        printf '%s' "$FORMATTED_LONG_DESC"
        continue
    fi

    [[ -n "$line" ]] && echo "$line"
done < "$TEMPLATE"