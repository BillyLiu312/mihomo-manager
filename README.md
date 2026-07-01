# Mihomo/Clash Remote Server Manager

基础代理能力来自 [@MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)。本仓库只提供一个轻量管理脚本，用来在远程 Linux 服务器上更方便地启动、停止、更新配置和查看日志。

这个小工具用于在远程 Linux 服务器上管理 `mihomo`/`clash`：

- 后台启动代理
- 查看运行状态和日志
- 停止代理
- 下载/更新 Clash/Mihomo 订阅配置
- 更换订阅 token
- 输出 VSCode/Codex/终端可用的代理环境变量

默认路径与你当前操作一致：

```text
~/.config/mihomo/clash-linux
~/.config/mihomo/config.yaml
~/.config/mihomo/mihomo.log
```

## 1. 准备 mihomo 基础文件

本节整理自 [bannedbook/fanqiang 的 Linux 教程](https://github.com/bannedbook/fanqiang/blob/5cb11c6420a95cdc83c4a29ffc54e2cd9e4689d4/linux/readme.md)，用于完成前期目录、二进制文件和地理数据库准备。

创建并进入程序目录：

```bash
mkdir -p ~/.config/mihomo
cd ~/.config/mihomo
```

下载 Linux amd64 版本的 mihomo/clash：

```bash
wget -O clash-linux.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.17.0/mihomo-linux-amd64-v1.17.0.gz
```

如果这个版本链接失效，去 [MetaCubeX/mihomo Releases](https://github.com/MetaCubeX/mihomo/releases) 选择适合你服务器架构的 `linux-amd64` / `linux-arm64` 版本，并把下载后的文件放到：

```text
~/.config/mihomo/clash-linux.gz
```

解压并授权：

```bash
gzip -f clash-linux.gz -d
chmod +x clash-linux
```

初始化执行一次，让 mihomo 生成默认文件；启动后等一会儿，然后按 `Ctrl+C` 退出：

```bash
./clash-linux
```

查看目录：

```bash
ls -rtl ~/.config/mihomo/
```

如果 `Country.mmdb` 没有自动生成，可以手动下载：

```bash
wget -O ~/.config/mihomo/Country.mmdb https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
```

如果 `GeoSite.dat` 没有自动生成，可以先用脚本后面的 `update-geodata` 命令补齐；或者手动下载后放到 `~/.config/mihomo/`：

```bash
wget -O ~/.config/mihomo/GeoSite.dat https://github.com/ewigl/mihomo/raw/master/GeoSite.dat
```

## 2. 克隆本管理脚本

在远程服务器上克隆这个仓库：

```bash
cd ~/.config/mihomo
git clone https://github.com/BillyLiu312/mihomo-manager.git manager
```

进入仓库并确认脚本可执行：

```bash
cd ~/.config/mihomo/manager
chmod +x mihomoctl.sh
```

后续命令都在这个目录执行：

```bash
cd ~/.config/mihomo/manager
```

## 3. 首次配置订阅

注意：URL 一定要加引号，因为里面通常有 `&`。

```bash
./mihomoctl.sh init
./mihomoctl.sh set-url 'https://你的订阅地址/api/v1/client/subscribe?token=你的token&flag=clash'
./mihomoctl.sh fetch
```

`set-url` 会自动补上 `flag=clash`，并把 token 存到：

```text
~/.config/mihomo/subscription.env
```

这个文件权限会设置为 `600`。

## 4. 后台启动

```bash
./mihomoctl.sh start
```

查看状态：

```bash
./mihomoctl.sh status
```

查看日志：

```bash
./mihomoctl.sh logs
```

持续跟踪日志：

```bash
./mihomoctl.sh logs -f
```

## 5. 让当前终端 / VSCode / Codex 走代理

启动成功后，默认代理端口是：

```text
127.0.0.1:7890
```

临时设置当前终端：

```bash
eval "$(~/.config/mihomo/manager/mihomoctl.sh env)"
```

测试：

```bash
curl https://api.openai.com/v1/models -I
```

如果返回 `401`、`403`、`404` 都说明网络连到了，只是 API 身份或路径问题；如果超时才是代理/网络问题。

也可以只让某条命令走代理：

```bash
~/.config/mihomo/manager/mihomoctl.sh run curl https://api.openai.com/v1/models -I
```

如果你想让远程 VSCode/Codex 总是继承代理，可以把下面这行放进 `~/.bashrc`：

```bash
eval "$($HOME/.config/mihomo/manager/mihomoctl.sh env)"
```

然后：

```bash
source ~/.bashrc
```

之后在 VSCode 命令面板执行：

```text
Remote-SSH: Kill VS Code Server on Host...
```

重新连接服务器，让 VSCode Server 继承新的环境变量。

## 6. 更换 VPN/订阅 token

如果只是 token 变了：

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh set-token 新token
./mihomoctl.sh fetch
./mihomoctl.sh restart
```

如果整个订阅地址变了：

```bash
./mihomoctl.sh set-url 'https://新的订阅地址?token=新token&flag=clash'
./mihomoctl.sh fetch
./mihomoctl.sh restart
```

## 7. 停止代理

停止后台 mihomo/clash：

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh stop
```

取消当前终端里的代理环境变量：

```bash
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
unset http_proxy https_proxy all_proxy
```

如果你把 `eval "$($HOME/.config/mihomo/manager/mihomoctl.sh env)"` 写进了 `~/.bashrc`，要永久取消就把那一行删掉或注释掉。

## 8. 更新 GeoSite / GeoIP

如果配置依赖 `GeoSite.dat` / `GeoIP.dat`：

```bash
cd ~/.config/mihomo/manager
./mihomoctl.sh update-geodata
./mihomoctl.sh restart
```

## 9. 常见问题

### `cannot unmarshal !!str c3M6Ly9...`

下载到的是 base64/raw 节点订阅，不是 Clash/Mihomo YAML。解决：

```bash
./mihomoctl.sh set-url '你的订阅URL&flag=clash'
./mihomoctl.sh fetch
```

### 命令执行后出现 `[1] 12345`

URL 没加引号，shell 把 `&flag=clash` 当成后台运行符号了。订阅 URL 必须用单引号包住。

### 代理启动了，但 Codex 还是连不上

先检查：

```bash
./mihomoctl.sh status
eval "$(./mihomoctl.sh env)"
curl https://api.openai.com/v1/models -I
```

如果 `curl` 能连，但 VSCode/Codex 不行，重启 VSCode Server：

```text
Remote-SSH: Kill VS Code Server on Host...
```

然后重新连接远程服务器。
