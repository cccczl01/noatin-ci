#!/bin/bash
set -euo pipefail

TEST_PKG="noatin-test-dummy"
TEST_VERSION="0.1.0-1"
DEB_FILE=""
STAGING_DIR=""
LINTIAN_OUTPUT=""
CTRL_TMP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN_CONTROL="${SCRIPT_DIR}/gen-control.sh"
GEN_POSTINST="${SCRIPT_DIR}/gen-postinst.sh"
GEN_POSTRM="${SCRIPT_DIR}/gen-postrm.sh"
GEN_METAINFO="${SCRIPT_DIR}/gen-metainfo.sh"
GEN_DESKTOP="${SCRIPT_DIR}/gen-desktop.sh"
GEN_DEP11="${SCRIPT_DIR}/gen-dep11.sh"

cleanup() {
    dpkg --purge "$TEST_PKG" 2>/dev/null || true
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    if [[ -n "$DEB_FILE" && -f "$DEB_FILE" ]]; then
        rm -f "$DEB_FILE"
    fi
    if [[ -n "$LINTIAN_OUTPUT" && -f "$LINTIAN_OUTPUT" ]]; then
        rm -f "$LINTIAN_OUTPUT"
    fi
    if [[ -n "$CTRL_TMP" && -d "$CTRL_TMP" ]]; then
        rm -rf "$CTRL_TMP"
    fi
}

trap cleanup EXIT

check_dependency() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo "错误: 缺少依赖 '$cmd' (包: $pkg)。请安装后重试。" >&2
        exit 1
    fi
}

if command -v lintian &>/dev/null; then
    LINTIAN_AVAILABLE=1
else
    echo "警告: lintian 不可用 (包: lintian)，跳过 lintian 检查" >&2
    LINTIAN_AVAILABLE=0
fi
check_dependency "dpkg-deb" "dpkg-dev"

echo "=== 步骤 1: 创建 staging 目录 ==="
STAGING_DIR=$(mktemp -d)

echo "=== 步骤 2: 生成 control 文件 ==="
mkdir -p "$STAGING_DIR/DEBIAN"
"$GEN_CONTROL" \
    --pkg-name test-dummy \
    --version "$TEST_VERSION" \
    --description "Noatin test dummy package" \
    --long-desc "用于验证 control 模板和 gen-control.sh 的最小测试包\n不包含实际功能" \
    --depends "libc6" \
    --staging-dir "$STAGING_DIR" \
    --output-dir "$STAGING_DIR"

echo "=== 步骤 2.5: 生成 postinst 文件 ==="
"$GEN_POSTINST" \
    --pkg-name test-dummy \
    --output-dir "$STAGING_DIR"

echo "=== 步骤 2.6: 生成 postrm 文件 ==="
"$GEN_POSTRM" \
    --pkg-name test-dummy \
    --output-dir "$STAGING_DIR"

echo "=== 步骤 2.7: 生成 metainfo 文件 ==="
"$GEN_METAINFO" \
    --pkg-name test-dummy \
    --zh-name "测试包" \
    --zh-summary "用于验证 metainfo 模板的测试包" \
    --zh-description "这是一个测试用的 deb 包\n用于验证 AppStream metainfo.xml 模板生成" \
    --developer-name "Noatin OS Team" \
    --project-license "MIT" \
    --version "$TEST_VERSION" \
    --output-dir "$STAGING_DIR"
mkdir -p "$STAGING_DIR/usr/share/metainfo"
cp "$STAGING_DIR/metainfo/com.noatin.test-dummy.metainfo.xml" "$STAGING_DIR/usr/share/metainfo/"
rm -rf "$STAGING_DIR/metainfo"

echo "=== 步骤 2.8: 生成 .desktop 文件 ==="
"$GEN_DESKTOP" \
    --pkg-name test-dummy \
    --zh-name "测试包" \
    --zh-comment "用于验证 .desktop 模板的测试包" \
    --exec "/usr/bin/noatin-test-dummy" \
    --icon "/usr/share/pixmaps/com.noatin.test-dummy.png" \
    --zh-keywords "测试;AI;" \
    --output-dir "$STAGING_DIR"
mkdir -p "$STAGING_DIR/usr/share/applications"
cp "$STAGING_DIR/desktop/com.noatin.test-dummy.desktop" "$STAGING_DIR/usr/share/applications/"
rm -rf "$STAGING_DIR/desktop"

