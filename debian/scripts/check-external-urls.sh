#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGES_DIR="${PROJECT_ROOT}/debian/packages"

GITHUB_RAW_BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/cccczl01/noatin-repo/main}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com/repos/cccczl01/noatin-repo}"

FAIL_COUNT=0
ISSUE_BODY="## 外部链接健康检查报告\n\n"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

usage() {
    cat <<'EOF'
Usage: check-external-urls.sh

检查 GitHub 仓库中所有 external 包的 upstream_url 可达性。
不可达的链接将被记录到 GitHub Issue 中。

环境变量:
  GITHUB_TOKEN      GitHub Personal Access Token（用于创建 Issue）
  GITHUB_RAW_BASE   GitHub raw URL 基地址
  GITHUB_API_BASE   GitHub API 基地址

退出码:
  0  所有链接可达
  1  存在不可达链接
EOF
}

echo "=== 外部链接健康检查 ==="
echo ""

# 通过 GitHub API 获取仓库文件树，发现 metadata.json
GITHUB_TREE_URL="${GITHUB_API_BASE}/git/trees/main?recursive=1"
echo "查询 GitHub API: ${GITHUB_TREE_URL}"
API_RESPONSE=$(curl -s "${GITHUB_TREE_URL}" 2>/dev/null || true)

if [ -z "${API_RESPONSE}" ]; then
    echo "ERROR: GitHub API 无响应" >&2
    exit 1
fi

META_PATHS=$(echo "${API_RESPONSE}" | grep -oP '"path":"\K[^"]+/pool/[^"]+/metadata\.json(?=")' || true)

if [ -z "${META_PATHS}" ]; then
    echo "未发现 external 包，跳过检查"
    exit 0
fi

echo "发现 external 包 metadata.json:"
echo "${META_PATHS}" | while read -r p; do echo "  - ${p}"; done
echo ""

while IFS= read -r meta_path || [ -n "${meta_path}" ]; do
    [ -z "${meta_path}" ] && continue

    META_URL="${GITHUB_RAW_BASE}/${meta_path}"
    PKG_NAME=$(echo "${meta_path}" | cut -d/ -f1)
    PKG_VERSION=$(echo "${meta_path}" | cut -d/ -f3)

    echo "--- ${PKG_NAME} ${PKG_VERSION} ---"

    META_JSON=$(wget -q -O - --connect-timeout=30 --timeout=60 "${META_URL}" 2>/dev/null || true)
    if [ -z "${META_JSON}" ]; then
        echo "  WARNING: 无法读取 metadata.json"
        continue
    fi

    UPSTREAM_URL=$(echo "${META_JSON}" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('download', {}).get('upstream_url', ''))
" 2>/dev/null || echo "")

    R2_URL=$(echo "${META_JSON}" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('download', {}).get('r2_url', ''))
" 2>/dev/null || echo "")

    if [ -z "${UPSTREAM_URL}" ]; then
        echo "  WARNING: upstream_url 为空，跳过"
        continue
    fi

    echo "  upstream_url: ${UPSTREAM_URL}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I -L --max-time 15 "${UPSTREAM_URL}" 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ]; then
        echo "  OK: HTTP ${HTTP_CODE}"
    else
        echo "  FAIL: HTTP ${HTTP_CODE}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ISSUE_BODY="${ISSUE_BODY}\n- **${PKG_NAME} ${PKG_VERSION}**: upstream_url 不可达 (HTTP ${HTTP_CODE})"
        if [ -n "${R2_URL}" ]; then
            ISSUE_BODY="${ISSUE_BODY}\n  - 灾备 R2: ${R2_URL}"
        fi
        ISSUE_BODY="${ISSUE_BODY}\n  - URL: ${UPSTREAM_URL}\n"
    fi
done <<< "${META_PATHS}"

ISSUE_BODY="${ISSUE_BODY}\n\n---\n检查时间: ${TIMESTAMP}"

echo ""
echo "============================================================"
echo "健康检查结果: ${FAIL_COUNT} 个链接不可达"
echo "============================================================"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    # 创建 GitHub Issue
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "创建 GitHub Issue..."
        ISSUE_TITLE="[Health Check] ${FAIL_COUNT} 个外部链接不可达 (${TIMESTAMP})"
        ISSUE_JSON=$(python3 -c "
import json, sys
print(json.dumps({
    'title': sys.argv[1],
    'body': sys.argv[2],
    'labels': ['health-check', 'external-url']
}))
" "${ISSUE_TITLE}" "${ISSUE_BODY}" 2>/dev/null)

        if [ -n "${ISSUE_JSON}" ]; then
            curl -s -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${ISSUE_JSON}" \
                "https://api.github.com/repos/cccczl01/noatin-repo/issues" \
                > /dev/null 2>&1 && echo "  OK: Issue 已创建" || echo "  WARNING: Issue 创建失败"
        fi
    else
        echo "WARNING: GITHUB_TOKEN 未设置，跳过 Issue 创建"
    fi
    exit 1
fi

echo ""
echo "OK: 所有外部链接可达"
exit 0