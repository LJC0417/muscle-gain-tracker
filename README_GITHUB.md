# 增肌管理 APP · 从代码到手机安装 · 完整步骤

> 给零技术背景用户的「傻瓜式」操作手册。每一步都附 PowerShell 命令，复制粘贴运行即可。
> 整条流程大概需要 **20-40 分钟**（其中 90% 时间是 GitHub Actions 云端编译在跑）。

---

## 一、你要做什么（一图看懂）

```
本机电脑（你在这里）                    GitHub（云端）                  手机（你在这里）
                              ┌─────────────────────────┐
   写代码 / 改代码    ───push──>  Actions 自动编译 APK   ───下载──>  打开 APK 安装
   （不用你做）              └─────────────────────────┘
```

你的实际操作只有 3 件事：

1. **建一个 GitHub 仓库**（10 分钟）
2. **把代码推上去**（5 分钟）
3. **等编译完下载 APK**（15-30 分钟）+ **手机安装**（2 分钟）

---

## 二、需要的工具（一次性安装）

### 1. Git（让代码能推到 GitHub）

打开 PowerShell（按 `Win + X` → 选 `Windows PowerShell` 或 `终端`），粘贴下面这一行：

```powershell
winget install --id Git.Git -e --source winget
```

装完**关掉再打开** PowerShell 验证：

```powershell
git --version
```

看到 `git version 2.x.x` 即可。

### 2. 注册 GitHub 账号（如果你还没有）

去 https://github.com/signup 注册一个免费账号。
- 邮箱：用你最常用的（QQ 邮箱、163、Gmail 都行）
- 用户名：选一个不会后悔的
- 密码：建议 1Password / Bitwarden 存一下

> GitHub 对个人项目**完全免费**，不会有任何收费。

### 3. 准备 APP 文件位置

我们这个项目的根目录是：

```
D:\000_WorkBuddy\Sport\stage_b\muscle_gain_tracker
```

确认这个目录存在 + 里面有 `.github\workflows\build-apk.yml` 文件。

---

## 三、建 GitHub 仓库（5 分钟）

### 步骤 1：登录 GitHub → 新建仓库

打开 https://github.com/new ，填：

| 字段 | 填什么 |
|------|--------|
| Repository name | `muscle-gain-tracker` （**必须用这个名**，或者你喜欢的也行） |
| Description | `增肌管理 Flutter APP` |
| Public / Private | **Public**（公开，编译免费额度更高） |
| Add README / Add .gitignore / Add license | **都不要勾** |

点 **Create repository**。

### 步骤 2：创建 Personal Access Token（让 Git 能推送代码）

> GitHub 从 2021 年起不让你用密码直接 push，必须用 token。

打开 https://github.com/settings/tokens/new

| 字段 | 填什么 |
|------|--------|
| Note | `git-push` |
| Expiration | `No expiration` 或 `90 days` |
| Select scopes | 勾上 `repo`（其他不用勾） |

点 **Generate token** → **复制**那个 `ghp_xxx...` 字符串（只显示一次！）。

> ⚠️ 这个 token 等于你的密码，**不要发给别人**，先存在记事本里。

---

## 四、推送代码到 GitHub（5 分钟）

打开 PowerShell，进入项目目录：

```powershell
cd D:\000_WorkBuddy\Sport\stage_b\muscle_gain_tracker
```

初始化 Git + 设置身份（第一次用 Git 才需要）：

```powershell
git init
git config user.name "你的GitHub用户名"
git config user.email "你的GitHub注册邮箱"
```

把所有文件加进来（**注意：项目根目录是 muscle_gain_tracker**）：

```powershell
git add .
git commit -m "first commit: F01-F05 最小可运行 APK"
```

把远程仓库接上（**把下面的 `你的用户名` 替换成你的 GitHub 用户名**）：

```powershell
git remote add origin https://github.com/你的用户名/muscle-gain-tracker.git
git branch -M main
```

推送代码（**这一步会弹窗让你输账号密码**）：

- Username: 你的 GitHub 用户名
- Password: **粘贴刚才那个 token**（不是你的 GitHub 密码）

```powershell
git push -u origin main
```

看到类似下面就成功了：

```
Enumerating objects: 120, done.
Counting objects: 100% (120/120), done.
...
To https://github.com/xxx/muscle-gain-tracker.git
 * [new branch]      main -> main
```

---

## 五、触发 GitHub Actions 编译（15-30 分钟）

### 方式 A：自动触发（你已经 push 了，会自动跑）

打开 https://github.com/你的用户名/muscle-gain-tracker/actions 刷新看。

### 方式 B：手动触发（推荐，最稳）

1. 打开 https://github.com/你的用户名/muscle-gain-tracker/actions
2. 左边选 **Build Android APK (arm64-v8a)**
3. 右边点 **Run workflow** → **Run workflow** 按钮

### 看编译进度

- ✅ 绿色对勾 = 这一步成功
- ❌ 红色叉 = 这一步失败（点进去看日志）
- 🟡 黄色圆圈 = 正在跑

