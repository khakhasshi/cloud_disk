#!/bin/bash
# Ubuntu服务器部署脚本（跳过sudo验证版本）
# 使用方法: chmod +x deploy_no_sudo_check.sh && ./deploy_no_sudo_check.sh

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="webstore"
PROJECT_DIR="/opt/${PROJECT_NAME}"
SERVICE_USER="${PROJECT_NAME}"
SERVICE_PORT=9001
PYTHON_VERSION="3.9"  # 可以根据需要修改

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}    WEBstore 文件共享服务部署脚本     ${NC}"
echo -e "${BLUE}    (跳过sudo验证版本)              ${NC}"
echo -e "${BLUE}======================================${NC}"

# 检查是否为root用户
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}请不要使用root用户直接运行此脚本${NC}"
    echo -e "${YELLOW}建议使用具有sudo权限的普通用户运行${NC}"
    exit 1
fi

# 跳过sudo权限检查，直接进入部署流程
echo -e "${YELLOW}跳过sudo权限检查，直接开始部署...${NC}"
echo -e "${RED}注意：如果后续步骤需要sudo权限，系统会提示输入密码${NC}"

# 函数：打印状态信息
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 函数：等待用户确认
wait_for_confirmation() {
    while true; do
        read -p "是否继续? (y/n): " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "部署已取消"; exit 0;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

print_status "开始部署 WEBstore 文件共享服务..."

# 1. 更新系统包
print_status "更新系统包..."
sudo apt update
sudo apt upgrade -y

# 2. 安装基本依赖
print_status "安装系统依赖..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    nginx \
    supervisor \
    ufw \
    git \
    curl \
    wget \
    unzip \
    logrotate

# 3. 创建项目用户
print_status "创建系统用户 ${SERVICE_USER}..."
if ! id "${SERVICE_USER}" &>/dev/null; then
    sudo useradd -r -s /bin/false -d "${PROJECT_DIR}" "${SERVICE_USER}"
    print_status "用户 ${SERVICE_USER} 创建成功"
else
    print_warning "用户 ${SERVICE_USER} 已存在"
fi

# 4. 创建项目目录
print_status "创建项目目录..."
sudo mkdir -p "${PROJECT_DIR}"
sudo mkdir -p "${PROJECT_DIR}/shared_files"
sudo mkdir -p "/var/log/${PROJECT_NAME}"

# 5. 复制项目文件
print_status "复制项目文件..."
sudo cp -r "$(pwd)"/* "${PROJECT_DIR}/"
sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "${PROJECT_DIR}"
sudo chmod 755 "${PROJECT_DIR}"
sudo chmod 755 "${PROJECT_DIR}/shared_files"

# 6. 创建Python虚拟环境
print_status "创建Python虚拟环境..."
sudo -u "${SERVICE_USER}" python3 -m venv "${PROJECT_DIR}/venv"
sudo -u "${SERVICE_USER}" bash -c "source ${PROJECT_DIR}/venv/bin/activate && pip install --upgrade pip"
sudo -u "${SERVICE_USER}" bash -c "source ${PROJECT_DIR}/venv/bin/activate && pip install -r ${PROJECT_DIR}/requirements.txt"

# 7. 创建Gunicorn配置文件
print_status "创建Gunicorn配置文件..."
sudo -u "${SERVICE_USER}" tee "${PROJECT_DIR}/gunicorn.conf.py" > /dev/null <<EOF
import multiprocessing

# 服务器配置
bind = "127.0.0.1:${SERVICE_PORT}"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# 日志配置
accesslog = "/var/log/${PROJECT_NAME}/access.log"
errorlog = "/var/log/${PROJECT_NAME}/error.log"
loglevel = "info"
access_log_format = '%h %l %u %t "%r" %s %b "%{Referer}i" "%{User-Agent}i"'

# 进程配置
preload_app = True
max_requests = 1000
max_requests_jitter = 50

# 安全配置
limit_request_line = 4096
limit_request_fields = 100
limit_request_field_size = 8190
EOF

# 8. 创建systemd服务文件
print_status "创建systemd服务..."
sudo tee "/etc/systemd/system/${PROJECT_NAME}.service" > /dev/null <<EOF
[Unit]
Description=WEBstore File Sharing Service
After=network.target

[Service]
Type=exec
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${PROJECT_DIR}
Environment=PATH=${PROJECT_DIR}/venv/bin
ExecStart=${PROJECT_DIR}/venv/bin/gunicorn --config gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${PROJECT_NAME}

[Install]
WantedBy=multi-user.target
EOF

# 9. 配置Nginx
print_status "配置Nginx反向代理..."
sudo tee "/etc/nginx/sites-available/${PROJECT_NAME}" > /dev/null <<EOF
server {
    listen 80;
    server_name _;
    client_max_body_size 500M;

    # 静态文件缓存
    location /static {
        alias ${PROJECT_DIR}/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # 代理到Flask应用
    location / {
        proxy_pass http://127.0.0.1:${SERVICE_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# 启用站点
sudo ln -sf "/etc/nginx/sites-available/${PROJECT_NAME}" "/etc/nginx/sites-enabled/"
sudo rm -f /etc/nginx/sites-enabled/default

# 10. 配置日志轮转
print_status "配置日志轮转..."
sudo tee "/etc/logrotate.d/${PROJECT_NAME}" > /dev/null <<EOF
/var/log/${PROJECT_NAME}/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 ${SERVICE_USER} ${SERVICE_USER}
    postrotate
        systemctl reload ${PROJECT_NAME} > /dev/null 2>&1 || true
    endscript
}
EOF

# 11. 设置文件权限
print_status "设置文件权限..."
sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "${PROJECT_DIR}"
sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "/var/log/${PROJECT_NAME}"
sudo chmod 755 "${PROJECT_DIR}"
sudo chmod 755 "${PROJECT_DIR}/shared_files"

# 12. 测试Nginx配置
print_status "测试Nginx配置..."
sudo nginx -t || {
    print_error "Nginx配置测试失败"
    exit 1
}

# 13. 启动服务
print_status "启动服务..."
sudo systemctl daemon-reload
sudo systemctl enable "${PROJECT_NAME}"
sudo systemctl start "${PROJECT_NAME}"
sudo systemctl enable nginx
sudo systemctl restart nginx

# 14. 配置防火墙
print_status "配置防火墙..."
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'

# 15. 验证服务状态
print_status "验证服务状态..."
sleep 3

if sudo systemctl is-active --quiet "${PROJECT_NAME}"; then
    print_status "✓ ${PROJECT_NAME} 服务运行正常"
else
    print_error "✗ ${PROJECT_NAME} 服务启动失败"
    echo "查看服务状态: sudo systemctl status ${PROJECT_NAME}"
    echo "查看服务日志: sudo journalctl -u ${PROJECT_NAME} -f"
fi

if sudo systemctl is-active --quiet nginx; then
    print_status "✓ Nginx 服务运行正常"
else
    print_error "✗ Nginx 服务启动失败"
    echo "查看Nginx状态: sudo systemctl status nginx"
fi

# 16. 显示部署完成信息
echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}         部署完成！                    ${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${BLUE}服务访问地址:${NC}"
echo -e "  • 本地访问: http://localhost"
echo -e "  • 外部访问: http://$(curl -s ifconfig.me || echo '你的服务器IP')"
echo
echo -e "${BLUE}服务管理命令:${NC}"
echo -e "  • 查看状态: sudo systemctl status ${PROJECT_NAME}"
echo -e "  • 重启服务: sudo systemctl restart ${PROJECT_NAME}"
echo -e "  • 停止服务: sudo systemctl stop ${PROJECT_NAME}"
echo -e "  • 启动服务: sudo systemctl start ${PROJECT_NAME}"
echo
echo -e "${BLUE}日志文件位置:${NC}"
echo -e "  • 访问日志: /var/log/${PROJECT_NAME}/access.log"
echo -e "  • 错误日志: /var/log/${PROJECT_NAME}/error.log"
echo -e "  • 系统日志: sudo journalctl -u ${PROJECT_NAME} -f"
echo
echo -e "${BLUE}项目目录:${NC}"
echo -e "  • 主目录: ${PROJECT_DIR}"
echo -e "  • 文件存储: ${PROJECT_DIR}/shared_files"
echo
echo -e "${YELLOW}注意事项:${NC}"
echo -e "  • 确保服务器的80端口对外开放"
echo -e "  • 定期备份 ${PROJECT_DIR}/shared_files 目录"
echo -e "  • 监控磁盘空间使用情况"
echo
print_status "部署脚本执行完成！"