#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com/repos/cccczl01/noatin-repo}"
GITHUB_RAW_BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/cccczl01/noatin-repo/main}"

RETRY_MAX="${RETRY_MAX:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=""

usage() {
    cat <<'EOF'
用法: check-external-urls.sh [OPTIONS]

检查 GitHub 仓库中所有 external 包的 upstream_url 可达性。
失效的 URL 会输出到 stdout，供 CI 创建 Issue 使用。

Options:
  --help           显示帮助信息

Environment Variables:
  GITHUB_API_BASE   GitHub API 基地址 (默认: https://api.github.com/repos/cccczl01/noatin-repo)
  GITHUB_RAW_BASE   GitHub raw 基地址 (默认: https://raw.githubusercontent.com/cccczl01/noatin-repo/main)
  GITHUB_TOKEN      可选，私有仓库认证 token
  RETRY_MAX         HTTP 检查重试次数 (默认: 3)
  RETRY_DELAY       重试间隔秒数 (默认: 10)

Exit Codes:
  0    所有 upstream_url 可达
  1    一个或多个 upstream_url 不可达
EOF
    exit 0
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
fi

echo "=== 外部链接健康检查 ==="
echo ""

TOKEN_HEADER=""
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    TOKEN_HEADER="Authorization: token ${GITHUB_TOKEN}"
fi

echo ">>> 从 GitHub API 获取仓库文件树 ..."
GITHUB_TREE_URL="${GITHUB_API_BASE}/git/trees/main?recursive=1"
API_RESPONSE=$(curl -s ${TOKEN_HEADER:+-H "$TOKEN_HEADER"} "${GITHUB_TREE_URL}" 2>/dev/null || true)

if [[ -z "${API_RESPONSE}" ]]; then
    echo "ERROR: GitHub API 无响应，请检查网络或 GITHUB_API_BASE 配置" >&2
    exit 1
fi

if echo "${API_RESPONSE}" | grep -q '"message"'; then
    echo "ERROR: GitHub API 返回错误:" >&2
    echo "${API_RESPONSE}" | grep -oP '"message":"\K[^"]+' >&2
    exit 1
fi

META_PATHS=$(echo "${API_RESPONSE}" | grep -oP '"path":\s*"\K[^"]+/pool/[^"]+/metadata\.json(?=")' || true)

if [[ -z "${META_PATHS}" ]]; then
    echo "未发现任何 external 包 (metadata.json)，跳过检查"
    exit 0
fi

echo "发现 external 包:"
echo "${META_PATHS}" | while IFS= read -r path; do
    echo "  - ${path}"
done
echo ""

while IFS= read -r meta_path || [[ -n "${meta_path}" ]]; do
    [[ -z "${meta_path}" ]] && continue

    PKG_NAME=$(echo "${meta_path}" | cut -d/ -f1)
    PKG_VERSION=$(echo "${meta_path}" | cut -d/ -f3)
    META_URL="${GITHUB_RAW_BASE}/${meta_path}"

    echo "--- ${PKG_NAME} ${PKG_VERSION} ---"
    echo "    metadata: ${META_URL}"

    META_JSON=$(curl -s ${TOKEN_HEADER:+-H "$TOKEN_HEADER"} "${META_URL}" 2>/dev/null || true)
    if [[ -z "${META_JSON}" ]]; then
        echo "    WARNING: 无法读取 metadata.json"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST}  - ${PKG_NAME} ${PKG_VERSION}: 无法读取 metadata.json\n"
        continue
    fi

    if ! command -v python3 > /dev/null 2>&1; then
        echo "    WARNING: python3 不可用，无法解析 metadata.json"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST}  - ${PKG_NAME} ${PKG_VERSION}: python3 不可用\n"
        continue
    fi

    set +e
    UPSTREAM_URL=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('download', {}).get('upstream_url', ''))
except:
    print('')
" <<< "${META_JSON}" 2>/dev/null)
    set -e

    if [[ -z "${UPSTREAM_URL}" ]]; then
        echo "    WARNING: metadata.json 中无 upstream_url"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST}  - ${PKG_NAME} ${PKG_VERSION}: metadata.json 缺少 upstream_url\n"
        continue
    fi

    echo "    检查: ${UPSTREAM_URL}"

    upstream_ok=false
    for attempt in $(seq 1 "${RETRY_MAX}"); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I -L --max-time 10 "${UPSTREAM_URL}" 2>/dev/null || echo "000")
        if [[ "${HTTP_CODE}" = "200" ]] || [[ "${HTTP_CODE}" = "302" ]]; then
            echo "    OK: HTTP ${HTTP_CODE} (attempt ${attempt})"
            upstream_ok=true
            PASS_COUNT=$((PASS_COUNT + 1))
            break
        fi
        if [[ $attempt -lt "${RETRY_MAX}" ]]; then
            echo "    HTTP ${HTTP_CODE} (attempt ${attempt}), retry in ${RETRY_DELAY}s ..."
            sleep "${RETRY_DELAY}"
        else
            echo "    FAIL: HTTP ${HTTP_CODE} (attempt ${attempt}, exhausted)"
        fi
    done

    if ! $upstream_ok; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="${FAIL_LIST}  - ${PKG_NAME} ${PKG_VERSION}: ${UPSTREAM_URL} (HTTP ${HTTP_CODE:-000})\n"
    fi

    echo ""
done <<< "${META_PATHS}"

echo "============================================================"
echo "健康检查结果: 通过 ${PASS_COUNT}, 失败 ${FAIL_COUNT}"
echo "============================================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "失效的 upstream_url:"
    echo -e "${FAIL_LIST}"
    exit 1
fi

echo ""
echo "所有 upstream_url 可达"
exit 0