> 第一次编译大概 **15-25 分钟**（要下载 Flutter SDK、Drift 依赖等）。
> 后面再编译会快很多（5-10 分钟）。

### 常见错误排查

| 错误 | 原因 | 解决 |
|------|------|------|
| `flutter pub get` 失败 | 网络问题 | 重跑 workflow（重试） |
| `build_runner` 报错 | Drift 表 schema 冲突 | 我会修，你重新 push 即可 |
| `Could not find method X` | Flutter 版本不对 | 我已钉死 3.22.3，理论上不会出 |

**如果卡住超过 30 分钟还没好**——把失败那一步的**最后 20 行日志截图发我**。

---

## 六、下载 APK 到电脑（2 分钟）

编译成功（绿色对勾）后：

1. 回到 https://github.com/你的用户名/muscle-gain-tracker/actions
2. 点那次成功的运行（最上面那个）
3. 滚到最下面 **Artifacts** 区域
4. 点 **muscle-gain-tracker-arm64-v8a** 下载（是个 zip）
5. 解压 zip，里面就是 `muscle-gain-tracker-arm64-v8a-release.apk`

---

## 七、安装到安卓手机（2 分钟）

### 1. 确认手机是 arm64 架构（99% 的现代手机都是）

手机 `设置 → 关于手机 → 处理器` 看是不是 arm64-v8a / aarch64。
- ✅ 是 → 直接装下面这个 APK
- ❌ 是 armv7（很老的手机）→ 联系我重新编译

### 2. 把 APK 拷到手机

**方法 A：USB 数据线**
- 手机连电脑 → 选「文件传输 / MTP」模式
- 把 `muscle-gain-tracker-arm64-v8a-release.apk` 拖到手机 Download 文件夹

**方法 B：网盘 / 微信文件传输**
- 把 APK 上传到你的网盘 / 发到「文件传输助手」
- 手机上下载

### 3. 允许安装未知来源

手机 `设置 → 安全 → 安装未知应用` → 选你用来打开 APK 的那个 app（一般是「文件管理」或「浏览器」）→ 允许。

> 这只是第一次安装会问，第二次就不问了。

### 4. 点 APK 文件安装

在手机文件管理器里点 `muscle-gain-tracker-arm64-v8a-release.apk` → **安装** → 打开。

---

## 八、第一次使用 APP

1. 打开「增肌管理」APP
2. 第一屏是引导页：填性别 / 年龄 / 身高 / 当前体重 / 目标体重 / 场景 → **完成**
3. 进入今日页：能看到 RingProgress（环）+ 目标 + 习惯打卡

**本期能用的功能**：
- ✅ 今日页：看今日目标、习惯打卡（喝水/睡眠）
- ✅ 训练页：看周排期、训练日详情、「开始训练」按钮会弹提示
- ✅ 饮食页：4 餐 tab、查看已记录食物、清空今日食物
- ✅ 我的页：查看资料、重新生成训练计划、清空数据

**本期还不能用的功能**（下个版本会做）：
- ⚠️ 真的开始训练 + 记录组数（点「开始训练」会弹提示）
- ⚠️ 添加食物（点「+」会弹提示）
- ⚠️ AI 周报
- ⚠️ 通知提醒
- ⚠️ 数据备份

---

## 九、下次再编译（改完代码后）

如果你（或者让我）改完代码，需要重新出 APK：

```powershell
cd D:\000_WorkBuddy\Sport\stage_b\muscle_gain_tracker
git add .
git commit -m "改动说明"
git push
```

然后去 Actions 页面看新的 run 跑完，下载新 APK 装到手机。

---

## 十、常见问题 FAQ

**Q：APK 装到手机提示「未安装」怎么办？**
A：先卸载旧版本（如果有）→ 重新装。如果还不行就是签名问题，联系我。

**Q：装完之后打开 APP 闪退？**
A：用 Android Studio 的 `adb logcat` 抓日志，截图发我。零技术用户可以手机 `设置 → 开发者选项 → 错误报告` 抓一份。

**Q：编译要多久？**
A：第一次 15-25 分钟（下载 SDK + 依赖），后面 5-10 分钟。

**Q：我不懂代码，能改 APP 内容吗？**
A：暂时需要我帮你改。你可以告诉我"我想在今日页加一个 X 按钮"，我改完代码 + 帮你 push + 触发编译 + 你下载安装。

**Q：iPhone 能装吗？**
A：不能。这个 APK 是 Android 专用。iOS 需要单独编译 IPA，工作量翻倍。**本项目暂不支持 iOS。**

**Q：可以加自定义图标 / 启动图吗？**
A：可以，但需要我帮你生成 + 改代码 + 重新编译。下版本做。

---

## 联系

任何一步卡住，**截图 + 文字描述发我**。我会给你具体解决方案。

最常见的「卡住点」是第四步 push 时让你输密码——记得是粘贴 **token 不是 GitHub 密码**。
