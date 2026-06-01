# Noatin SoftDeb CI

noatin-softdeb 的构建引擎仓库，包含构建脚本、模板、构建配置和 CI workflows。该仓库以 `ci/` 子目录形式存在于内网 Gitea 主仓库内，独立 git 托管于 GitHub。

## 目录结构

```
ci/
├── .github/workflows/build-deb.yml      # GitHub Actions CI 流水线
├── debian/
│   ├── scripts/
│   │   ├── build-package.sh             # 单包构建脚本
│   │   ├── ci-build.sh                  # CI 编排脚本（变更检测、构建、签名、推送）
│   │   └── tests/
│   │       └── test-ci-build.sh         # CI 构建测试
│   ├── templates/                       # deb 包模板和生成器
│   │   ├── DEBIAN/                      # control/postinst/postrm 模板
│   │   ├── dep11/                       # DEP-11 元数据模板
│   │   ├── desktop/                     # .desktop 文件模板
│   │   ├── metainfo/                    # AppStream metainfo 模板
│   │   ├── gen-control.sh              # control 文件生成器
│   │   ├── gen-postinst.sh             # postinst 生成器
│   │   ├── gen-postrm.sh               # postrm 生成器
│   │   ├── gen-desktop.sh              # .desktop 文件生成器
│   │   ├── gen-metainfo.sh             # metainfo 生成器
│   │   └── gen-dep11.sh                # DEP-11 YAML 生成器
│   └── packages/
│       └── <package-name>/
│           └── build.conf               # 构建配置（每个包一个）
└── README.md
```

## 如何新增一个包

1. 在 `debian/packages/` 下创建新目录 `debian/packages/<new-pkg>/`
2. 创建 `build.conf`，填入必填字段：

```ini
name=<name>
upstream_version=<version>
debian_revision=<revision>
description=<short description>
long_desc=<long description>
zh_name=<中文名>
zh_summary=<中文简介>
zh_desc=<中文描述>
developer_name=<开发者名>
project_license=<license>
exec=<可执行文件路径>
icon=<图标路径>
icon_url=<图标下载 URL>
```

3. 可选字段：

```ini
fetch_type=npm              # 源码获取方式（local/npm，默认 local）
fetch_source=<npm-package>  # npm 包名（fetch_type=npm 时必填）
depends=<依赖>              # Debian 依赖列表
homepage=<主页>             # 项目主页
screenshot_url=<截图 URL>   # 截图
zh_keywords=<中文关键词>     # 分号分隔
has_desktop=no              # 是否生成 desktop 相关触发（默认 yes）
```

## CI 触发流程

1. push 到 GitHub `main` 分支，且 `debian/packages/**` 路径有变更
2. GitHub Actions 检出代码
3. `ci-build.sh` 检测变更的包，依次执行：
   - 调用 `build-package.sh` 构建 deb
   - GPG 签名
   - clone noatin-repo，提交构建产物
   - 推送到 Gitee，触发 sync-mirrors 同步至 GitHub / GitCode
   - VPS DEP-11 上传 + 索引更新回调

## 安全边界

本仓库是公开仓库，不包含任何秘密。所有敏感信息（GPG 密钥、API Token）通过 GitHub Secrets 注入。