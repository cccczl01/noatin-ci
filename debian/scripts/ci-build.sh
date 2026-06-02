#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_DIR="$(mktemp -d /tmp/noatin-repo-XXXXXX)"
PACKAGES_DIR="${PROJECT_ROOT}/debian/packages"
SCRIPTS_DIR="${PROJECT_ROOT}/debian/scripts"

if [[ -z "${GITEE_TOKEN:-}" ]]; then
    echo "错误: GITEE_TOKEN 未设置，无法 clone noatin-repo" >&2
    exit 1
fi
git clone "https://oauth2:${GITEE_TOKEN}@gitee.com/cccczl01/noatin-repo.git" "$REPO_DIR" > /dev/null 2>&1
git -C "$REPO_DIR" remote rename origin gitee
git -C "$REPO_DIR" remote add github "https://github.com/cccczl01/noatin-repo.git"
git -C "$REPO_DIR" remote add gitcode "https://gitcode.com/cccczl001/noatin-repo.git"
echo "REPO_DIR: ${REPO_DIR} (cloned from Gitee)"

DRY_RUN="false"
PKG_FILTER=""

usage() {
    cat <<'EOF'
用法: ci-build.sh [OPTIONS]

CI 编排脚本：检测 debian/packages/ 下的包变更，调用 build-package.sh 构建 deb，
GPG 签名后推送到三平台仓库，并触发 VPS 索引更新。

Options:
  --dry-run       只输出将要构建的包和推送目标，不执行实际构建
  --pkg <name>    只构建指定包（用于手动重跑单个包）
  --help          显示帮助信息

Environment Variables (CI secrets):
  GPG_PRIVATE_KEY   GPG 私钥（ASCII-armored），用于 deb 包签名
  GITEE_TOKEN       Gitee Personal Access Token
  GITHUB_TOKEN      GitHub Personal Access Token
  GITCODE_TOKEN     GitCode Personal Access Token
  VPS_API_KEY       VPS API 密钥（用于 DEP-11 上传和索引更新回调）

Exit Codes:
  0    所有包构建成功（或无需构建）
  1    一个或多个包构建失败
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift ;;
        --pkg)
            [[ -z "${2:-}" || "$2" == -* ]] && { echo "错误: --pkg 需要参数" >&2; usage; }
            PKG_FILTER="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        *)
            echo "未知参数: $1" >&2; usage ;;
    esac
done

ORIG_HEAD=$(git -C "$PROJECT_ROOT" rev-parse HEAD)

declare -A BUILD_RESULTS
FAILED_PKGS=""
TOTAL_COUNT=0
SUCCESS_COUNT=0
SKIPPED_COUNT=0

BUILD_OUTPUT_DIR="$(mktemp -d /tmp/ci-build-out-XXXXXX)"
cleanup_build() {
    rm -rf "${BUILD_OUTPUT_DIR}"
    rm -rf "${REPO_DIR}"
}
trap cleanup_build EXIT

echo "=== CI 构建流水线 ==="
echo ""
echo "模式: $([ "${DRY_RUN}" = "true" ] && echo '干跑 (--dry-run)' || echo '实际构建')"
echo "HEAD: ${ORIG_HEAD:0:7}"
echo ""

if [[ -n "$PKG_FILTER" ]]; then
    echo "指定包: ${PKG_FILTER}"
    PACKAGES=("$PKG_FILTER")
