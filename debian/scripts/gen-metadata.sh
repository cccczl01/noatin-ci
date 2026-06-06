#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 必填参数
PKG_NAME=""              # 包名
DEBIAN_VER=""            # Debian 版本号 (如 1.1.0-1)
UPSTREAM_URL=""          # 上游下载 URL
DOWNLOAD_SHA256=""       # 文件 sha256 校验和
DEB_SIZE=""              # 文件大小 (bytes)

# 可选参数（从 deb 提取）
ARCH="amd64"
MAINTAINER="Noatin OS Team <repo@cccczl.top>"
DESCRIPTION=""
ORIG_DEPENDS=""
ORIG_HOMEPAGE=""
ORIG_SECTION="utils"
ORIG_PRIORITY="optional"
INSTALLED_SIZE="0"
DEB_MD5=""
R2_URL=""
UPSTREAM_DESKTOP=""

# 来自 build.conf 的字段
LONG_DESC=""
ZH_NAME=""
ZH_SUMMARY=""
ZH_DESC=""
DEVELOPER_NAME=""
PROJECT_LICENSE=""
ICON_URL=""
SCREENSHOT_URL=""
OUTPUT_DIR=""

usage() {
    cat <<'EOF'
用法: gen-metadata.sh --pkg-name <name> --version <ver> --upstream-url <url> [OPTIONS]

必填参数:
  --pkg-name <name>        包名
  --version <ver>          Debian 版本号 (如 1.1.0-1)
  --upstream-url <url>     上游下载 URL

可选参数:
  --sha256 <hash>          文件 sha256 校验和
  --size <bytes>           文件大小
  --arch <arch>            架构 (默认: amd64)
  --maintainer <name>      维护者 (默认: Noatin OS Team)
  --description <desc>     简短描述
  --depends <deps>         依赖列表
  --homepage <url>         项目主页
  --section <section>      分类 (默认: utils)
  --priority <priority>    优先级 (默认: optional)
  --installed-size <kb>    安装大小 (默认: 0)
  --md5 <hash>             MD5 校验和
  --r2-url <url>           R2 灾备 URL
  --desktop-id <name>      desktop 文件名
  --long-desc <text>       长描述
  --zh-name <name>         中文名
  --zh-summary <text>      中文摘要
  --zh-desc <text>         中文描述
  --developer-name <name>  开发者名称
  --project-license <name> 项目许可证
  --icon-url <url>         图标 URL
  --screenshot-url <url>   截图 URL
  --output-dir <dir>       输出目录 (默认: 当前目录)
  --help                   显示帮助信息

输出:
  metadata.json 写入 --output-dir 指定的目录
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg-name)
            PKG_NAME="$2"; shift 2 ;;
        --version)
            DEBIAN_VER="$2"; shift 2 ;;
        --upstream-url)
            UPSTREAM_URL="$2"; shift 2 ;;
        --sha256)
            DOWNLOAD_SHA256="$2"; shift 2 ;;
        --size)
            DEB_SIZE="$2"; shift 2 ;;
        --arch)
            ARCH="$2"; shift 2 ;;
        --maintainer)
            MAINTAINER="$2"; shift 2 ;;
        --description)
            DESCRIPTION="$2"; shift 2 ;;
        --depends)
            ORIG_DEPENDS="$2"; shift 2 ;;
        --homepage)
            ORIG_HOMEPAGE="$2"; shift 2 ;;
        --section)
            ORIG_SECTION="$2"; shift 2 ;;
        --priority)
            ORIG_PRIORITY="$2"; shift 2 ;;
        --installed-size)
            INSTALLED_SIZE="$2"; shift 2 ;;
        --md5)
            DEB_MD5="$2"; shift 2 ;;
        --r2-url)
            R2_URL="$2"; shift 2 ;;
        --desktop-id)
            UPSTREAM_DESKTOP="$2"; shift 2 ;;
        --long-desc)
            LONG_DESC="$2"; shift 2 ;;
        --zh-name)
            ZH_NAME="$2"; shift 2 ;;
        --zh-summary)
            ZH_SUMMARY="$2"; shift 2 ;;
        --zh-desc)
            ZH_DESC="$2"; shift 2 ;;
        --developer-name)
            DEVELOPER_NAME="$2"; shift 2 ;;
        --project-license)
            PROJECT_LICENSE="$2"; shift 2 ;;
        --icon-url)
            ICON_URL="$2"; shift 2 ;;
        --screenshot-url)
            SCREENSHOT_URL="$2"; shift 2 ;;
        --output-dir)
            OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        *)
            echo "错误: 未知参数: $1" >&2
            usage ;;
    esac
done

if [[ -z "$PKG_NAME" ]]; then
    echo "错误: --pkg-name 为必填项" >&2
    usage
fi
if [[ -z "$DEBIAN_VER" ]]; then
    echo "错误: --version 为必填项" >&2
    usage
fi
if [[ -z "$UPSTREAM_URL" ]]; then
    echo "错误: --upstream-url 为必填项" >&2
    usage
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(pwd)"
fi

mkdir -p "$OUTPUT_DIR"

BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

METADATA_FILE="${OUTPUT_DIR}/metadata.json"

cat > "$METADATA_FILE" << METAEOF
{
  "schema_version": 1,
  "package_type": "external",
  "package": "${PKG_NAME}",
  "version": "${DEBIAN_VER}",
  "architecture": "${ARCH}",
  "maintainer": "${MAINTAINER}",
  "description": "${DESCRIPTION}",
  "long_description": "${LONG_DESC}",
  "depends": "${ORIG_DEPENDS}",
  "homepage": "${ORIG_HOMEPAGE}",
  "section": "${ORIG_SECTION}",
  "priority": "${ORIG_PRIORITY}",
  "installed_size": "${INSTALLED_SIZE}",
  "size": "${DEB_SIZE}",
  "sha256": "${DOWNLOAD_SHA256}",
  "md5": "${DEB_MD5}",
  "download": {
    "upstream_url": "${UPSTREAM_URL}",
    "r2_url": "${R2_URL}"
  },
  "zh_name": "${ZH_NAME}",
  "zh_summary": "${ZH_SUMMARY}",
  "zh_desc": "${ZH_DESC}",
  "developer_name": "${DEVELOPER_NAME}",
  "project_license": "${PROJECT_LICENSE}",
  "icon_url": "${ICON_URL}",
  "screenshot_url": "${SCREENSHOT_URL}",
  "desktop_id": "${UPSTREAM_DESKTOP}",
  "commit_sha": "${COMMIT_SHA}",
  "build_date": "${BUILD_DATE}"
}
METAEOF

echo "metadata.json 已生成: ${METADATA_FILE}"