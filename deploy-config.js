module.exports = {
  deployConfigs: {
    /**
     * 部署脚本存储 有关已创建 故障恢复 合同的元数据的目录
     */
    checkpointDir: "./build",
    /**
     * 部署日志将以纯文本格式存储的目录
     */
    deployLogsDir: "./logs",
    /**
     * 所有已部署合约的 地址 和 名称将以 json 格式存储的目录
     */
    deployedContractsDir: "./build/deployed",
  },
};
