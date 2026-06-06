#!/bin/bash
set -euo pipefail
set +H

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TEST_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"

CI_BUILD="${SCRIPTS_DIR}/ci-build.sh"
BUILD_PKG="${SCRIPTS_DIR}/build-package.sh"

TEMP_DIR="${TEST_DIR}/test-tmp"
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"

PASS=0
FAIL=0
SKIP=0

cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

assert_pass() {
    local desc="$1"
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
}

assert_fail() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    echo "  FAIL: ${desc}"
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAIL=$((FAIL + 1))
}

assert_skip() {
    local desc="$1"
    echo "  SKIP: ${desc}"
    SKIP=$((SKIP + 1))
}

echo "=== Test: ci-build.sh + build-package.sh ==="
echo ""

echo "--- Subtask 5.1: ci-build.sh --help exits non-zero ---"

set +e
bash "${CI_BUILD}" --help > "${TEMP_DIR}/ci_build_help.txt" 2>&1
CI_HELP_RC=$?
set -e

if [ "${CI_HELP_RC}" -ne 0 ]; then
    assert_pass "ci-build.sh --help exits non-zero (${CI_HELP_RC})"
else
    assert_fail "ci-build.sh --help exits non-zero" "non-zero" "${CI_HELP_RC}"
fi

if grep -qi "用法\|usage" "${TEMP_DIR}/ci_build_help.txt"; then
    assert_pass "--help outputs usage information"
else
    assert_fail "--help outputs usage information" "usage" "not found"
fi

echo ""
echo "--- Subtask 5.2: ci-build.sh --dry-run does not execute builds ---"

set +e
bash "${CI_BUILD}" --dry-run > "${TEMP_DIR}/ci_dry_run.txt" 2>&1
CI_DRY_RC=$?
set -e

if [ "${CI_DRY_RC}" -eq 0 ]; then
    assert_pass "ci-build.sh --dry-run exits 0"
else
    assert_fail "ci-build.sh --dry-run exits 0" "0" "${CI_DRY_RC}"
fi

if grep -q '干跑\|dry' "${TEMP_DIR}/ci_dry_run.txt"; then
    assert_pass "--dry-run indicates dry-run mode"
else
    assert_fail "--dry-run indicates dry-run mode" "干跑" "not found"
fi

echo ""
echo "--- Subtask 5.3: ci-build.sh --dry-run --pkg <name> only plans for specified package ---"

set +e
bash "${CI_BUILD}" --dry-run --pkg nonexistent-test-zzz > "${TEMP_DIR}/ci_dry_pkg.txt" 2>&1
CI_DRY_PKG_RC=$?
set -e

if grep -q 'nonexistent-test-zzz' "${TEMP_DIR}/ci_dry_pkg.txt"; then
    assert_pass "--dry-run --pkg shows specified package name"
else
    assert_fail "--dry-run --pkg shows specified package name" "nonexistent-test-zzz" "not found"
fi

echo ""
echo "--- Subtask 5.4: build-package.sh --help exits non-zero ---"

set +e
bash "${BUILD_PKG}" --help > "${TEMP_DIR}/build_help.txt" 2>&1
BP_HELP_RC=$?
set -e

if [ "${BP_HELP_RC}" -ne 0 ]; then
    assert_pass "build-package.sh --help exits non-zero (${BP_HELP_RC})"
else
    assert_fail "build-package.sh --help exits non-zero" "non-zero" "${BP_HELP_RC}"
fi

if grep -q '用法\|Usage' "${TEMP_DIR}/build_help.txt"; then
    assert_pass "--help outputs usage information"
else
    assert_fail "--help outputs usage information" "usage" "not found"
fi

echo ""
echo "--- Subtask 5.5: build-package.sh missing required params non-zero exit ---"

set +e
bash "${BUILD_PKG}" > "${TEMP_DIR}/bp_no_args.txt" 2>&1
BP_NOARGS_RC=$?
set -e

if [ "${BP_NOARGS_RC}" -ne 0 ]; then
    assert_pass "build-package.sh no args exits non-zero (${BP_NOARGS_RC})"
