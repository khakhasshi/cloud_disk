#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import socket
from flask import Flask, render_template, request, send_file, redirect, url_for, flash, jsonify
from werkzeug.utils import secure_filename
import zipfile
import tempfile
from datetime import datetime

app = Flask(__name__)
app.secret_key = 'your-secret-key-change-this'

# 配置文件上传
UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shared_files')
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 3072 * 1024 * 1024  # 3072MB 最大文件大小

# 确保上传目录存在
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def get_local_ip():
    """获取本机IP地址"""
    try:
        # 连接到一个远程地址来获取本机IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def format_file_size(size_bytes):
    """格式化文件大小"""
    if size_bytes == 0:
        return "0B"
    size_names = ["B", "KB", "MB", "GB"]
    i = 0
    while size_bytes >= 1024 and i < len(size_names) - 1:
        size_bytes /= 1024.0
        i += 1
    return f"{size_bytes:.1f}{size_names[i]}"

def get_file_info(filepath):
    """获取文件信息"""
    stat = os.stat(filepath)
    return {
        'name': os.path.basename(filepath),
        'size': format_file_size(stat.st_size),
        'size_bytes': stat.st_size,
        'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
    }

@app.route('/')
def index():
    """主页面 - 显示文件列表"""
    files = []
    if os.path.exists(UPLOAD_FOLDER):
        for filename in os.listdir(UPLOAD_FOLDER):
            filepath = os.path.join(UPLOAD_FOLDER, filename)
            if os.path.isfile(filepath):
                files.append(get_file_info(filepath))
    
    # 按文件名排序
    files.sort(key=lambda x: x['name'])
    
    return render_template('index.html', files=files, server_ip=get_local_ip())

@app.route('/upload', methods=['POST'])
def upload_file():
    """处理文件上传"""
    if 'file' not in request.files:
        flash('没有选择文件', 'error')
        return redirect(url_for('index'))
    
    files = request.files.getlist('file')  # 获取多个文件
    if not files or all(file.filename == '' for file in files):
        flash('没有选择文件', 'error')
        return redirect(url_for('index'))
    
    uploaded_files = []
    failed_files = []
    
    for file in files:
        if file and file.filename != '':
            filename = secure_filename(file.filename)
            if not filename:
                failed_files.append(f'{file.filename} (无效文件名)')
                continue
            
            # 如果文件已存在，添加时间戳
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            if os.path.exists(filepath):
                name, ext = os.path.splitext(filename)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                filename = f"{name}_{timestamp}{ext}"
                filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            
            try:
                file.save(filepath)
                uploaded_files.append(filename)
            except Exception as e:
                failed_files.append(f'{filename} ({str(e)})')
    
    # 显示上传结果
    if uploaded_files:
        if len(uploaded_files) == 1:
            flash(f'文件 "{uploaded_files[0]}" 上传成功！', 'success')
        else:
            flash(f'成功上传 {len(uploaded_files)} 个文件！', 'success')
    
    if failed_files:
        if len(failed_files) == 1:
            flash(f'上传失败: {failed_files[0]}', 'error')
        else:
            flash(f'{len(failed_files)} 个文件上传失败', 'error')
    
    return redirect(url_for('index'))

@app.route('/download/<filename>')
def download_file(filename):
    """下载文件"""
    try:
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.exists(filepath):
            return send_file(filepath, as_attachment=True)
        else:
            flash('文件不存在', 'error')
            return redirect(url_for('index'))
    except Exception as e:
        flash(f'下载失败: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/preview/<filename>')
def preview_file(filename):
    """预览文件（用于图片显示）"""
    try:
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.exists(filepath):
            return send_file(filepath)
        else:
            return '', 404
    except Exception as e:
        return '', 404

@app.route('/delete/<filename>')
def delete_file(filename):
    """删除文件"""
    try:
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.exists(filepath):
            os.remove(filepath)
            flash(f'文件 "{filename}" 删除成功！', 'success')
        else:
            flash('文件不存在', 'error')
    except Exception as e:
        flash(f'删除失败: {str(e)}', 'error')
    
    return redirect(url_for('index'))

@app.route('/download_all')
def download_all():
    """下载所有文件为ZIP"""
    try:
        if not os.path.exists(UPLOAD_FOLDER) or not os.listdir(UPLOAD_FOLDER):
            flash('没有文件可下载', 'error')
            return redirect(url_for('index'))
        
        # 创建临时ZIP文件
        temp_dir = tempfile.mkdtemp()
        zip_filename = f"shared_files_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip"
        zip_path = os.path.join(temp_dir, zip_filename)
        
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for filename in os.listdir(UPLOAD_FOLDER):
                filepath = os.path.join(UPLOAD_FOLDER, filename)
                if os.path.isfile(filepath):
                    zipf.write(filepath, filename)
        
        return send_file(zip_path, as_attachment=True, download_name=zip_filename)
    
    except Exception as e:
        flash(f'打包下载失败: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/api/files')
def api_files():
    """API接口 - 获取文件列表"""
    files = []
    if os.path.exists(UPLOAD_FOLDER):
        for filename in os.listdir(UPLOAD_FOLDER):
            filepath = os.path.join(UPLOAD_FOLDER, filename)
            if os.path.isfile(filepath):
                files.append(get_file_info(filepath))
    
    return jsonify({'files': files})

if __name__ == '__main__':
    # 获取本机IP地址
    local_ip = get_local_ip()
    port = 9001  # 更改为9001端口
    
    print(f"🚀 文件共享服务器启动中...")
    print(f"📱 本地访问: http://127.0.0.1:{port}")
    print(f"🌐 网络访问: http://{local_ip}:{port}")
    print(f"📁 文件存储目录: {UPLOAD_FOLDER}")
    print(f"⚡ 按 Ctrl+C 停止服务器")
    print("=" * 50)
    
    # 启动Flask应用，允许外部访问
    app.run(host='0.0.0.0', port=port, debug=False)
