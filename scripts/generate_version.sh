#!/bin/bash
# 版本号生成脚本
# 规则：有 git tag 用 tag，否则用 UTC+8 构建日期时间生成，标记时区

set -e

# 获取最近的 tag（排除 build 日期类型的 tag）
TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)

BUILD_TYPE=""
VERSION_NAME=""
VERSION_NUMBER=""
BUILD_TAG=""
BUILD_DATETIME=""
BUILD_TIMEZONE=""

if [ -n "$TAG" ]; then
    # 有 tag，使用 tag 作为版本号（去掉 v 前缀）
    VERSION_NAME="${TAG#v}"
    VERSION_NUMBER="1"
    BUILD_TYPE="tag"
    BUILD_TAG="$TAG"
else
    # 无 tag，使用 UTC+8 构建日期时间生成版本号
    # 格式: 0.0.0-YYYYMMDD.HHMMSS+08
    BUILD_DATETIME=$(TZ='Asia/Shanghai' date '+%Y%m%d.%H%M%S')
    VERSION_NAME="0.0.0-${BUILD_DATETIME}+08"
    # 用时间戳作为 build number
    VERSION_NUMBER=$(TZ='Asia/Shanghai' date '+%Y%m%d%H%M%S')
    BUILD_TYPE="datetime"
    BUILD_TIMEZONE="UTC+8"
fi

# 安全输出（避免空值和多行问题）
echo "VERSION_NAME=${VERSION_NAME}"
echo "VERSION_NUMBER=${VERSION_NUMBER}"
echo "BUILD_TYPE=${BUILD_TYPE}"
echo "BUILD_TAG=${BUILD_TAG}"
echo "BUILD_DATETIME=${BUILD_DATETIME}"
echo "BUILD_TIMEZONE=${BUILD_TIMEZONE}"
