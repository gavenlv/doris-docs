// build-tools/nexus-init.groovy
// Nexus 3.x 初始化脚本 - 首次启动自动创建 Docker 仓库
// 放置到: nexus-data/etc/db/initialization/nexus.groovy
//
// 访问 Nexus API: http://localhost:8081

import org.sonatype.nexus.repository.storage.StorageFacet
import org.sonatype.nexus.repository.manager.RepositoryManager
import org.sonatype.nexus.security.SeedData
import org.sonatype.nexus.securitypassword.PasswordService

log.info("===========================================")
log.info(" Nexus 初始化脚本开始执行")
log.info("===========================================")

// 等待安全初始化完成
def passwordService = container.lookup(PasswordService.class)
if (passwordService == null) {
    log.warn("PasswordService 未就绪，跳过初始化")
    return
}

// 创建 Docker Hosted 仓库 (存储我们构建的镜像)
def dockerHostedConfig = [
    name: 'doris-docker-hosted',
    type: 'hosted',
    format: 'docker',
    online: true,
    storage: [
        blobStoreName: 'default',
        strictContentTypeValidation: false
    ],
    docker: [
        httpPort: 5000,
        v1Enabled: false,
        forceBasicAuth: true,
        allowAnonymousPull: false
    ],
    cleanup: [
        policyNames: ['docker-weekly-cleanup']
    ]
]

// 创建 Docker Proxy 仓库 (代理 Docker Hub，用于加速)
def dockerProxyConfig = [
    name: 'doris-docker',
    type: 'proxy',
    format: 'docker',
    online: true,
    storage: [
        blobStoreName: 'default',
        strictContentTypeValidation: false
    ],
    proxy: [
        remoteUrl: 'https://registry-1.docker.io',
        cleanupPolicyNames: []
    ],
    docker: [
        httpPort: 5002,
        v1Enabled: false,
        forceBasicAuth: false,
        allowAnonymousPull: true
    ],
    negativeCache: [
        enabled: true,
        ttl: 1440
    ]
]

// 应用配置
try {
    def repoManager = container.lookup(RepositoryManager.class)

    // 创建 hosted 仓库
    if (!repoManager.exists('doris-docker-hosted')) {
        repoManager.create(dockerHostedConfig)
        log.info("创建 Docker hosted 仓库: doris-docker-hosted")
    } else {
        log.info("Docker hosted 仓库已存在")
    }

    // 创建 proxy 仓库
    if (!repoManager.exists('doris-docker')) {
        repoManager.create(dockerProxyConfig)
        log.info("创建 Docker proxy 仓库: doris-docker")
    } else {
        log.info("Docker proxy 仓库已存在")
    }

    log.info("===========================================")
    log.info(" Nexus 仓库初始化完成")
    log.info("===========================================")
} catch (Exception e) {
    log.error("初始化失败: " + e.message)
    throw e
}