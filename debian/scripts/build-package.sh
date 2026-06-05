#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATES_DIR="${PROJECT_ROOT}/debian/templates"

fetch_source() {
    local type="$1" source="$2" staging="$3" ver="$4"
    case "$type" in
        local)
            local src_dir="${PKG_DIR}/src"
            if [[ ! -d "$src_dir" ]]; then
                echo "错误: local 类型需要 src/ 目录: $src_dir" >&2
                exit 1
            fi
            local file_count
            file_count=$(find "$src_dir" -type f | wc -l)
            if [[ "$file_count" -eq 0 ]]; then
                echo "错误: src/ 目录为空: $src_dir" >&2
                exit 1
            fi
            cp -r "${src_dir}/"* "$staging/"
            ;;
        npm)
            local tmp
            tmp=$(mktemp -d)
            npm pack "${source}@${ver}" --pack-destination "$tmp"
            local tgz
            tgz=$(echo "$tmp"/*.tgz)
            local extract_dir="${tmp}/extract"
            mkdir -p "$extract_dir"
            tar -xzf "$tgz" -C "$extract_dir"
            cp -r "${extract_dir}/package/"* "$staging/"
            rm -rf "$tmp"
            ;;
        deb-url)
            if [[ -z "$source" ]]; then
                echo "错误: deb-url 类型需要 fetch_source (deb 下载 URL)" >&2
                exit 1
            fi
            local tmp
            tmp=$(mktemp -d)
            local deb_file="${tmp}/upstream.deb"
            echo "    下载: ${source}"
            if ! wget -q --show-progress -O "$deb_file" "$source" 2>&1; then
                echo "错误: 下载失败: $source" >&2
                rm -rf "$tmp"
                exit 1
            fi
            dpkg-deb -x "$deb_file" "$staging"
            rm -rf "$tmp"
            ;;
        *)
            echo "错误: 未知的 fetch_type: $type" >&2
            exit 1
            ;;
    esac
}

PKG_DIR=""
OUTPUT_DIR=""
VERSION_OVERRIDE=""

usage() {
    cat <<'EOF'
用法: build-package.sh --pkg-dir <dir> [--output-dir <dir>] [--version <ver>]

必填参数:
  --pkg-dir <dir>        deb 包源码目录 (含 build.conf、src/ 等)
  --output-dir <dir>     deb 输出目录 (默认当前目录)

可选参数:
  --version <ver>        Debian 版本号 (如 1.1.0-1)，覆盖 build.conf 中的版本拼接

示例:
  build-package.sh --pkg-dir debian/packages/noatin-chatgpt-client
  build-package.sh --pkg-dir debian/packages/noatin-chatgpt-client --output-dir /tmp/out
  build-package.sh --pkg-dir debian/packages/noatin-chatgpt-client --version 1.2.0-1
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg-dir)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --pkg-dir 需要参数" >&2; usage; }
            PKG_DIR="$2"; shift 2 ;;
        --output-dir)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --output-dir 需要参数" >&2; usage; }
            OUTPUT_DIR="$2"; shift 2 ;;
        --version)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --version 需要参数" >&2; usage; }
            VERSION_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        *)
            echo "未知参数: $1" >&2; usage ;;
    esac
done

if [[ -z "$PKG_DIR" ]]; then
    echo "错误: --pkg-dir 为必填项" >&2
    usage
fi

if [[ ! -d "$PKG_DIR" ]]; then
    echo "错误: 包目录不存在: $PKG_DIR" >&2
    exit 1
fi

BUILD_CONF="${PKG_DIR}/build.conf"
if [[ ! -f "$BUILD_CONF" ]]; then
    echo "错误: 缺少 build.conf: $BUILD_CONF" >&2
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(pwd)"
fi

declare -A CONF
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    CONF["$key"]="$value"
done < "$BUILD_CONF"

FETCH_TYPE="${CONF[fetch_type]:-local}"
FETCH_SOURCE="${CONF[fetch_source]:-}"

HAS_DESKTOP="${CONF[has_desktop]:-yes}"

required_fields="name upstream_version debian_revision description long_desc zh_name zh_summary zh_desc developer_name project_license exec"
if [[ "$HAS_DESKTOP" = "yes" ]]; then
    required_fields="$required_fields icon icon_url"
fi
for field in $required_fields; do
    if [[ -z "${CONF[$field]:-}" ]]; then
        echo "错误: build.conf 缺少必填字段: $field" >&2
        exit 1
    fi
done

NAME="${CONF[name]}"
UPSTREAM_VERSION="${CONF[upstream_version]}"
DEBIAN_REVISION="${CONF[debian_revision]}"
DESCRIPTION="${CONF[description]}"
LONG_DESC="${CONF[long_desc]}"
DEPENDS="${CONF[depends]:-}"
HOMEPAGE="${CONF[homepage]:-}"
ZH_NAME="${CONF[zh_name]}"
ZH_SUMMARY="${CONF[zh_summary]}"
ZH_DESC="${CONF[zh_desc]}"
DEVELOPER_NAME="${CONF[developer_name]}"
PROJECT_LICENSE="${CONF[project_license]}"
ZH_KEYWORDS="${CONF[zh_keywords]:-}"
EXEC_PATH="${CONF[exec]}"
ICON_PATH="${CONF[icon]}"
ICON_URL="${CONF[icon_url]}"
SCREENSHOT_URL="${CONF[screenshot_url]:-}"

if [[ -n "$VERSION_OVERRIDE" ]]; then
    DEBIAN_VER="$VERSION_OVERRIDE"
    if [[ ! "$DEBIAN_VER" =~ ^[0-9][a-zA-Z0-9.+~:]*\-[a-zA-Z0-9.+~]+$ ]]; then
        echo "错误: --version 格式无效: $DEBIAN_VER (应为 {upstream}-{revision})" >&2
        exit 1
    fi
    if [[ "$DEBIAN_VER" =~ ^(.+)-([^-]+)$ ]]; then
        UPSTREAM_VERSION="${BASH_REMATCH[1]}"
    fi
else
    DEBIAN_VER="${UPSTREAM_VERSION}-${DEBIAN_REVISION}"
fi

PKG_NAME="${NAME}"

# --- deb-url 模式：仅提取元数据，不存储 deb 到仓库 ---
if [[ "$FETCH_TYPE" == "deb-url" ]]; then
    mkdir -p "$OUTPUT_DIR"
    tmp=$(mktemp -d)
    deb_file="${tmp}/upstream.deb"
    extract_dir="${tmp}/extract"
    mkdir -p "$extract_dir"

    DOWNLOAD_URL="${CONF[download_url]:-${FETCH_SOURCE}}"
    DOWNLOAD_SHA256="${CONF[download_sha256]:-}"

    echo "--- 下载第三方 deb ---"
    echo "    来源: ${DOWNLOAD_URL}"
    for attempt in 1 2 3; do
        if wget -q --show-progress -O "$deb_file" "$DOWNLOAD_URL" 2>&1; then
            break
        fi
        if [[ $attempt -lt 3 ]]; then
            echo "    重试 ${attempt}/3 ..."
            sleep 10
        else
            echo "错误: 下载失败（重试 3 次后）: $DOWNLOAD_URL" >&2
            rm -rf "$tmp"
            exit 2
        fi
    done

    if [[ -n "$DOWNLOAD_SHA256" ]]; then
        echo "--- 校验 sha256 ---"
        actual_sha256=$(sha256sum "$deb_file" | awk '{print $1}')
        if [[ "$actual_sha256" != "$DOWNLOAD_SHA256" ]]; then
            echo "错误: sha256 校验和不匹配" >&2
            echo "  期望: $DOWNLOAD_SHA256" >&2
            echo "  实际: $actual_sha256" >&2
            rm -rf "$tmp"
            exit 3
        fi
        echo "    OK: sha256 匹配"
    fi

    echo "--- 提取元数据 ---"
    orig_version=$(dpkg-deb -f "$deb_file" Version 2>/dev/null || echo "$DEBIAN_VER")
    orig_pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || echo "$PKG_NAME")
    orig_arch=$(dpkg-deb -f "$deb_file" Architecture 2>/dev/null || echo "amd64")
    orig_depends=$(dpkg-deb -f "$deb_file" Depends 2>/dev/null || echo "")
    orig_desc=$(dpkg-deb -f "$deb_file" Description 2>/dev/null || echo "$DESCRIPTION")
    orig_maintainer=$(dpkg-deb -f "$deb_file" Maintainer 2>/dev/null || echo "Noatin OS Team <repo@cccczl.top>")
    orig_section=$(dpkg-deb -f "$deb_file" Section 2>/dev/null || echo "utils")
    orig_priority=$(dpkg-deb -f "$deb_file" Priority 2>/dev/null || echo "optional")
    orig_installed_size=$(dpkg-deb -f "$deb_file" Installed-Size 2>/dev/null || echo "0")
    deb_size=$(stat -c%s "$deb_file" 2>/dev/null || echo "0")
    deb_sha256=$(sha256sum "$deb_file" | awk '{print $1}')
    deb_md5=$(md5sum "$deb_file" 2>/dev/null | awk '{print $1}' || echo "")

    dpkg-deb -x "$deb_file" "$extract_dir"
    upstream_desktop=""
    if [[ -d "${extract_dir}/usr/share/applications" ]]; then
        upstream_desktop=$(find "${extract_dir}/usr/share/applications" -maxdepth 1 -name '*.desktop' -type f -printf '%f\n' 2>/dev/null | head -1)
    fi

    echo "--- 上传 deb 到 R2（灾备） ---"
    r2_url=""
    if [[ -n "${R2_ACCESS_KEY_ID:-}" && -n "${R2_ENDPOINT:-}" && -n "${R2_BUCKET:-}" ]]; then
        R2_KEY="${PKG_NAME}/pool/${DEBIAN_VER}/${PKG_NAME}_${DEBIAN_VER}_amd64.deb"
        if command -v aws > /dev/null 2>&1; then
            set +e
            r2_output=$(AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
                AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
                AWS_DEFAULT_REGION=auto \
                aws s3 cp "$deb_file" "s3://${R2_BUCKET}/${R2_KEY}" \
                --endpoint-url "${R2_ENDPOINT}" 2>&1)
            R2_RC=$?
            set -e
            if [[ $R2_RC -eq 0 ]]; then
                R2_PUBLIC_URL="${R2_PUBLIC_URL:-https://r2.cccczl.top}"
                r2_url="${R2_PUBLIC_URL}/${R2_KEY}"
                echo "    R2 上传成功: ${r2_url}"
            else
                echo "    WARNING: R2 上传失败 (exit code: ${R2_RC})，r2_url 留空"
            fi
        else
            echo "    WARNING: aws CLI 不可用，跳过 R2 上传"
        fi
    else
        echo "    SKIP: R2 环境变量未设置"
    fi

    echo "--- 生成 metadata.json ---"
    BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    COMMIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    METADATA_FILE="${OUTPUT_DIR}/metadata.json"
    cat > "$METADATA_FILE" << METAEOF
{
  "schema_version": 1,
  "package_type": "external",
  "package": "${PKG_NAME}",
  "version": "${DEBIAN_VER}",
  "architecture": "${orig_arch}",
  "maintainer": "${orig_maintainer}",
  "description": "${orig_desc%%$'\n'*}",
  "long_description": "${LONG_DESC}",
  "depends": "${orig_depends}",
  "homepage": "${HOMEPAGE}",
  "section": "${orig_section}",
  "priority": "${orig_priority}",
  "installed_size": "${orig_installed_size}",
  "size": "${deb_size}",
  "sha256": "${deb_sha256}",
  "md5": "${deb_md5}",
  "download": {
    "upstream_url": "${DOWNLOAD_URL}",
    "r2_url": "${r2_url}"
  },
  "zh_name": "${ZH_NAME}",
  "zh_summary": "${ZH_SUMMARY}",
  "zh_desc": "${ZH_DESC}",
  "developer_name": "${DEVELOPER_NAME}",
  "project_license": "${PROJECT_LICENSE}",
  "icon_url": "${ICON_URL}",
  "screenshot_url": "${SCREENSHOT_URL}",
  "desktop_id": "${upstream_desktop}",
  "commit_sha": "${COMMIT_SHA}",
  "build_date": "${BUILD_DATE}"
}
METAEOF
    echo "    输出: ${METADATA_FILE}"

    echo "--- 生成 DEP-11 元数据 ---"
    "${TEMPLATES_DIR}/gen-dep11.sh" \
        --pkg-name "$NAME" \
        --zh-name "$ZH_NAME" \
        --zh-summary "$ZH_SUMMARY" \
        --zh-description "$ZH_DESC" \
        --developer-name "$DEVELOPER_NAME" \
        --project-license "$PROJECT_LICENSE" \
        --version "$UPSTREAM_VERSION" \
        --icon-url "$ICON_URL" \
        ${HOMEPAGE:+--homepage "$HOMEPAGE"} \
        ${SCREENSHOT_URL:+--screenshot-url "$SCREENSHOT_URL"} \
        ${upstream_desktop:+--desktop-id "$upstream_desktop"} \
        --output-dir "$PKG_DIR"

    rm -rf "$tmp"

    echo ""
    echo "=== 构建完成 ==="
    echo "  metadata: ${METADATA_FILE}"
    echo "  类型: external（第三方 deb，仅元数据）"
    exit 0
fi

# --- 自主打包模式 (local / npm)：从源码构建 ---
STAGING_DIR="$(mktemp -d /tmp/build-package-XXXXXX)"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "=== 构建 ${PKG_NAME} ==="
echo "  版本: ${DEBIAN_VER}"
echo "  源码目录: ${PKG_DIR}"
echo "  输出目录: ${OUTPUT_DIR}"
echo "  staging: ${STAGING_DIR}"
echo ""

mkdir -p "${STAGING_DIR}/DEBIAN"
if [[ "$HAS_DESKTOP" = "yes" ]]; then
    mkdir -p "${STAGING_DIR}/usr/share/metainfo"
    mkdir -p "${STAGING_DIR}/usr/share/applications"
fi
mkdir -p "${STAGING_DIR}/usr/share/doc/${PKG_NAME}"

echo "--- 获取源码 (fetch_type=${FETCH_TYPE}) ---"
fetch_source "$FETCH_TYPE" "$FETCH_SOURCE" "$STAGING_DIR" "$UPSTREAM_VERSION"

echo "--- 生成 control ---"
"${TEMPLATES_DIR}/gen-control.sh" \
    --pkg-name "$NAME" \
    --version "$DEBIAN_VER" \
    --description "$DESCRIPTION" \
    --long-desc "$LONG_DESC" \
    ${DEPENDS:+--depends "$DEPENDS"} \
    ${HOMEPAGE:+--homepage "$HOMEPAGE"} \
    --staging-dir "$STAGING_DIR" \
    --output-dir "$STAGING_DIR"

echo "--- 生成 postinst ---"
"${TEMPLATES_DIR}/gen-postinst.sh" \
    --pkg-name "$NAME" \
    ${HAS_DESKTOP:+--has-desktop "$HAS_DESKTOP"} \
    --output-dir "$STAGING_DIR"

echo "--- 生成 postrm ---"
"${TEMPLATES_DIR}/gen-postrm.sh" \
    --pkg-name "$NAME" \
    ${HAS_DESKTOP:+--has-desktop "$HAS_DESKTOP"} \
    --output-dir "$STAGING_DIR"

if [[ "$HAS_DESKTOP" = "yes" ]]; then
    echo "--- 生成 metainfo ---"
    "${TEMPLATES_DIR}/gen-metainfo.sh" \
        --pkg-name "$NAME" \
        --zh-name "$ZH_NAME" \
        --zh-summary "$ZH_SUMMARY" \
        --zh-description "$ZH_DESC" \
        --developer-name "$DEVELOPER_NAME" \
        --project-license "$PROJECT_LICENSE" \
        --version "$UPSTREAM_VERSION" \
        ${HOMEPAGE:+--homepage "$HOMEPAGE"} \
        ${SCREENSHOT_URL:+--screenshot-url "$SCREENSHOT_URL"} \
        --output-dir "$STAGING_DIR"

    echo "--- 生成 desktop ---"
    "${TEMPLATES_DIR}/gen-desktop.sh" \
        --pkg-name "$NAME" \
        --zh-name "$ZH_NAME" \
        --zh-comment "$DESCRIPTION" \
        --exec "$EXEC_PATH" \
        --icon "$ICON_PATH" \
        ${ZH_KEYWORDS:+--zh-keywords "$ZH_KEYWORDS"} \
        --output-dir "$STAGING_DIR"

    echo "--- 生成 DEP-11 ---"
    "${TEMPLATES_DIR}/gen-dep11.sh" \
        --pkg-name "$NAME" \
        --zh-name "$ZH_NAME" \
        --zh-summary "$ZH_SUMMARY" \
        --zh-description "$ZH_DESC" \
        --developer-name "$DEVELOPER_NAME" \
        --project-license "$PROJECT_LICENSE" \
        --version "$UPSTREAM_VERSION" \
        --icon-url "$ICON_URL" \
        ${HOMEPAGE:+--homepage "$HOMEPAGE"} \
        ${SCREENSHOT_URL:+--screenshot-url "$SCREENSHOT_URL"} \
        --output-dir "$PKG_DIR"
fi

echo "--- 生成 copyright ---"
cat > "${STAGING_DIR}/usr/share/doc/${PKG_NAME}/copyright" << COPYEOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${PKG_NAME}
Source: ${HOMEPAGE:-N/A}

Files: *
Copyright: ${DEVELOPER_NAME}
License: ${PROJECT_LICENSE}
COPYEOF

echo "--- 生成 changelog.gz ---"
CHANGELOG_DATE=$(date -R 2>/dev/null || date '+%a, %d %b %Y %H:%M:%S %z')
COMMIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
cat > "${STAGING_DIR}/usr/share/doc/${PKG_NAME}/changelog" << CHANGELOGEOF
${PKG_NAME} (${DEBIAN_VER}) stable; urgency=medium

  * CI auto-build from commit ${COMMIT_SHA}

 -- Noatin OS Team <repo@cccczl.top>  ${CHANGELOG_DATE}
CHANGELOGEOF
gzip -9cn "${STAGING_DIR}/usr/share/doc/${PKG_NAME}/changelog" \
    > "${STAGING_DIR}/usr/share/doc/${PKG_NAME}/changelog.gz"
rm -f "${STAGING_DIR}/usr/share/doc/${PKG_NAME}/changelog"

echo "--- 打包 deb ---"
mkdir -p "$OUTPUT_DIR"
DEB_FILE="${OUTPUT_DIR}/${PKG_NAME}_${DEBIAN_VER}_amd64.deb"
dpkg-deb --build "$STAGING_DIR" "$DEB_FILE"

echo "--- lintian 检查 ---"
if command -v lintian > /dev/null 2>&1; then
    LINTIAN_RC=0
    lintian --no-tag-display-limit "$DEB_FILE" || LINTIAN_RC=$?
    if [[ $LINTIAN_RC -ne 0 ]]; then
        echo "WARN: lintian 报告错误 (exit code: ${LINTIAN_RC})"
    fi
else
    echo "SKIP: lintian 不可用，跳过检查"
fi

echo ""
echo "=== 构建完成 ==="
echo "  deb: ${DEB_FILE}"