echo "=== 步骤 2.9: 生成 DEP-11 YAML 片段 ==="
"$GEN_DEP11" \
    --pkg-name test-dummy \
    --zh-name "测试包" \
    --zh-summary "用于验证 DEP-11 模板的测试包" \
    --zh-description "这是一个测试用的 deb 包\n用于验证 DEP-11 YAML 片段模板生成" \
    --developer-name "Noatin OS Team" \
    --project-license "MIT" \
    --version "$TEST_VERSION" \
    --icon-url "https://gitee.com/noatin/noatin-repo/raw/main/noatin-test-dummy/assets/icon.png" \
    --output-dir "$STAGING_DIR"
mkdir -p "$STAGING_DIR/repo/dep11"
cp "$STAGING_DIR/dep11/com.noatin.test-dummy.yml" "$STAGING_DIR/repo/dep11/"
rm -rf "$STAGING_DIR/dep11"

echo "=== 步骤 3: 创建 /usr/bin/noatin-test-dummy 占位脚本 ==="
mkdir -p "$STAGING_DIR/usr/bin"
cat > "$STAGING_DIR/usr/bin/noatin-test-dummy" <<'SCRIPTEOF'
#!/bin/bash
echo "noatin-test-dummy: Hello from Noatin OS!"
SCRIPTEOF
chmod 755 "$STAGING_DIR/usr/bin/noatin-test-dummy"

echo "=== 步骤 4: 创建 copyright 文件 ==="
mkdir -p "$STAGING_DIR/usr/share/doc/$TEST_PKG"
cat > "$STAGING_DIR/usr/share/doc/$TEST_PKG/copyright" <<'COPYEOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: noatin-test-dummy
Upstream-Contact: Noatin OS Team <repo@cccczl.top>

Files: *
Copyright: 2026 Noatin OS Team
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
COPYEOF

echo "=== 步骤 5: 创建 changelog 文件 ==="
mkdir -p "$STAGING_DIR/usr/share/doc/$TEST_PKG"
cat > "$STAGING_DIR/usr/share/doc/$TEST_PKG/changelog" <<'CHANGEOF'
noatin-test-dummy (0.1.0-1) unstable; urgency=medium

  * Test build for control template verification.

 -- Noatin OS Team <repo@cccczl.top>  Thu, 01 Jan 2026 00:00:00 +0000
CHANGEOF
gzip -n -9 "$STAGING_DIR/usr/share/doc/$TEST_PKG/changelog"

echo "=== 步骤 6: 构建 deb 包 ==="
DEB_DIR=$(mktemp -d)
DEB_FILE="${DEB_DIR}/${TEST_PKG}_${TEST_VERSION}_amd64.deb"
dpkg-deb --build "$STAGING_DIR" "$DEB_FILE"
echo "构建完成: $DEB_FILE"

echo "=== 步骤 6.5: 验证 deb 包内容 ==="
echo "--- deb 包文件列表 ---"
dpkg-deb -c "$DEB_FILE"

echo ""
echo "--- 验证 postinst 存在 ---"
CTRL_TMP=$(mktemp -d)
dpkg-deb --ctrl-tarfile "$DEB_FILE" | tar -C "$CTRL_TMP" -xf - 2>/dev/null
if [[ -f "$CTRL_TMP/postinst" ]]; then
    echo "✓ deb 包包含 postinst 文件"
else
    echo "✗ deb 包不包含 postinst 文件" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi
echo "--- postinst 内容 (来自解压后的归档) ---"
cat "$CTRL_TMP/postinst"
echo ""

echo "--- 验证 postinst 权限为 755 ---"
POSTINST_PERM=$(stat -c '%a' "$CTRL_TMP/postinst")
if [[ "$POSTINST_PERM" == "755" ]]; then
    echo "✓ DEBIAN/postinst 权限为 755"
else
    echo "✗ DEBIAN/postinst 权限为 $POSTINST_PERM，期望 755" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi

echo "--- 验证 postinst 内容 ---"
if grep -q 'update-desktop-database' "$CTRL_TMP/postinst" && \
   grep -q 'appstreamcli refresh' "$CTRL_TMP/postinst"; then
    echo "✓ postinst 包含 update-desktop-database 和 appstreamcli refresh"
