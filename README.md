# Ubuntu 酒馆一键安装脚本

这是 Ubuntu 版 SillyTavern（酒馆）安装脚本。

Windows 版 `install.bat` 保持不变。Ubuntu 版不安装 Bun，按官方 Linux 启动方式使用 Node.js/npm。

菜单署名：凌宇和苏苏子制作OVO。

## 直接复制这一行

打开 Ubuntu 终端，复制下面这一行运行，会进入中文菜单：

```bash
curl -fsSL https://raw.githubusercontent.com/qsly17-ai/sillytavern-ubuntu-installer/main/install_ubuntu.sh | bash
```

如果你不想看菜单，想直接完整安装，复制这一行：

```bash
curl -fsSL https://raw.githubusercontent.com/qsly17-ai/sillytavern-ubuntu-installer/main/install_ubuntu.sh | bash -s -- --one-click
```

想换安装目录时，用这一行：

```bash
curl -fsSL https://raw.githubusercontent.com/qsly17-ai/sillytavern-ubuntu-installer/main/install_ubuntu.sh | SILLYTAVERN_DIR="$HOME/apps/SillyTavern" bash -s -- --one-click
```

## 本地测试命令

如果已经把脚本下载到本地，可以运行：

```bash
bash install_ubuntu.sh
```

本地直接完整安装：

```bash
bash install_ubuntu.sh --one-click
```

## 菜单功能

- 安装基础环境：`git`、`curl`、`ca-certificates`
- 安装或检查 Node.js：低于 Node.js 20 时，通过 NodeSource 安装 Node.js 22.x
- 下载 SillyTavern 项目：默认下载官方 `release` 分支到 `$HOME/SillyTavern`
- 安装项目依赖：使用官方 `start.sh` 同款 npm 参数
- 启动 SillyTavern：前台运行 `bash ./start.sh`
- 更新 SillyTavern：执行 `git pull --ff-only` 后刷新 npm 依赖
- 一键安装：按顺序完成依赖、Node.js、克隆和 npm 依赖安装

## 环境变量

```bash
SILLYTAVERN_DIR=/path/to/SillyTavern
SILLYTAVERN_BRANCH=release
SILLYTAVERN_REPO_URL=https://github.com/SillyTavern/SillyTavern.git
```

## 注意事项

- 目标系统是 Ubuntu，不是通用 Debian。
- 普通用户运行时需要 `sudo` 权限。
- 如果目标目录已经存在，脚本会询问是否删除后重新克隆。
- 启动后在浏览器访问 `http://127.0.0.1:8000`。
