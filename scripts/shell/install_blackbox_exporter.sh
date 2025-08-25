#!/bin/bash

# Blackbox Exporter 安装和服务配置脚本
set -e

# 配置参数
CONFIG_DIR="/data/prometheus/blackbox-exporter/config"
CONFIG_FILE="${CONFIG_DIR}/blackbox.yml"
SERVICE_FILE="/etc/systemd/system/blackbox-exporter.service"
DOCKER_IMAGE="quay.io/prometheus/blackbox-exporter:latest"
CONTAINER_NAME="blackbox_exporter"
PORT="9115"

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装，请先安装 Docker"
    exit 1
fi

# 创建配置目录
echo "创建配置目录..."
sudo mkdir -p "${CONFIG_DIR}"

# 检查配置文件是否存在，如果不存在则创建
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "创建配置文件..."
    sudo tee "${CONFIG_FILE}" > /dev/null << 'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: [200]
      method: GET
      
  http_post_2xx:
    prober: http
    timeout: 5s
    http:
      method: POST
      headers:
        Content-Type: application/json
      body: '{}'
      
  tcp_connect:
    prober: tcp
    timeout: 5s
    
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
EOF
    echo "配置文件已创建: ${CONFIG_FILE}"
else
    echo "配置文件已存在: ${CONFIG_FILE}"
fi

# 检查 Docker 镜像是否存在
echo "检查 Docker 镜像..."
if ! sudo docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${DOCKER_IMAGE}$"; then
    echo "拉取 Docker 镜像..."
    sudo docker pull "${DOCKER_IMAGE}"
else
    echo "Docker 镜像已存在: ${DOCKER_IMAGE}"
fi

# 检查容器是否已运行
if sudo docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "容器已存在: ${CONTAINER_NAME}"
    echo "停止并删除现有容器..."
    sudo docker stop "${CONTAINER_NAME}" || true
    sudo docker rm "${CONTAINER_NAME}" || true
fi

# 创建 systemd 服务文件
echo "创建 systemd 服务文件..."
sudo tee "${SERVICE_FILE}" > /dev/null << EOF
[Unit]
Description=Blackbox Exporter
Documentation=https://github.com/prometheus/blackbox_exporter
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker stop ${CONTAINER_NAME}
ExecStartPre=-/usr/bin/docker rm ${CONTAINER_NAME}
ExecStart=/usr/bin/docker run \\
  --name ${CONTAINER_NAME} \\
  -p ${PORT}:9115 \\
  -v ${CONFIG_DIR}:/config \\
  ${DOCKER_IMAGE} \\
  --config.file=/config/blackbox.yml

ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
echo "重新加载 systemd 配置..."
sudo systemctl daemon-reload

# 启用并启动服务
echo "启动 Blackbox Exporter 服务..."
sudo systemctl enable blackbox-exporter
sudo systemctl start blackbox-exporter

# 检查服务状态
echo "检查服务状态..."
sleep 3
sudo systemctl status blackbox-exporter --no-pager

# 验证服务是否正常运行
echo "验证服务..."
if curl -s http://localhost:${PORT}/metrics > /dev/null; then
    echo "✅ Blackbox Exporter 安装成功！"
    echo "访问地址: http://localhost:${PORT}"
    echo "配置文件: ${CONFIG_FILE}"
    echo "管理命令: sudo systemctl {start|stop|restart|status} blackbox-exporter"
else
    echo "❌ 服务启动失败，请检查日志: sudo journalctl -u blackbox-exporter -f"
    exit 1
fi