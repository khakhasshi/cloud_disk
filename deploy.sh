#!/bin/bash
# Ubuntu服务器部署脚本
# 使用方法: chmod +x deploy.sh && ./deploy.sh

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
echo -e "${BLUE}======================================${NC}"

# 检查是否为root用户
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}请不要使用root用户直接运行此脚本${NC}"
    echo -e "${YELLOW}建议使用具有sudo权限的普通用户运行${NC}"
    exit 1
fi

# 检查sudo权限
echo -e "${YELLOW}检查sudo权限...${NC}"
# 使用无密码检查方式
if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}sudo权限已配置为免密码${NC}"
else
    echo -e "${YELLOW}尝试验证sudo权限...${NC}"
    sudo -v || {
        echo -e "${RED}需要sudo权限才能继续${NC}"
        echo -e "${YELLOW}提示：如果没有设置密码，请运行 'sudo passwd \$(whoami)' 设置密码${NC}"
        echo -e "${YELLOW}或者配置免密码sudo：sudo visudo 并添加 '\$(whoami) ALL=(ALL) NOPASSWD:ALL'${NC}"
        exit 1
    }
fi

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

# 更新系统包
print_status "更新系统包..."
sudo apt update && sudo apt upgrade -y

# 安装系统依赖
print_status "安装系统依赖..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    nginx \
    supervisor \
    git \
    curl \
    unzip \
    build-essential

# 创建系统用户
print_status "创建服务用户: $SERVICE_USER"
if id "$SERVICE_USER" &>/dev/null; then
    print_warning "用户 $SERVICE_USER 已存在，跳过创建"
else
    sudo useradd --system --shell /bin/bash --home-dir "$PROJECT_DIR" --create-home "$SERVICE_USER"
    print_status "用户 $SERVICE_USER 创建成功"
fi

# 创建项目目录
print_status "创建项目目录..."
sudo mkdir -p "$PROJECT_DIR"
sudo mkdir -p "$PROJECT_DIR/shared_files"
sudo mkdir -p "/var/log/$PROJECT_NAME"

# 复制项目文件
print_status "复制项目文件..."
current_dir=$(pwd)
sudo cp -r "$current_dir"/* "$PROJECT_DIR/"

# 设置目录权限
print_status "设置目录权限..."
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$PROJECT_DIR"
sudo chown -R "$SERVICE_USER:$SERVICE_USER" "/var/log/$PROJECT_NAME"
sudo chmod -R 755 "$PROJECT_DIR"
sudo chmod -R 777 "$PROJECT_DIR/shared_files"  # 共享文件目录需要写权限

# 创建Python虚拟环境
print_status "创建Python虚拟环境..."
sudo -u "$SERVICE_USER" python3 -m venv "$PROJECT_DIR/venv"

# 激活虚拟环境并安装依赖
print_status "安装Python依赖包..."
sudo -u "$SERVICE_USER" bash -c "
    cd '$PROJECT_DIR' && \
    source venv/bin/activate && \
    pip install --upgrade pip && \
    pip install -r requirements.txt
"

# 创建Gunicorn配置文件
print_status "创建Gunicorn配置..."
sudo tee "$PROJECT_DIR/gunicorn.conf.py" > /dev/null << EOF
# Gunicorn配置文件
import multiprocessing

# 服务器配置
bind = "0.0.0.0:$SERVICE_PORT"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# 日志配置
accesslog = "/var/log/$PROJECT_NAME/access.log"
errorlog = "/var/log/$PROJECT_NAME/error.log"
loglevel = "info"

# 进程配置
daemon = False
pidfile = "/var/run/$PROJECT_NAME.pid"
user = "$SERVICE_USER"
group = "$SERVICE_USER"

# 性能配置
max_requests = 1000
max_requests_jitter = 100
preload_app = True
EOF

# 创建systemd服务文件
print_status "创建systemd服务..."
sudo tee "/etc/systemd/system/${PROJECT_NAME}.service" > /dev/null << EOF
[Unit]
Description=WEBstore File Sharing Service
After=network.target

[Service]
Type=exec
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/gunicorn --config gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=5

# 安全配置
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$PROJECT_DIR/shared_files /var/log/$PROJECT_NAME /tmp

[Install]
WantedBy=multi-user.target
EOF

# 配置Nginx反向代理
print_status "配置Nginx反向代理..."
sudo tee "/etc/nginx/sites-available/${PROJECT_NAME}" > /dev/null << EOF
server {
    listen 80;
    server_name _;  # 监听所有域名

    # 客户端上传文件大小限制（500MB）
    client_max_body_size 500M;

    location / {
        proxy_pass http://127.0.0.1:$SERVICE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 静态文件直接由Nginx服务
    location /static/ {
        alias $PROJECT_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# 启用Nginx站点
print_status "启用Nginx站点..."
sudo ln -sf "/etc/nginx/sites-available/${PROJECT_NAME}" "/etc/nginx/sites-enabled/"
sudo rm -f /etc/nginx/sites-enabled/default  # 删除默认站点

# 测试Nginx配置
sudo nginx -t

# 创建日志轮转配置
print_status "配置日志轮转..."
sudo tee "/etc/logrotate.d/${PROJECT_NAME}" > /dev/null << EOF
/var/log/$PROJECT_NAME/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_USER
    postrotate
        systemctl reload $PROJECT_NAME
    endscript
}
EOF

# 创建防火墙规则
print_status "配置防火墙..."
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw --force enable

# 重新加载systemd并启动服务
print_status "启动服务..."
sudo systemctl daemon-reload
sudo systemctl enable "${PROJECT_NAME}.service"
sudo systemctl start "${PROJECT_NAME}.service"
sudo systemctl enable nginx
sudo systemctl restart nginx

# 等待服务启动
sleep 3

# 检查服务状态
print_status "检查服务状态..."
if systemctl is-active --quiet "${PROJECT_NAME}.service"; then
    print_status "✅ WEBstore服务运行正常"
else
    print_error "❌ WEBstore服务启动失败"
    sudo journalctl -u "${PROJECT_NAME}.service" --no-pager -n 20
fi

if systemctl is-active --quiet nginx; then
    print_status "✅ Nginx服务运行正常"
else
    print_error "❌ Nginx服务启动失败"
fi

# 获取服务器IP
SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}           部署完成！                   ${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "${BLUE}服务访问地址:${NC}"
echo -e "  • 本地访问: http://localhost"
echo -e "  • 网络访问: http://${SERVER_IP}"
echo -e "\n${BLUE}服务管理命令:${NC}"
echo -e "  • 查看服务状态: ${YELLOW}sudo systemctl status ${PROJECT_NAME}${NC}"
echo -e "  • 重启服务:     ${YELLOW}sudo systemctl restart ${PROJECT_NAME}${NC}"
echo -e "  • 停止服务:     ${YELLOW}sudo systemctl stop ${PROJECT_NAME}${NC}"
echo -e "  • 查看日志:     ${YELLOW}sudo journalctl -u ${PROJECT_NAME} -f${NC}"
echo -e "\n${BLUE}文件存储目录:${NC} ${PROJECT_DIR}/shared_files"
echo -e "${BLUE}日志文件目录:${NC} /var/log/${PROJECT_NAME}"
echo -e "\n${GREEN}部署成功！服务将在系统重启后自动启动。${NC}"