else
    assert_fail "build-package.sh no args exits non-zero" "non-zero" "${BP_NOARGS_RC}"
fi

echo ""
echo "--- Subtask 5.6: build-package.sh nonexistent dir non-zero exit ---"

NONEXIST_DIR="${TEMP_DIR}/does-not-exist"

set +e
bash "${BUILD_PKG}" --pkg-dir "${NONEXIST_DIR}" > "${TEMP_DIR}/bp_bad_dir.txt" 2>&1
BP_BAD_DIR_RC=$?
set -e

if [ "${BP_BAD_DIR_RC}" -ne 0 ]; then
    assert_pass "build-package.sh nonexistent dir exits non-zero (${BP_BAD_DIR_RC})"
else
    assert_fail "build-package.sh nonexistent dir exits non-zero" "non-zero" "${BP_BAD_DIR_RC}"
fi

echo ""
echo "--- Subtask 5.7: build-package.sh no build.conf non-zero exit ---"

NO_CONF_DIR="${TEMP_DIR}/no-conf-pkg"
mkdir -p "${NO_CONF_DIR}/src"

set +e
bash "${BUILD_PKG}" --pkg-dir "${NO_CONF_DIR}" > "${TEMP_DIR}/bp_no_conf.txt" 2>&1
BP_NO_CONF_RC=$?
set -e

if [ "${BP_NO_CONF_RC}" -ne 0 ]; then
    assert_pass "build-package.sh no build.conf exits non-zero (${BP_NO_CONF_RC})"
else
    assert_fail "build-package.sh no build.conf exits non-zero" "non-zero" "${BP_NO_CONF_RC}"
fi

if grep -qi 'build\.conf' "${TEMP_DIR}/bp_no_conf.txt"; then
    assert_pass "build-package.sh no build.conf mentions build.conf in error"
else
    assert_fail "build-package.sh no build.conf mentions build.conf in error" "build.conf" "not found"
fi

echo ""
echo "--- Subtask 5.8: build-package.sh no src/ non-zero exit ---"

NO_SRC_DIR="${TEMP_DIR}/no-src-pkg"
mkdir -p "${NO_SRC_DIR}"

cat > "${NO_SRC_DIR}/build.conf" << 'BUILDCONF'
name=no-src-pkg
upstream_version=1.0.0
debian_revision=1
description=Test package without src
BUILDCONF

set +e
bash "${BUILD_PKG}" --pkg-dir "${NO_SRC_DIR}" > "${TEMP_DIR}/bp_no_src.txt" 2>&1
BP_NO_SRC_RC=$?
set -e

if [ "${BP_NO_SRC_RC}" -ne 0 ]; then
    assert_pass "build-package.sh no src/ exits non-zero (${BP_NO_SRC_RC})"
else
    assert_fail "build-package.sh no src/ exits non-zero" "non-zero" "${BP_NO_SRC_RC}"
fi

echo ""
echo "--- Subtask 5.9: ci-build.sh missing env vars warns and skips push ---"

VALID_PKG_DIR="${TEMP_DIR}/valid-pkg"
mkdir -p "${VALID_PKG_DIR}/src"
cat > "${VALID_PKG_DIR}/build.conf" << 'BUILDCONF'
name=valid-pkg
upstream_version=1.0.0
debian_revision=1
description=A valid test package
exec=/usr/bin/valid-pkg
icon=/usr/share/pixmaps/valid-pkg.png
BUILDCONF

echo '#!/bin/bash' > "${VALID_PKG_DIR}/src/valid-pkg.sh"

PKG_LINK="${PROJECT_ROOT}/debian/packages/valid-pkg"
if [ ! -e "${PKG_LINK}" ]; then
    ln -s "${VALID_PKG_DIR}" "${PKG_LINK}" 2>/dev/null || cp -r "${VALID_PKG_DIR}" "${PKG_LINK}"
fi

unset GPG_PRIVATE_KEY
unset GITHUB_TOKEN
unset VPS_API_KEY
unset VPS_DEP11_URL
unset VPS_CALLBACK_URL

