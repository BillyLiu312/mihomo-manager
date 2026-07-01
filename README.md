# Mihomo/Clash Remote Server Manager

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

## 1. 安装到服务器

把 `mihomoctl.sh` 上传到远程服务器，例如：

```bash
mkdir -p ~/.config/mihomo
cp mihomoctl.sh ~/.config/mihomo/mihomoctl.sh
chmod +x ~/.config/mihomo/mihomoctl.sh
```

如果你的二进制文件已经在这里：

```bash
~/.config/mihomo/clash-linux
```

确保它可执行：

```bash
chmod +x ~/.config/mihomo/clash-linux
```

## 2. 首次配置订阅

注意：URL 一定要加引号，因为里面通常有 `&`。

```bash
cd ~/.config/mihomo

./mihomoctl.sh init
./mihomoctl.sh set-url 'https://你的订阅地址/api/v1/client/subscribe?token=你的token&flag=clash'
./mihomoctl.sh fetch
```

`set-url` 会自动补上 `flag=clash`，并把 token 存到：

```text
~/.config/mihomo/subscription.env
```

这个文件权限会设置为 `600`。

## 3. 后台启动

```bash
cd ~/.config/mihomo
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

## 4. 让当前终端 / VSCode / Codex 走代理

启动成功后，默认代理端口是：

```text
127.0.0.1:7890
```

临时设置当前终端：

```bash
eval "$(~/.config/mihomo/mihomoctl.sh env)"
```

测试：

```bash
curl https://api.openai.com/v1/models -I
```

如果返回 `401`、`403`、`404` 都说明网络连到了，只是 API 身份或路径问题；如果超时才是代理/网络问题。

也可以只让某条命令走代理：

```bash
~/.config/mihomo/mihomoctl.sh run curl https://api.openai.com/v1/models -I
```

如果你想让远程 VSCode/Codex 总是继承代理，可以把下面这行放进 `~/.bashrc`：

```bash
eval "$($HOME/.config/mihomo/mihomoctl.sh env)"
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

## 5. 更换 VPN/订阅 token

如果只是 token 变了：

```bash
cd ~/.config/mihomo
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

## 6. 停止代理

停止后台 mihomo/clash：

```bash
cd ~/.config/mihomo
./mihomoctl.sh stop
```

取消当前终端里的代理环境变量：

```bash
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
unset http_proxy https_proxy all_proxy
```

如果你把 `eval "$($HOME/.config/mihomo/mihomoctl.sh env)"` 写进了 `~/.bashrc`，要永久取消就把那一行删掉或注释掉。

## 7. 更新 GeoSite / GeoIP

如果配置依赖 `GeoSite.dat` / `GeoIP.dat`：

```bash
cd ~/.config/mihomo
./mihomoctl.sh update-geodata
./mihomoctl.sh restart
```

## 8. 常见问题

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