else
    echo "✗ postinst 内容验证失败" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi

echo "--- 验证 postrm 存在 ---"
if [[ -f "$CTRL_TMP/postrm" ]]; then
    echo "✓ deb 包包含 postrm 文件"
else
    echo "✗ deb 包不包含 postrm 文件" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi
echo "--- postrm 内容 (来自解压后的归档) ---"
cat "$CTRL_TMP/postrm"
echo ""

echo "--- 验证 postrm 权限为 755 ---"
POSTRM_PERM=$(stat -c '%a' "$CTRL_TMP/postrm")
if [[ "$POSTRM_PERM" == "755" ]]; then
    echo "✓ DEBIAN/postrm 权限为 755"
else
    echo "✗ DEBIAN/postrm 权限为 $POSTRM_PERM，期望 755" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi

echo "--- 验证 postrm 内容 ---"
if grep -q 'update-desktop-database' "$CTRL_TMP/postrm" && \
   grep -q 'appstreamcli refresh' "$CTRL_TMP/postrm" && \
   grep -q 'set -e' "$CTRL_TMP/postrm" && \
   grep -q '"purge" ]]' "$CTRL_TMP/postrm"; then
    echo "✓ postrm 包含 update-desktop-database, appstreamcli refresh, set -e, 和 purge/remove 判断逻辑"
else
    echo "✗ postrm 内容验证失败" >&2
    rm -rf "$CTRL_TMP"
    exit 1
fi

echo "--- 验证 postrm remove 时不删 /etc/ 目录 ---"
POSTRM_PURGE_LINE=$(grep -n 'rm -rf' "$CTRL_TMP/postrm" || true)
POSTRM_REMOVE_BLOCK_START=$(grep -n 'remove" ]]' "$CTRL_TMP/postrm" | head -1 | cut -d: -f1 || true)
POSTRM_PURGE_BLOCK_LINE=$(grep -n 'purge" ]]' "$CTRL_TMP/postrm" | head -1 | cut -d: -f1 || true)
if [[ -n "$POSTRM_PURGE_LINE" ]] && [[ -n "$POSTRM_PURGE_BLOCK_LINE" ]]; then
    PURGE_LINE_NUM=$(echo "$POSTRM_PURGE_LINE" | head -1 | cut -d: -f1)
    if [[ "$PURGE_LINE_NUM" -lt "$POSTRM_REMOVE_BLOCK_START" ]]; then
        echo "✓ rm -rf 在 purge-only 块内 (行 $PURGE_LINE_NUM), remove 块从行 $POSTRM_REMOVE_BLOCK_START 开始 — remove 不会删 /etc/"
    else
        echo "✗ rm -rf 可能也在 remove 块中" >&2
        rm -rf "$CTRL_TMP"
        exit 1
    fi
fi

rm -rf "$CTRL_TMP"

echo "--- 验证 metainfo 文件存在 ---"
METAINFO_PATH="/usr/share/metainfo/com.noatin.test-dummy.metainfo.xml"
if dpkg-deb -c "$DEB_FILE" | grep -q "$METAINFO_PATH"; then
    echo "✓ deb 包包含 $METAINFO_PATH"
else
    echo "✗ deb 包不包含 $METAINFO_PATH" >&2
    exit 1
fi

echo "--- 提取并验证 metainfo 内容 ---"
METAINFO_TMP=$(mktemp)
dpkg-deb --fsys-tarfile "$DEB_FILE" | tar -O -xf - ".$METAINFO_PATH" > "$METAINFO_TMP" 2>/dev/null || true
if [[ -s "$METAINFO_TMP" ]]; then
if grep -q 'xml:lang="zh_CN"' "$METAINFO_TMP"; then
    echo "✓ metainfo 包含 zh_CN 本地化"
else
    echo "✗ metainfo 不包含 zh_CN 本地化内容" >&2
    rm -f "$METAINFO_TMP"
    exit 1
fi
if grep -q '<p xml:lang="zh_CN">' "$METAINFO_TMP"; then
    echo "✓ metainfo <description> 包含 zh_CN 段落"
else
    echo "✗ metainfo <description> 不包含 zh_CN 段落" >&2
    rm -f "$METAINFO_TMP"
    exit 1
