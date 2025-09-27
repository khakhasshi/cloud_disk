#!/bin/bash
# WEBstore 服务管理脚本
# 使用方法: ./webstore.sh [start|stop|restart|status|logs]

PROJECT_NAME="webstore"

case "$1" in
    start)
        echo "启动 WEBstore 服务..."
        sudo systemctl start $PROJECT_NAME
        sudo systemctl start nginx
        echo "服务已启动"
        ;;
    stop)
        echo "停止 WEBstore 服务..."
        sudo systemctl stop $PROJECT_NAME
        echo "服务已停止"
        ;;
    restart)
        echo "重启 WEBstore 服务..."
        sudo systemctl restart $PROJECT_NAME
        sudo systemctl restart nginx
        echo "服务已重启"
        ;;
    status)
        echo "=== WEBstore 服务状态 ==="
        sudo systemctl status $PROJECT_NAME --no-pager -l
        echo
        echo "=== Nginx 服务状态 ==="
        sudo systemctl status nginx --no-pager -l
        ;;
    logs)
        echo "=== 查看实时日志 (Ctrl+C 退出) ==="
        sudo journalctl -u $PROJECT_NAME -f
        ;;
    access-logs)
        echo "=== 查看访问日志 ==="
        sudo tail -f /var/log/$PROJECT_NAME/access.log
        ;;
    error-logs)
        echo "=== 查看错误日志 ==="
        sudo tail -f /var/log/$PROJECT_NAME/error.log
        ;;
    *)
        echo "使用方法: $0 {start|stop|restart|status|logs|access-logs|error-logs}"
        echo
        echo "命令说明:"
        echo "  start        - 启动服务"
        echo "  stop         - 停止服务"
        echo "  restart      - 重启服务"
        echo "  status       - 查看服务状态"
        echo "  logs         - 查看实时日志"
        echo "  access-logs  - 查看访问日志"
        echo "  error-logs   - 查看错误日志"
        exit 1
        ;;
esac