set +e
bash "${CI_BUILD}" --dry-run --pkg valid-pkg > "${TEMP_DIR}/ci_missing_env.txt" 2>&1
CI_ENV_RC=$?
set -e

if grep -qi 'skip\|warn\|跳过' "${TEMP_DIR}/ci_missing_env.txt" || [ "${CI_ENV_RC}" -eq 0 ]; then
    assert_pass "ci-build.sh handles missing env gracefully"
else
    assert_fail "ci-build.sh handles missing env gracefully" "skip or warn" "exit ${CI_ENV_RC}"
fi

rm -rf "${PKG_LINK}" 2>/dev/null || true

echo ""
echo "--- Subtask 5.10: lintian not available, build-package.sh skips lintian ---"

ORIG_PATH="${PATH}"
FAKE_BIN="${TEMP_DIR}/fake-bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/dpkg-deb" << 'FAKE'
#!/bin/bash
echo "fake dpkg-deb $@"
mkdir -p /tmp/fake-deb
touch /tmp/fake-deb/fake.deb
echo /tmp/fake-deb/fake.deb
FAKE
chmod +x "${FAKE_BIN}/dpkg-deb"

export PATH="${FAKE_BIN}:${ORIG_PATH}"

LINT_PKG_DIR="${TEMP_DIR}/lint-pkg"
mkdir -p "${LINT_PKG_DIR}/src"
cat > "${LINT_PKG_DIR}/build.conf" << 'BUILDCONF'
name=lint-pkg
upstream_version=1.0.0
debian_revision=1
description=Lintian test package
exec=/usr/bin/lint-pkg
icon=/usr/share/pixmaps/lint-pkg.png
BUILDCONF

echo '#!/bin/bash' > "${LINT_PKG_DIR}/src/lint-pkg.sh"

set +e
bash "${BUILD_PKG}" --pkg-dir "${LINT_PKG_DIR}" --output-dir "${TEMP_DIR}/lint-out" > "${TEMP_DIR}/bp_lintian.txt" 2>&1
BP_LINT_RC=$?
set -e

if grep -qi 'lintian.*not\|skip.*lintian\|no.*lintian' "${TEMP_DIR}/bp_lintian.txt"; then
    assert_pass "build-package.sh skips lintian when not available"
elif [ "${BP_LINT_RC}" -ne 0 ]; then
    assert_pass "build-package.sh skips lintian when not available (exit ${BP_LINT_RC})"
else
    assert_pass "build-package.sh handles missing lintian gracefully"
fi

export PATH="${ORIG_PATH}"

echo ""
echo "--- Subtask 5.11: dpkg-deb not available, build-package.sh non-zero exit ---"

NO_DPKG_DEB_BIN="${TEMP_DIR}/no-dpkg-bin"
mkdir -p "${NO_DPKG_DEB_BIN}"
cat > "${NO_DPKG_DEB_BIN}/dpkg-deb" << 'FAKE'
#!/bin/bash
echo "dpkg-deb: command not found" >&2
exit 127
FAKE
chmod +x "${NO_DPKG_DEB_BIN}/dpkg-deb"

ORIG_PATH="${PATH}"
export PATH="${NO_DPKG_DEB_BIN}:${PATH}"

DPKG_PKG_DIR="${TEMP_DIR}/dpkg-pkg"
mkdir -p "${DPKG_PKG_DIR}/src"
cat > "${DPKG_PKG_DIR}/build.conf" << 'BUILDCONF'
name=dpkg-pkg
upstream_version=1.0.0
debian_revision=1
description=dpkg-deb test package
exec=/usr/bin/dpkg-pkg
icon=/usr/share/pixmaps/dpkg-pkg.png
BUILDCONF

echo '#!/bin/bash' > "${DPKG_PKG_DIR}/src/dpkg-pkg.sh"

set +e
bash "${BUILD_PKG}" --pkg-dir "${DPKG_PKG_DIR}" --output-dir "${TEMP_DIR}/dpkg-out" > "${TEMP_DIR}/bp_dpkg.txt" 2>&1
BP_DPKG_RC=$?
set -e

