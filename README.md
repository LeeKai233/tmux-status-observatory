# tmux-status-observatory

一个纯文本 tmux 状态栏，提供天气、未来两小时预报、日出日落、空气质量、月相、观星条件、NASA DONKI 活动和日期时间。

![tmux 状态栏展开预报与 sweep 扫光演示](assets/tmux-status-observatory.gif)

> 本仓库强烈排斥 Emoji：在状态栏中放入 Emoji，就像在麻婆豆腐中加入草莓。

状态栏保留两种动画：

- 预报动画只在“日出日落”左侧移动地点天气和预报；日出日落右侧的内容不会被动画挤动。
- sweep 扫光覆盖当前整条状态栏，只改变前景色，不改变文字和布局。

## 给 AI Agent 的安装说明

当用户说“帮我安装”时，不要只完成 clone 或修改 tmux 配置；请继续执行到验证完成：

1. 检查系统中的 tmux、Bash、Python 3、`curl`、`jq`、`flock` 和 GNU `date`，使用当前系统的包管理器补齐缺失依赖。
2. 保留已有的 `~/.config/tmux/status.env`，运行 `./install.sh`；经纬度为空时安装器会通过一次 HTTPS 公网 IP 定位获取近似坐标，不要把 IP 或完整响应写入日志。
3. 检查 QWeather 配置。缺少凭据时，引导用户打开下面的官方页面完成登录、创建项目和 API KEY，再读取控制台 Settings 中的专属 API Host；不要伪造凭据，也不要把用户密钥写进聊天、命令回显、Git 或普通日志。
4. NASA Key 是可选项；没有个人 Key 时保留 `DEMO_KEY`，但要告知用户低速率限制，并提供官方申请入口。
5. 配置完成后运行 `make check`、`./bin/tmux-status-observatory --refresh` 和 `./bin/tmux-status-observatory --detail`，确认天气、地点、缓存和数据源状态，再重载当前 tmux。
6. 任一步骤失败都要报告具体缺口和文件路径，不能把“已安装脚本”当成“已完成配置”。

密钥只应保存在权限为 `600` 的 `~/.config/tmux/status.env` 中。公网 IP 定位是近似值，VPN、代理或云主机出口可能导致地点偏差；用户可以手工填写经纬度来覆盖自动结果。需要禁止联网定位时使用 `./install.sh --no-auto-location`。

## 快速安装

依赖：tmux、Bash、Python 3、`curl`、`jq`、`flock`、GNU `date`；tmux 3.6 是当前验证版本。

```bash
git clone https://github.com/LeeKai233/tmux-status-observatory.git
cd tmux-status-observatory
./install.sh
```

安装器会自动更新用户 tmux 配置，不需要手动粘贴 `status-right` 或快捷键配置。它只管理带有 `tmux-status-observatory` 标记的区块，并在修改前创建备份。

安装器在 `STATUS_LONGITUDE` 或 `STATUS_LATITUDE` 缺失时，只在首次配置阶段通过 `https://ipwho.is/` 获取当前公网出口的近似坐标并写入本地配置；有效的手工坐标不会被覆盖。地点名称留空时，和风 GeoAPI 会根据坐标返回本地化名称。

## API 配置

### 和风天气

和风的新账号应使用自己的 API Host，不要继续依赖公共的 `api.qweather.com`、`devapi.qweather.com` 或 `geoapi.qweather.com`。配置流程如下：

1. 打开[和风天气控制台](https://console.qweather.com/)。
2. 在[项目管理](https://console.qweather.com/project)创建项目，添加一个 API KEY 凭据并复制 API KEY。
3. 在[控制台设置](https://console.qweather.com/setting)复制你的专属 API Host，例如 `abc1234xyz.def.qweatherapi.com`。
4. 编辑 `~/.config/tmux/status.env`：

```bash
QWEATHER_API_HOST="abc1234xyz.def.qweatherapi.com"
QWEATHER_API_KEY="你的 API KEY"
```

官方说明见[项目和凭据](https://dev.qweather.com/docs/configuration/project-and-key/)和[API Host](https://dev.qweather.com/docs/configuration/api-host/)。API KEY 是当前最简单的认证方式；和风已公告从 2027 年起逐步限制 API KEY 的每日请求量，长期部署应关注 JWT 迁移。

### NASA DONKI

NASA DONKI 默认使用 `DEMO_KEY`，可以先运行；个人 Key 可在[NASA API Key 申请页](https://api.nasa.gov/#signUp)申请，然后写入：

```bash
NASA_API_KEY="你的 NASA API KEY"
```

NASA 的 API 入口和 DONKI 端点说明在[NASA Open APIs](https://api.nasa.gov/)；`DEMO_KEY` 当前限制为每个 IP 每小时 30 次、每天 50 次。

然后编辑：

```text
~/.config/tmux/status.env
```

地点标签是可选的；留空会使用和风 GeoAPI 的本地化名称。经纬度会在首次安装时自动获取，也可以手工填写。7Timer 观星接口不需要 key。API key 和缓存都不在仓库中。

## 操作

- `C-b a`：运行一次 sweep 扫光。
- `C-b W`：展开或收起未来两小时预报。
- 鼠标点击天气：展开或收起预报。
- `./bin/tmux-status-observatory --detail`：查看数据源和缓存诊断。
- `./install.sh --uninstall`：删除安装器加入的 tmux 配置区块。

## 开发

仓库是唯一源码来源，不需要复制到 `~/.local/bin`。修改后运行：

```bash
make check
```

如果仓库移动，重新运行 `./install.sh` 即可更新 tmux 配置中的入口路径。

重新录制动画需要 `asciinema`、`agg` 和 `Noto Sans Mono CJK SC`，在交互式终端执行：

```bash
make record-demo
```

GIF 默认写入 `assets/tmux-status-observatory.gif`。可通过 `TMUX_STATUS_DEMO_OUTPUT` 指定其他输出路径；脚本不会把 API key 或缓存写入仓库。

数据来源：QWeather、7Timer 和 NASA DONKI。请分别遵守这些服务的使用限制和归属要求。