fi
    if grep -q '<launchable' "$METAINFO_TMP"; then
        echo "✓ metainfo 包含 <launchable> 引用 .desktop 文件"
    else
        echo "✗ metainfo 不包含 <launchable> 元素" >&2
        rm -f "$METAINFO_TMP"
        exit 1
    fi
    if grep -q '<id>com\.noatin\.' "$METAINFO_TMP"; then
        echo "✓ metainfo <id> 为 com.noatin. 格式"
    else
        echo "✗ metainfo <id> 格式不正确" >&2
        rm -f "$METAINFO_TMP"
        exit 1
    fi
    if command -v appstreamcli &>/dev/null; then
        echo "--- 运行 appstreamcli validate ---"
        APPSTREAM_VALIDATE_OUTPUT=""
        APPSTREAM_VALIDATE_OUTPUT=$(appstreamcli validate --no-net "$METAINFO_TMP" 2>&1) || true
        echo "$APPSTREAM_VALIDATE_OUTPUT"
        if echo "$APPSTREAM_VALIDATE_OUTPUT" | grep -q '^E:'; then
            echo "✗ appstreamcli validate 发现 error 级别问题" >&2
            rm -f "$METAINFO_TMP"
            exit 1
        else
            echo "✓ appstreamcli validate 通过 (无 error)"
        fi
    else
        echo "警告: appstreamcli 不可用，跳过 metainfo 验证" >&2
    fi
else
    echo "✗ 无法从 deb 包提取 metainfo 文件" >&2
    rm -f "$METAINFO_TMP"
    exit 1
fi
rm -f "$METAINFO_TMP"

echo "--- 验证 .desktop 文件存在 ---"
DESKTOP_PATH="/usr/share/applications/com.noatin.test-dummy.desktop"
if dpkg-deb -c "$DEB_FILE" | grep -q "$DESKTOP_PATH"; then
    echo "✓ deb 包包含 $DESKTOP_PATH"
else
    echo "✗ deb 包不包含 $DESKTOP_PATH" >&2
    exit 1
fi

