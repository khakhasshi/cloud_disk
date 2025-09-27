# 设置sudo密码的解决方案

## 方案1：为当前用户设置密码
```bash
# 在服务器上运行
sudo passwd ubuntu
```

## 方案2：配置免密码sudo（推荐）
```bash
# 编辑sudo配置
sudo visudo

# 在文件末尾添加以下行：
ubuntu ALL=(ALL) NOPASSWD:ALL
```

**具体操作步骤：**
1. 在服务器终端中运行 `sudo visudo`
2. 使用方向键移动到文件末尾
3. 按 `i` 键进入插入模式（如果使用vim）
4. 添加新行：`ubuntu ALL=(ALL) NOPASSWD:ALL`
5. 按 `Esc` 键退出插入模式
6. 输入 `:wq` 并按回车保存退出

如果使用的是nano编辑器：
1. 移动到文件末尾
2. 添加新行：`ubuntu ALL=(ALL) NOPASSWD:ALL`
3. 按 `Ctrl+X` 退出
4. 按 `Y` 确认保存
5. 按回车确认文件名

## 方案3：临时解决方案 - 修改deploy.sh脚本
如果以上方法不适用，可以修改deploy.sh脚本跳过sudo密码检查。