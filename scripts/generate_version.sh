#!/bin/bash
# 版本号生成脚本
# 规则：有 git tag 用 tag + build number，否则用 UTC+8 构建日期时间生成

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
    # 有 tag，使用 tag 作为基础版本号
    BASE_VERSION="${TAG#v}"
    
    # 计算自 tag 之后的 commit 数量作为 build number
    COMMIT_COUNT=$(git rev-list "${TAG}..HEAD" --count 2>/dev/null || echo "0")
    
    # 获取短 commit hash
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    if [ "$COMMIT_COUNT" -gt 0 ]; then
        # tag 之后有新提交，追加 build number
        VERSION_NAME="${BASE_VERSION}-${COMMIT_COUNT}"
        VERSION_NUMBER="$COMMIT_COUNT"
    else
        # 正好在 tag 上
        VERSION_NAME="${BASE_VERSION}"
        VERSION_NUMBER="1"
    fi
    
    BUILD_TYPE="tag"
    BUILD_TAG="$TAG"
else
    # 无 tag，使用 UTC+8 构建日期时间生成版本号
    # 格式: 0.0.0-YYYYMMDD.HHMMSS
    BUILD_DATETIME=$(TZ='Asia/Shanghai' date '+%Y%m%d.%H%M%S')
    VERSION_NAME="0.0.0-${BUILD_DATETIME}"
    # 用时间戳作为 build number（取后 9 位，确保不超过 Android 限制 2100000000）
    TIMESTAMP=$(TZ='Asia/Shanghai' date '+%Y%m%d%H%M%S')
    VERSION_NUMBER=$(echo "$TIMESTAMP" | sed 's/^.*\(.\{9\}\)$/\1/')
    # 确保不超过 2100000000
    if [ "$VERSION_NUMBER" -gt 2100000000 ]; then
        VERSION_NUMBER=$((VERSION_NUMBER % 2100000000))
    fi
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