else
    if ! git -C "$PROJECT_ROOT" rev-parse HEAD~1 > /dev/null 2>&1; then
        echo "No package changes detected, skipping build"
        exit 0
    fi

    CHANGED_FILES=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null || true)
    PACKAGES=()
    while IFS= read -r file; do
        if [[ "$file" == debian/packages/* ]]; then
            pkg_dir="${file#debian/packages/}"
            pkg_name="${pkg_dir%%/*}"
            if [[ -n "$pkg_name" ]]; then
                found=0
                for existing in "${PACKAGES[@]:-}"; do
                    [[ "$existing" == "$pkg_name" ]] && found=1 && break
                done
                if [[ $found -eq 0 ]]; then
                    PACKAGES+=("$pkg_name")
                fi
            fi
        fi
    done <<< "$CHANGED_FILES"
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "No package changes detected, skipping build"
    exit 0
fi

echo "检测到变更包 (${#PACKAGES[@]} 个):"
for pkg in "${PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""

for pkg_name in "${PACKAGES[@]}"; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    PKG_DIR="${PACKAGES_DIR}/${pkg_name}"

    echo ">>> [${pkg_name}] 开始处理"

    if [[ ! -d "$PKG_DIR" ]]; then
        echo "  SKIP: 包目录不存在: ${PKG_DIR}"
        BUILD_RESULTS["${pkg_name}"]="SKIPPED"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo ""
        continue
    fi

    BUILD_CONF="${PKG_DIR}/build.conf"
    if [[ ! -f "$BUILD_CONF" ]]; then
        echo "  SKIP: 缺少 build.conf"
        BUILD_RESULTS["${pkg_name}"]="SKIPPED"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo ""
        continue
    fi

    declare -A CONF
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        CONF["$key"]="$value"
    done < "$BUILD_CONF"

    NAME="${CONF[name]}"
    UPSTREAM_VERSION="${CONF[upstream_version]}"
    DEBIAN_REVISION="${CONF[debian_revision]}"
    DEBIAN_VER="${UPSTREAM_VERSION}-${DEBIAN_REVISION}"
    PKG="noatin-${NAME}"

    PKG_REPO_DIR="${REPO_DIR}/${PKG}/pool/${DEBIAN_VER}"
    REPO_DEP11_DIR="${REPO_DIR}/dep11"
    SRC_DEP11_YML="${PKG_DIR}/dep11/com.noatin.${NAME}.yml"

    if [[ "${DRY_RUN}" = "true" ]]; then
        echo "  [DRY-RUN] 构建: build-package.sh --pkg-dir ${PKG_DIR}"
        echo "  [DRY-RUN] 输出: ${PKG_REPO_DIR}/${PKG}_${DEBIAN_VER}_amd64.deb"
        echo "  [DRY-RUN] DEP-11: ${SRC_DEP11_YML} → ${REPO_DEP11_DIR}/"
        echo "  [DRY-RUN] 推送: Gitee → GitHub (sync-mirrors.sh) → GitCode"
        echo "  [DRY-RUN] VPS: DEP-11 上传 + 索引更新回调"
        echo "  SUCCESS: ${pkg_name} (干跑)"
        BUILD_RESULTS["${pkg_name}"]="SUCCESS"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo ""
        continue
    fi

    set +e
    "${SCRIPTS_DIR}/build-package.sh" \
        --pkg-dir "$PKG_DIR" \
        --output-dir "$BUILD_OUTPUT_DIR" \
        > /tmp/ci-build-${pkg_name}.log 2>&1
    BUILD_RC=$?
    set -e

    if [[ $BUILD_RC -ne 0 ]]; then
        echo "  FAILED: build-package.sh 退出码 ${BUILD_RC}"
        cat /tmp/ci-build-${pkg_name}.log
        BUILD_RESULTS["${pkg_name}"]="FAILED"
        FAILED_PKGS="${FAILED_PKGS} ${pkg_name}"
        echo ""
        continue
    fi

    DEB_FILE=$(find "$BUILD_OUTPUT_DIR" -name "${PKG}_*_amd64.deb" | head -1)
    if [[ -z "$DEB_FILE" || ! -f "$DEB_FILE" ]]; then
        echo "  FAILED: 未找到生成的 deb 文件"
        BUILD_RESULTS["${pkg_name}"]="FAILED"
        FAILED_PKGS="${FAILED_PKGS} ${pkg_name}"
        echo ""
        continue
    fi

    echo "  deb: ${DEB_FILE}"

    mkdir -p "$PKG_REPO_DIR"
    cp "$DEB_FILE" "$PKG_REPO_DIR/"
    echo "  COPY: ${DEB_FILE} → ${PKG_REPO_DIR}/"

    if [[ -f "$SRC_DEP11_YML" ]]; then
        mkdir -p "$REPO_DEP11_DIR"
        cp "$SRC_DEP11_YML" "$REPO_DEP11_DIR/"
        echo "  COPY-DEP11: ${SRC_DEP11_YML} → ${REPO_DEP11_DIR}/"
    else
        echo "  WARN: DEP-11 YAML 不存在: ${SRC_DEP11_YML}"
    fi

    if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
        echo "  GPG: 导入私钥..."
        KEY_ID=""
        if gpg --batch --import <<< "${GPG_PRIVATE_KEY}" 2>/dev/null; then
            KEY_ID=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | head -1 | cut -d: -f5)
            if [[ -n "$KEY_ID" ]]; then
                REPO_DEB="${PKG_REPO_DIR}/${PKG}_${DEBIAN_VER}_amd64.deb"
                if command -v dpkg-sig > /dev/null 2>&1; then
                    dpkg-sig --sign builder "$REPO_DEB" 2>/dev/null && echo "  GPG: dpkg-sig 签名成功" || echo "  WARN: dpkg-sig 签名失败"
                else
                    gpg --batch --yes --detach-sign --local-user "$KEY_ID" "$REPO_DEB" 2>/dev/null && echo "  GPG: detach-sign 签名成功" || echo "  WARN: GPG 签名失败"
                fi
            else
                echo "  WARN: 无法解析 GPG key ID"
            fi
            gpg --batch --yes --delete-secret-and-public-key "$KEY_ID" 2>/dev/null || true
            echo "  GPG: 密钥已清理"
        else
            echo "  WARN: GPG 私钥导入失败，跳过签名"
        fi
    else
        echo "  GPG: GPG_PRIVATE_KEY 未设置，跳过签名（仅本地/干跑模式正常）"
    fi

    echo "  GIT: 添加构建产物..."
    REPO_CHANGELOG_DIR="${REPO_DIR}/_changelog"
    mkdir -p "${REPO_CHANGELOG_DIR}"

    CHANGELOG_DATE=$(date '+%Y-%m-%d')
    ORIG_COMMIT_MSG=$(git -C "$PROJECT_ROOT" log -1 --format=%s "$ORIG_HEAD" 2>/dev/null || echo "CI: build ${PKG} ${DEBIAN_VER}")
    CHANGELOG_SUMMARY=""
    if echo "${ORIG_COMMIT_MSG}" | grep -q '^feat:'; then
        CHANGELOG_SUMMARY=$(echo "${ORIG_COMMIT_MSG}" | sed 's/^feat:[[:space:]]*//')
    elif echo "${ORIG_COMMIT_MSG}" | grep -q '^fix:'; then
        CHANGELOG_SUMMARY=$(echo "${ORIG_COMMIT_MSG}" | sed 's/^fix:[[:space:]]*//')
    elif echo "${ORIG_COMMIT_MSG}" | grep -qP '\[changelog:\s*([^\]]+)\]'; then
        CHANGELOG_SUMMARY=$(echo "${ORIG_COMMIT_MSG}" | grep -oP '\[changelog:\s*\K[^\]]+')
    elif echo "${ORIG_COMMIT_MSG}" | grep -q '^chore:'; then
        CHANGELOG_SUMMARY="更新 ${PKG} 至 ${DEBIAN_VER}"
    elif echo "${ORIG_COMMIT_MSG}" | grep -qP '\[changelog:\s*([^\]]+)\]'; then
        CHANGELOG_SUMMARY=$(echo "${ORIG_COMMIT_MSG}" | grep -oP '\[changelog:\s*\K[^\]]+')
    else
        CHANGELOG_SUMMARY="${PKG} ${DEBIAN_VER}"
    fi
    CHANGELOG_JSON_FILE="${REPO_CHANGELOG_DIR}/${CHANGELOG_DATE}-${PKG}-${DEBIAN_VER}.json"
    cat > "${CHANGELOG_JSON_FILE}" << CHANGELOGEOF
{
    "package": "${PKG}",
    "version": "${DEBIAN_VER}",
    "date": "${CHANGELOG_DATE}",
    "summary": "${CHANGELOG_SUMMARY}"
}
CHANGELOGEOF
    echo "  CHANGELOG: ${CHANGELOG_JSON_FILE}"
    git -C "$REPO_DIR" add "${CHANGELOG_JSON_FILE#${REPO_DIR}/}/" 2>/dev/null || true

    git -C "$REPO_DIR" add "${PKG_REPO_DIR#${REPO_DIR}/}/" 2>/dev/null || true
    if [[ -f "$SRC_DEP11_YML" ]]; then
        REPO_DEP11_DEST="${REPO_DEP11_DIR}/$(basename "$SRC_DEP11_YML")"
        git -C "$REPO_DIR" add "${REPO_DEP11_DEST#${REPO_DIR}/}/" 2>/dev/null || true
    fi

    COMMIT_MSG="CI: build ${PKG} ${DEBIAN_VER} [${ORIG_HEAD:0:7}]"
    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "  GIT: 无变更需要提交"
    else
        git -C "$REPO_DIR" commit -m "$COMMIT_MSG" 2>/dev/null || true
        echo "  GIT: 已提交 — ${COMMIT_MSG}"
    fi

    GITEE_REMOTE="gitee"
    if git -C "$REPO_DIR" remote get-url "$GITEE_REMOTE" > /dev/null 2>&1; then
        if [[ -n "${GITEE_TOKEN:-}" ]]; then
            GITEE_URL="https://oauth2:${GITEE_TOKEN}@gitee.com/cccczl01/noatin-repo.git"
        else
            GITEE_URL="$(git -C "$REPO_DIR" remote get-url "$GITEE_REMOTE")"
        fi
        echo "  PUSH: Gitee..."
        set +e
        # fetch + rebase before push to handle concurrent remote changes
        LOCAL_SHA=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
        push_output=$(git -C "$REPO_DIR" push "$GITEE_URL" main 2>&1)
        GITEE_RC=$?
        set -e
        echo "${push_output}" | sed 's|https://[^@]*@|https://***@|g'

        # If "Everything up-to-date" but local has new commits, try fetch+rebase+push
        if [[ $GITEE_RC -eq 0 ]] && echo "${push_output}" | grep -q "Everything up-to-date"; then
            if [[ -n "$LOCAL_SHA" ]]; then
                REMOTE_SHA=$(git -C "$REPO_DIR" ls-remote "$GITEE_URL" refs/heads/main 2>/dev/null | awk '{print $1}')
                if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
                    echo "  PUSH: 检测到远程有新提交，尝试 fetch + rebase..."
                    set +e
                    git -C "$REPO_DIR" fetch "$GITEE_URL" main 2>&1 | sed 's|https://[^@]*@|https://***@|g'
                    git -C "$REPO_DIR" rebase FETCH_HEAD 2>&1
                    rebase_push_output=$(git -C "$REPO_DIR" push "$GITEE_URL" main 2>&1)
                    GITEE_RC=$?
                    set -e
                    echo "${rebase_push_output}" | sed 's|https://[^@]*@|https://***@|g'
                fi
            fi
        fi

        if [[ $GITEE_RC -eq 0 ]]; then
            echo "  PUSH: Gitee 推送成功"
        else
            echo "  WARN: Gitee 推送失败 (exit code: ${GITEE_RC})"
        fi
    else
        echo "  WARN: Gitee remote 未配置，跳过推送"
    fi

    SYNC_SCRIPT="${REPO_DIR}/scripts/sync-mirrors.sh"
    if [[ -f "$SYNC_SCRIPT" ]]; then
        echo "  SYNC: 调用 sync-mirrors.sh..."
        set +e
        bash "$SYNC_SCRIPT"
        SYNC_RC=$?
        set -e
        if [[ $SYNC_RC -eq 0 ]]; then
            echo "  SYNC: 三平台镜像同步完成"
        else
            echo "  WARN: sync-mirrors.sh 退出码 ${SYNC_RC}"
        fi
    else
        echo "  WARN: sync-mirrors.sh 不存在，跳过镜像同步"
    fi

    if [[ -f "$SRC_DEP11_YML" && -n "${VPS_API_KEY:-}" ]]; then
        if command -v curl > /dev/null 2>&1; then
            VPS_DEP11_URL="${VPS_DEP11_URL:-}"
            if [[ -n "$VPS_DEP11_URL" ]]; then
                echo "  VPS: 上传 DEP-11 YAML..."
                set +e
                curl -s -X POST \
                    -H "Authorization: Bearer ${VPS_API_KEY}" \
                    -H "Content-Type: application/x-yaml" \
                    --data-binary "@${SRC_DEP11_YML}" \
                    "$VPS_DEP11_URL" 2>&1 | head -5
                CURL_RC=$?
                set -e
                if [[ $CURL_RC -eq 0 ]]; then
                    echo "  VPS: DEP-11 上传成功"
                else
                    echo "  WARN: VPS DEP-11 上传失败 (exit code: ${CURL_RC})"
                fi
            else
                echo "  WARN: VPS_DEP11_URL 未设置，跳过 DEP-11 上传"
            fi

            VPS_CALLBACK_URL="${VPS_CALLBACK_URL:-}"
            if [[ -n "$VPS_CALLBACK_URL" ]]; then
                echo "  VPS: 触发索引更新..."
                set +e
                curl -s -X POST \
                    -H "Authorization: Bearer ${VPS_API_KEY}" \
                    "$VPS_CALLBACK_URL" 2>&1 | head -5
                CURL_RC=$?
                set -e
                if [[ $CURL_RC -eq 0 ]]; then
                    echo "  VPS: 索引更新触发成功"
                else
                    echo "  WARN: VPS 索引更新触发失败 (exit code: ${CURL_RC})"
                fi
            else
                echo "  WARN: VPS_CALLBACK_URL 未设置，跳过索引更新触发"
            fi
        else
            echo "  WARN: curl 不可用，跳过 VPS HTTP 操作"
        fi
    else
        if [[ ! -f "$SRC_DEP11_YML" ]]; then
            echo "  VPS: 跳过（无 DEP-11 YAML）"
        else
            echo "  WARN: VPS_API_KEY 未设置，跳过 VPS 操作"
        fi
    fi

    rm -f /tmp/ci-build-${pkg_name}.log

    echo "  SUCCESS: ${pkg_name}"
    BUILD_RESULTS["${pkg_name}"]="SUCCESS"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo ""
done

echo ""
echo "============================================================"
echo "构建结果汇总: 总计 ${TOTAL_COUNT}, 成功 ${SUCCESS_COUNT}, 跳过 ${SKIPPED_COUNT}"
echo "============================================================"

for pkg_name in "${PACKAGES[@]}"; do
    echo "  ${pkg_name}: ${BUILD_RESULTS[${pkg_name}]}"
done

if [[ -n "$FAILED_PKGS" ]]; then
    echo ""
    echo "FAILED:${FAILED_PKGS}"
    exit 1
fi

echo ""
echo "所有包构建完成。"
exit 0