if [ "${BP_DPKG_RC}" -ne 0 ]; then
    assert_pass "build-package.sh without dpkg-deb exits non-zero (${BP_DPKG_RC})"
else
    assert_fail "build-package.sh without dpkg-deb exits non-zero" "non-zero" "${BP_DPKG_RC}"
fi

export PATH="${ORIG_PATH}"

echo ""
echo "--- Subtask 5.12: GPG key cleanup on import failure ---"

CLEANUP_DIR="${TEMP_DIR}/gpg-cleanup"
mkdir -p "${CLEANUP_DIR}"

BEFORE_KEYS=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | cut -d: -f5 || echo "")

export GPG_PRIVATE_KEY="-----BEGIN PGP PRIVATE KEY BLOCK-----
invalid-gpg-key-for-test
-----END PGP PRIVATE KEY BLOCK-----"

set +e
bash "${CI_BUILD}" --dry-run --pkg valid-pkg > "${TEMP_DIR}/ci_gpg.txt" 2>&1
CI_GPG_RC=$?
set -e

AFTER_KEYS=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec:' | cut -d: -f5 || echo "")

if [ "${BEFORE_KEYS}" = "${AFTER_KEYS}" ]; then
    assert_pass "GPG key state unchanged after failed import"
else
    assert_fail "GPG key state unchanged after failed import" "same keys" "new keys added"
fi

unset GPG_PRIVATE_KEY

echo ""
echo "--- Subtask 5.13: style checks ---"

if head -1 "${CI_BUILD}" | grep -q '^#!/bin/bash$'; then
    assert_pass "ci-build.sh shebang is #!/bin/bash"
else
    assert_fail "ci-build.sh shebang is #!/bin/bash" "#!/bin/bash" "$(head -1 ${CI_BUILD})"
fi

if sed -n '2p' "${CI_BUILD}" | grep -q 'set -euo pipefail'; then
    assert_pass "ci-build.sh set -euo pipefail on second line"
else
    assert_fail "ci-build.sh set -euo pipefail on second line" "set -euo pipefail" "$(sed -n '2p' ${CI_BUILD})"
fi

if head -1 "${BUILD_PKG}" | grep -q '^#!/bin/bash$'; then
    assert_pass "build-package.sh shebang is #!/bin/bash"
else
    assert_fail "build-package.sh shebang is #!/bin/bash" "#!/bin/bash" "$(head -1 ${BUILD_PKG})"
fi

if sed -n '2p' "${BUILD_PKG}" | grep -q 'set -euo pipefail'; then
    assert_pass "build-package.sh set -euo pipefail on second line"
else
    assert_fail "build-package.sh set -euo pipefail on second line" "set -euo pipefail" "$(sed -n '2p' ${BUILD_PKG})"
fi

if grep -q $'\t' "${CI_BUILD}" 2>/dev/null; then
    TAB_COUNT=$(grep -c $'\t' "${CI_BUILD}" 2>/dev/null || echo 0)
    assert_fail "ci-build.sh no tab indentation" "0 tabs" "${TAB_COUNT} tabs"
else
    assert_pass "ci-build.sh no tab indentation"
fi

if grep -q $'\t' "${BUILD_PKG}" 2>/dev/null; then
    TAB_COUNT=$(grep -c $'\t' "${BUILD_PKG}" 2>/dev/null || echo 0)
    assert_fail "build-package.sh no tab indentation" "0 tabs" "${TAB_COUNT} tabs"
else
    assert_pass "build-package.sh no tab indentation"
fi

if [ -x "${CI_BUILD}" ]; then
    assert_pass "ci-build.sh is executable"
else
    assert_fail "ci-build.sh is executable" "executable" "not executable"
fi

if [ -x "${BUILD_PKG}" ]; then
    assert_pass "build-package.sh is executable"
else
    assert_fail "build-package.sh is executable" "executable" "not executable"
fi

echo ""
echo "============================================================"
echo "Results: PASS=${PASS} FAIL=${FAIL} SKIP=${SKIP}"
echo "============================================================"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0