# WEBstore 文件共享服务部署文档

## 项目简介
WEBstore 是一个基于 Flask 的文件共享 Web 应用，支持文件上传、下载、预览和删除功能。

## 部署要求
- Ubuntu 18.04+ 或其他基于 Debian 的 Linux 发行版
- Python 3.8+
- 至少 1GB 内存
- 至少 10GB 磁盘空间（根据文件存储需求调整）

## 快速部署

### 1. 准备服务器
确保你有一台 Ubuntu 服务器，并且具有 sudo 权限的用户账户。

### 2. 上传项目文件
将项目文件上传到服务器：
```bash
# 方法1：使用 scp
scp -r /path/to/WEBstore username@server_ip:/home/username/

# 方法2：使用 git clone（如果项目在 git 仓库中）
git clone https://github.com/yourusername/WEBstore.git
cd WEBstore
```

### 3. 运行部署脚本
```bash
# 给脚本添加执行权限
chmod +x deploy.sh

# 运行部署脚本
./deploy.sh
```

部署脚本会自动完成以下操作：
- 更新系统包
- 安装必要的系统依赖
- 创建专用的系统用户
- 创建 Python 虚拟环境
- 安装 Python 依赖包
- 配置 Gunicorn WSGI 服务器
- 配置 Nginx 反向代理
- 创建 systemd 服务
- 配置日志轮转
- 设置防火墙规则

### 4. 访问服务
部署完成后，你可以通过以下地址访问服务：
- `http://服务器IP地址`
- `http://localhost`（在服务器本地）

## 服务管理

### 查看服务状态
```bash
sudo systemctl status webstore
```

### 重启服务
```bash
sudo systemctl restart webstore
```

### 停止服务
```bash
sudo systemctl stop webstore
```

### 启动服务
```bash
sudo systemctl start webstore
```

### 查看实时日志
```bash
sudo journalctl -u webstore -f
```

### 查看访问日志
```bash
sudo tail -f /var/log/webstore/access.log
```

### 查看错误日志
```bash
sudo tail -f /var/log/webstore/error.log
```

## 目录结构
```
/opt/webstore/              # 项目主目录
├── app.py                  # Flask 应用主文件
├── requirements.txt        # Python 依赖列表
├── gunicorn.conf.py       # Gunicorn 配置文件
├── venv/                  # Python 虚拟环境
├── shared_files/          # 文件存储目录
└── templates/             # HTML 模板目录

/var/log/webstore/         # 日志文件目录
├── access.log            # 访问日志
└── error.log             # 错误日志
```

## 配置文件说明

### Gunicorn 配置 (`/opt/webstore/gunicorn.conf.py`)
- 监听端口：9001
- 工作进程数：CPU核心数 × 2 + 1
- 日志文件：`/var/log/webstore/`

### Nginx 配置 (`/etc/nginx/sites-available/webstore`)
- 监听端口：80
- 反向代理到：`127.0.0.1:9001`
- 文件上传大小限制：500MB

### Systemd 服务 (`/etc/systemd/system/webstore.service`)
- 服务用户：webstore
- 工作目录：`/opt/webstore`
- 自动重启：是

## 安全配置

### 防火墙规则
脚本会自动配置以下防火墙规则：
- 端口 22（SSH）：允许
- 端口 80（HTTP）：允许
- 端口 443（HTTPS）：允许

### 用户权限
- 创建专用的系统用户 `webstore`
- 限制文件访问权限
- 启用系统安全模块

## 故障排除

### 服务无法启动
1. 检查服务状态：
   ```bash
   sudo systemctl status webstore
   ```

2. 查看详细日志：
   ```bash
   sudo journalctl -u webstore -n 50
   ```

3. 检查端口占用：
   ```bash
   sudo netstat -tlnp | grep 9001
   ```

### 无法访问网站
1. 检查 Nginx 状态：
   ```bash
   sudo systemctl status nginx
   ```

2. 测试 Nginx 配置：
   ```bash
   sudo nginx -t
   ```

3. 检查防火墙：
   ```bash
   sudo ufw status
   ```

### 文件上传失败
1. 检查存储目录权限：
   ```bash
   ls -la /opt/webstore/shared_files/
   ```

2. 检查磁盘空间：
   ```bash
   df -h
   ```

3. 查看错误日志：
   ```bash
   sudo tail -f /var/log/webstore/error.log
   ```

## 维护建议

### 定期备份
```bash
# 备份共享文件
sudo tar -czf webstore-backup-$(date +%Y%m%d).tar.gz /opt/webstore/shared_files/

# 备份配置文件
sudo cp /etc/nginx/sites-available/webstore /opt/webstore/nginx.conf.backup
sudo cp /etc/systemd/system/webstore.service /opt/webstore/webstore.service.backup
```

### 监控磁盘空间
```bash
# 查看存储目录大小
du -sh /opt/webstore/shared_files/

# 清理旧的日志文件（logrotate 会自动处理）
sudo find /var/log/webstore/ -name "*.log.*" -mtime +30 -delete
```

### 更新应用
```bash
# 停止服务
sudo systemctl stop webstore

# 更新代码
cd /opt/webstore
sudo -u webstore git pull  # 如果使用 git

# 重新安装依赖（如果有更新）
sudo -u webstore bash -c "source venv/bin/activate && pip install -r requirements.txt"

# 重启服务
sudo systemctl start webstore
```

## 性能优化

### 增加工作进程数
编辑 `/opt/webstore/gunicorn.conf.py`，调整 `workers` 参数：
```python
workers = 4  # 根据服务器性能调整
```

### 启用 gzip 压缩
在 Nginx 配置中添加：
```nginx
gzip on;
gzip_types text/plain text/css application/json application/javascript text/javascript;
```

### 设置静态文件缓存
已在默认配置中启用，静态文件缓存 1 年。

## SSL/TLS 配置（可选）

如需启用 HTTPS，可以使用 Let's Encrypt：

```bash
# 安装 certbot
sudo apt install certbot python3-certbot-nginx

# 获取 SSL 证书
sudo certbot --nginx -d yourdomain.com

# 自动续期
sudo crontab -e
# 添加以下行：
# 0 12 * * * /usr/bin/certbot renew --quiet
```

## 联系支持
如果在部署过程中遇到问题，请：
1. 查看本文档的故障排除部分
2. 检查系统日志和应用日志
3. 确保服务器满足最低要求