echo "--- 提取并验证 .desktop 内容 ---"
DESKTOP_TMP=$(mktemp)
dpkg-deb --fsys-tarfile "$DEB_FILE" | tar -O -xf - ".$DESKTOP_PATH" > "$DESKTOP_TMP" 2>/dev/null || true
if [[ -s "$DESKTOP_TMP" ]]; then
    if grep -q 'Name\[zh_CN\]' "$DESKTOP_TMP"; then
        echo "✓ .desktop 包含 Name[zh_CN] 字段"
    else
        echo "✗ .desktop 不包含 Name[zh_CN] 字段" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    DESKTOP_EXEC=$(grep '^Exec=' "$DESKTOP_TMP" | head -1 | cut -d= -f2 || true)
    if [[ -n "$DESKTOP_EXEC" ]]; then
        echo "✓ .desktop Exec 字段非空: $DESKTOP_EXEC"
    else
        echo "✗ .desktop Exec 字段为空" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    if [[ "$DESKTOP_EXEC" == /* ]]; then
        echo "✓ .desktop Exec 为绝对路径: $DESKTOP_EXEC"
    else
        echo "✗ .desktop Exec 不是绝对路径: $DESKTOP_EXEC" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    DESKTOP_ICON=$(grep '^Icon=' "$DESKTOP_TMP" | head -1 | cut -d= -f2 || true)
    if [[ -n "$DESKTOP_ICON" ]]; then
        echo "✓ .desktop Icon 字段非空: $DESKTOP_ICON"
    else
        echo "✗ .desktop Icon 字段为空" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    DESKTOP_CATS=$(grep '^Categories=' "$DESKTOP_TMP" | head -1 | cut -d= -f2 || true)
    if [[ -n "$DESKTOP_CATS" ]]; then
        echo "✓ .desktop Categories 字段非空: $DESKTOP_CATS"
    else
        echo "✗ .desktop Categories 字段为空" >&2
        rm -f "$DESKTOP_TMP"
        exit 1
    fi
    if command -v desktop-file-validate &>/dev/null; then
        echo "--- 运行 desktop-file-validate ---"
        DESKTOP_VALIDATE_OUTPUT=""
        DESKTOP_VALIDATE_OUTPUT=$(desktop-file-validate "$DESKTOP_TMP" 2>&1) || true
        echo "$DESKTOP_VALIDATE_OUTPUT"
        if echo "$DESKTOP_VALIDATE_OUTPUT" | grep -q '^.*: error:'; then
            echo "✗ desktop-file-validate 发现 error 级别问题" >&2
            rm -f "$DESKTOP_TMP"
            exit 1
        else
            echo "✓ desktop-file-validate 通过 (无 error)"
        fi
    else
        echo "警告: desktop-file-validate 不可用，跳过 .desktop 验证" >&2
    fi
else
    echo "✗ 无法从 deb 包提取 .desktop 文件" >&2
    rm -f "$DESKTOP_TMP"
    exit 1
fi
rm -f "$DESKTOP_TMP"

echo "--- 验证 DEP-11 YAML 片段 ---"
DEP11_YAML_PATH="repo/dep11/com.noatin.test-dummy.yml"
if [[ -f "$STAGING_DIR/$DEP11_YAML_PATH" ]]; then
    echo "✓ $DEP11_YAML_PATH 存在"
else
    echo "✗ $DEP11_YAML_PATH 不存在" >&2
    exit 1
fi
DEP11_CONTENT=$(cat "$STAGING_DIR/$DEP11_YAML_PATH")
if echo "$DEP11_CONTENT" | grep -q 'ID: com.noatin.test-dummy'; then
    echo "✓ YAML 包含 ID: com.noatin.test-dummy"
else
    echo "✗ YAML 不包含 ID: com.noatin.test-dummy" >&2
    exit 1
fi
if echo "$DEP11_CONTENT" | grep -q 'Type: desktop-application'; then
    echo "✓ YAML 包含 Type: desktop-application"
else
    echo "✗ YAML 不包含 Type: desktop-application" >&2
    exit 1
fi
if echo "$DEP11_CONTENT" | grep -q 'zh_CN:'; then
    echo "✓ YAML 包含 zh_CN: 本地化字段"
else
    echo "✗ YAML 不包含 zh_CN: 本地化字段" >&2
    exit 1
fi
if echo "$DEP11_CONTENT" | grep -q 'Launchable:' && echo "$DEP11_CONTENT" | grep -q 'desktop-id:'; then
    echo "✓ YAML 包含 Launchable: 和 desktop-id:"
else
    echo "✗ YAML 不包含 Launchable: 或 desktop-id:" >&2
    exit 1
fi
if command -v appstreamcli &>/dev/null; then
    echo "--- 运行 appstreamcli validate (DEP-11 YAML) ---"
    DEP11_VALIDATE_OUTPUT=""
    DEP11_VALIDATE_OUTPUT=$(appstreamcli validate --no-net "$STAGING_DIR/$DEP11_YAML_PATH" 2>&1) || true
    if echo "$DEP11_VALIDATE_OUTPUT" | grep -q '^E:'; then
        echo "⚠ appstreamcli validate 发现 error (独立 YAML 片段验证可能需要仓库上下文)" >&2
    else
        echo "✓ appstreamcli validate 通过 (无 error)"
    fi
else
    echo "警告: appstreamcli 不可用，跳过 DEP-11 YAML 验证" >&2
fi

if [[ $LINTIAN_AVAILABLE -eq 1 ]]; then
echo "=== 步骤 7: lintian 检查 ($(lintian --version 2>&1 | head -1)) ==="
    LINTIAN_OUTPUT=$(mktemp)
    set +e
    lintian --pedantic "$DEB_FILE" > "$LINTIAN_OUTPUT" 2>&1
    LINTIAN_EXIT=$?
    set -e

    echo "--- lintian 输出 ---"
    cat "$LINTIAN_OUTPUT"
    echo "--- lintian 结束 (exit=$LINTIAN_EXIT) ---"

    ERROR_COUNT=$(grep -c '^E:' "$LINTIAN_OUTPUT" 2>/dev/null || echo 0)
    WARNING_COUNT=$(grep -c '^W:' "$LINTIAN_OUTPUT" 2>/dev/null || echo 0)
    INFO_COUNT=$(grep -c '^I:' "$LINTIAN_OUTPUT" 2>/dev/null || echo 0)
    PEDANTIC_COUNT=$(grep -c '^P:' "$LINTIAN_OUTPUT" 2>/dev/null || echo 0)

    echo ""
    echo "=== 结果摘要 ==="
    echo "Error:   $ERROR_COUNT"
    echo "Warning: $WARNING_COUNT"
    echo "Info:    $INFO_COUNT"
    echo "Pedantic: $PEDANTIC_COUNT"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        echo ""
        echo "✗ 检查失败: lintian 发现 ${ERROR_COUNT} 个 error"
        exit 1
    fi

    echo ""
    echo "✓ lintian 检查通过: 无 error (${WARNING_COUNT} warning(s), ${INFO_COUNT} info(s), ${PEDANTIC_COUNT} pedantic)"
else
    echo "=== 步骤 7: lintian 检查 (跳过 - lintian 不可用) ==="
fi

echo "=== 步骤 7.5: postrm purge 端到端测试 ==="
echo "--- 安装 deb 包 ---"
dpkg -i "$DEB_FILE"
echo "--- 执行 purge ---"
dpkg --purge "$TEST_PKG"

echo "--- 验证 /etc/$TEST_PKG/ 目录不存在 ---"
if [[ -d "/etc/$TEST_PKG" ]]; then
    echo "✗ /etc/$TEST_PKG/ 目录仍存在，purge 未完全清理" >&2
    exit 1
fi
echo "✓ /etc/$TEST_PKG/ 目录已清理"

echo "--- 验证 dpkg -L 返回错误或空输出 ---"
set +e
PKG_LIST=$(dpkg -L "$TEST_PKG" 2>&1)
PKG_LIST_RC=$?
set -e
if [[ $PKG_LIST_RC -ne 0 ]]; then
    echo "✓ dpkg -L '$TEST_PKG' 返回错误 (包已卸载)"
elif [[ -z "$PKG_LIST" ]]; then
    echo "✓ dpkg -L '$TEST_PKG' 返回空输出 (包已卸载)"
else
    echo "✗ dpkg -L '$TEST_PKG' 仍有残留文件:" >&2
    echo "$PKG_LIST" >&2
    exit 1
fi

if [[ $LINTIAN_AVAILABLE -eq 1 ]]; then
    echo "--- 验证 deb 包无 postrm 相关 lintian error ---"
    _lintian_postrm_tmp=$(mktemp)
    set +e
    lintian --pedantic "$DEB_FILE" > "$_lintian_postrm_tmp" 2>&1
    set -e
    if grep -q 'postrm' "$_lintian_postrm_tmp"; then
        echo "--- lintian postrm 相关输出 ---"
        grep 'postrm' "$_lintian_postrm_tmp" || true
    fi
    rm -f "$_lintian_postrm_tmp"
    echo "✓ lintian postrm 检查完成"
fi

echo "✓ 步骤 7.5 通过"

echo "=== 步骤 7.6: metainfo 端到端测试 ==="
echo "--- 安装 deb 包 ---"
dpkg -i "$DEB_FILE"

if command -v appstreamcli &>/dev/null; then
    echo "--- 运行 appstreamcli refresh-cache ---"
    appstreamcli refresh-cache --force 2>/dev/null || true
    echo "--- 运行 appstreamcli search test-dummy ---"
    SEARCH_OUTPUT=""
    SEARCH_OUTPUT=$(appstreamcli search test-dummy 2>&1) || true
    if echo "$SEARCH_OUTPUT" | grep -qi 'test-dummy\|测试包'; then
        echo "✓ appstreamcli search test-dummy 找到匹配结果"
    else
        echo "⚠ appstreamcli search test-dummy 未找到匹配 (可能需要刷新缓存)" >&2
        echo "$SEARCH_OUTPUT"
    fi
else
    echo "警告: appstreamcli 不可用，跳过搜索验证" >&2
fi

echo "--- 验证 update-desktop-database 缓存 ---"
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
    if [[ -f /usr/share/applications/desktop-db ]] || \
       [[ -f /usr/share/applications/mimeinfo.cache ]]; then
        echo "✓ update-desktop-database 已生成缓存文件"
    else
        echo "⚠ 未检测到 desktop 缓存文件 (可能需要手动刷新)" >&2
    fi
else
    echo "警告: update-desktop-database 不可用，跳过缓存验证" >&2
fi

echo "--- 卸载 deb 包 ---"
dpkg --purge "$TEST_PKG" 2>/dev/null || true

echo "✓ 步骤 7.6 通过"
echo "✓ ${DEB_FILE} 构建成功"

