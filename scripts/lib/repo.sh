#!/usr/bin/env bash
# 供仓库脚本共享的根目录定位；函数使用本文件位置，不依赖调用方当前目录。

ubaa_repo_root() (
  cd "$(dirname "${BASH_SOURCE[0]}")/../.."
  pwd
)
