#!/bin/bash
# 版本号生成脚本
# 规则：有 git tag 用 tag + 构建时间戳，否则用构建时间戳
# 版本号中不含 + 号（Android 不允许），用 CST 表示东八区

set -e

# 获取最近的 tag（排除 build 日期类型的 tag）
TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)

BUILD_TYPE=""
VERSION_NAME=""
VERSION_NUMBER=""
BUILD_TAG=""
BUILD_DATETIME=""
BUILD_TIMEZONE="CST"

# 东八区构建时间
BUILD_DATETIME=$(TZ='Asia/Shanghai' date '+%Y%m%d.%H%M%S')

if [ -n "$TAG" ]; then
    # 有 tag，使用 tag + 构建时间戳
    BASE_VERSION="${TAG#v}"
    
    # 判断是否正好在 tag 上
    COMMIT_COUNT=$(git rev-list "${TAG}..HEAD" --count 2>/dev/null || echo "0")
    
    if [ "$COMMIT_COUNT" -gt 0 ]; then
        # tag 之后有新提交：1.1.0-20260609.143000CST
        VERSION_NAME="${BASE_VERSION}-${BUILD_DATETIME}CST"
    else
        # 正好在 tag 上：1.1.0
        VERSION_NAME="${BASE_VERSION}"
    fi
    
    VERSION_NUMBER="1"
    BUILD_TYPE="tag"
    BUILD_TAG="$TAG"
else
    # 无 tag：0.0.0-20260609.143000CST
    VERSION_NAME="0.0.0-${BUILD_DATETIME}CST"
    
    # 用时间戳作为 build number（取后 9 位，确保不超过 Android 限制 2100000000）
    TIMESTAMP=$(TZ='Asia/Shanghai' date '+%Y%m%d%H%M%S')
    VERSION_NUMBER=$(echo "$TIMESTAMP" | sed 's/^.*\(.\{9\}\)$/\1/')
    if [ "$VERSION_NUMBER" -gt 2100000000 ]; then
        VERSION_NUMBER=$((VERSION_NUMBER % 2100000000))
    fi
    
    BUILD_TYPE="datetime"
fi

# 安全输出（避免空值和多行问题）
echo "VERSION_NAME=${VERSION_NAME}"
echo "VERSION_NUMBER=${VERSION_NUMBER}"
echo "BUILD_TYPE=${BUILD_TYPE}"
echo "BUILD_TAG=${BUILD_TAG}"
echo "BUILD_DATETIME=${BUILD_DATETIME}"
echo "BUILD_TIMEZONE=${BUILD_TIMEZONE}"
