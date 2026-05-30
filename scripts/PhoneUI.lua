-- ====================================================================
-- PhoneUI.lua - 手机界面系统
-- ====================================================================

local Config = require("Config")
local UI = require("urhox-libs/UI")

local PhoneUI = {}

-- 内部状态
local phoneRoot = nil
local phoneSlider = nil      -- 滑动容器（手+手机）
local isVisible = false
local currentApp = nil
local onEventCallback = nil -- 回调给主游戏处理事件

-- 滑入动画状态
local ANIM_DURATION = 0.35   -- 动画时长（秒）
local animState = "hidden"   -- "hidden" | "sliding_in" | "visible" | "sliding_out"
local animProgress = 0       -- 0→1 动画进度
local animOffset = 600       -- 当前Y偏移（像素，正=向下偏移）

-- App 内容面板引用
local mapPanel = nil
local scanPanel = nil
local payPanel = nil
local homePanel = nil
local adOverlay = nil
local fakeAppPanel = nil

-- 假应用下载状态
local fakeAppDownloading = false
local fakeAppProgress = 0
local fakeAppName = ""
local fakeAppLoadingTime = 0  -- 低电量时先转圈
local fakeAppLoading = false
local fakeAppDownloadSpeed = 0

function PhoneUI.Init(eventCallback)
    onEventCallback = eventCallback
end

function PhoneUI.CreateUI()
    -- 手+手机的滑动容器
    phoneSlider = UI.Panel {
        id = "phoneSlider",
        position = "absolute",
        bottom = -600,  -- 初始在屏幕下方（不可见）
        left = 0, right = 0,
        height = 620,
        alignItems = "center",
        justifyContent = "flex-end",
        children = {
            -- 手机本体
            UI.Panel {
                id = "phoneBody",
                width = 280,
                height = 480,
                backgroundColor = { 20, 20, 30, 255 },
                borderRadius = 20,
                borderWidth = 3,
                borderColor = { 60, 60, 80, 255 },
                padding = 8,
                children = {
                    -- 状态栏
                    PhoneUI.CreateStatusBar(),
                    -- 内容区域
                    UI.Panel {
                        id = "phoneContent",
                        flexGrow = 1,
                        flexBasis = 0,
                        width = "100%",
                        backgroundColor = { 30, 30, 45, 255 },
                        borderRadius = 12,
                        overflow = "hidden",
                        children = {
                            PhoneUI.CreateHomeScreen(),
                            PhoneUI.CreateMapApp(),
                            PhoneUI.CreateScanApp(),
                            PhoneUI.CreatePayApp(),
                            PhoneUI.CreateFakeAppPage(),
                        }
                    },
                    -- 底部按钮
                    UI.Panel {
                        height = 32,
                        width = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Button {
                                text = "放下手机",
                                fontSize = 11,
                                height = 26,
                                backgroundColor = { 60, 60, 80, 255 },
                                onClick = function()
                                    PhoneUI.Close()
                                    if onEventCallback then onEventCallback("phone_close") end
                                end,
                            }
                        }
                    },
                    -- 广告覆盖层（绝对定位，覆盖在手机内容之上）
                    PhoneUI.CreateAdOverlay(),
                    -- 低电量警告覆盖层（绝对定位，覆盖在手机内容之上）
                    PhoneUI.CreateLowBatteryOverlay(),
                }
            },
            -- 手（握持手机底部的手掌）
            UI.Panel {
                id = "handGrip",
                width = 200,
                height = 120,
                alignItems = "center",
                children = {
                    -- 手腕/手臂
                    UI.Panel {
                        width = 80,
                        height = 120,
                        backgroundColor = { 220, 180, 150, 255 },
                        borderRadius = 20,
                    },
                    -- 左拇指（覆盖在手机左侧）
                    UI.Panel {
                        position = "absolute",
                        top = -12,
                        left = 40,
                        width = 22,
                        height = 40,
                        backgroundColor = { 210, 170, 140, 255 },
                        borderRadius = 10,
                    },
                    -- 右拇指区域
                    UI.Panel {
                        position = "absolute",
                        top = -12,
                        right = 40,
                        width = 22,
                        height = 40,
                        backgroundColor = { 210, 170, 140, 255 },
                        borderRadius = 10,
                    },
                }
            },
        }
    }

    -- 手机框架（全屏遮罩 + 滑动容器）
    phoneRoot = UI.Panel {
        id = "phoneFrame",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "flex-end",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 0 },  -- 初始透明，动画时渐变
        children = {
            phoneSlider,
        }
    }

    return phoneRoot
end

function PhoneUI.CreateStatusBar()
    return UI.Panel {
        id = "statusBar",
        height = 24,
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 8,
        children = {
            UI.Label {
                text = "22:47",
                fontSize = 10,
                fontColor = { 200, 200, 200, 255 },
            },
            UI.Label {
                id = "batteryLabel",
                text = "5%",
                fontSize = 10,
                fontColor = { 255, 60, 60, 255 },
            },
        }
    }
end

function PhoneUI.CreateHomeScreen()
    homePanel = UI.Panel {
        id = "homeScreen",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        padding = 16,
        gap = 12,
        children = {
            UI.Label {
                text = "主屏幕",
                fontSize = 13,
                fontColor = { 180, 180, 200, 255 },
                textAlign = "center",
            },
            -- App 图标行
            UI.Panel {
                flexDirection = "row",
                gap = 16,
                justifyContent = "center",
                flexWrap = "wrap",
                children = {
                    PhoneUI.AppIcon("地图", { 50, 180, 50, 255 }, function()
                        PhoneUI.OpenApp("map")
                    end),
                    PhoneUI.AppIcon("扫码", { 50, 100, 200, 255 }, function()
                        PhoneUI.OpenApp("scan")
                    end),
                    PhoneUI.AppIcon("支付", { 200, 120, 50, 255 }, function()
                        PhoneUI.OpenApp("pay")
                    end),
                }
            },
            -- 省电提示
            UI.Panel {
                marginTop = 20,
                padding = 10,
                backgroundColor = { 80, 30, 30, 200 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "电量极低！建议立即充电",
                        fontSize = 11,
                        fontColor = { 255, 200, 200, 255 },
                        textAlign = "center",
                    },
                }
            },
        }
    }
    return homePanel
end

function PhoneUI.AppIcon(name, color, onClick)
    return UI.Panel {
        width = 60, height = 72,
        alignItems = "center",
        gap = 4,
        children = {
            UI.Button {
                text = string.sub(name, 1, 3),
                width = 48, height = 48,
                fontSize = 14,
                backgroundColor = color,
                borderRadius = 12,
                onClick = function()
                    if onEventCallback then onEventCallback("app_open") end
                    onClick()
                end,
            },
            UI.Label {
                text = name,
                fontSize = 9,
                fontColor = { 180, 180, 200, 255 },
            },
        }
    }
end

function PhoneUI.CreateMapApp()
    mapPanel = UI.Panel {
        id = "mapApp",
        visible = false,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        padding = 10,
        gap = 8,
        backgroundColor = { 25, 35, 30, 255 },
        children = {
            -- 标题栏
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "附近充电点", fontSize = 13, fontColor = { 100, 255, 100, 255 } },
                    UI.Button {
                        text = "X",
                        width = 24, height = 24,
                        fontSize = 12,
                        backgroundColor = { 80, 40, 40, 255 },
                        onClick = function() PhoneUI.CloseApp() end,
                    },
                },
            },
            -- 地图内容（简化列表）
            UI.Panel {
                flexGrow = 1,
                gap = 6,
                children = {
                    PhoneUI.MapItem("共享充电宝柜", "80m", "可能可用", { 50, 200, 50, 255 }),
                    PhoneUI.MapItem("便利店", "150m", "营业中", { 200, 200, 50, 255 }),
                    PhoneUI.MapItem("墙壁插座", "220m", "未知状态", { 150, 150, 150, 255 }),
                    PhoneUI.MapItem("青年旅舍", "350m", "需认证", { 150, 100, 100, 255 }),
                }
            },
            -- 底部广告（小字）
            UI.Label {
                text = "广告：低电量焦虑？下载「电量守护」App",
                fontSize = 8,
                fontColor = { 150, 150, 150, 200 },
                textAlign = "center",
            },
        }
    }
    return mapPanel
end

function PhoneUI.MapItem(name, dist, status, color)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = 8,
        backgroundColor = { 40, 50, 45, 255 },
        borderRadius = 6,
        children = {
            UI.Panel {
                gap = 2,
                children = {
                    UI.Label { text = name, fontSize = 11, fontColor = { 220, 220, 220, 255 } },
                    UI.Label { text = status, fontSize = 9, fontColor = color },
                },
            },
            UI.Label { text = dist, fontSize = 11, fontColor = { 150, 150, 150, 255 } },
        }
    }
end

function PhoneUI.CreateScanApp()
    scanPanel = UI.Panel {
        id = "scanApp",
        visible = false,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        padding = 10,
        gap = 8,
        backgroundColor = { 20, 20, 35, 255 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Label { text = "扫码", fontSize = 15, fontColor = { 100, 150, 255, 255 } },
            -- 扫码说明
            UI.Panel {
                width = 180, height = 140,
                borderWidth = 2,
                borderColor = { 100, 150, 255, 150 },
                borderRadius = 8,
                justifyContent = "center",
                alignItems = "center",
                padding = 12,
                gap = 6,
                children = {
                    UI.Label {
                        text = "将摄像头对准\n充电宝柜上的二维码",
                        fontSize = 11,
                        fontColor = { 150, 150, 200, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = "移动鼠标对准 · 点击拍摄",
                        fontSize = 9,
                        fontColor = { 120, 120, 150, 200 },
                        textAlign = "center",
                    },
                },
            },
            UI.Button {
                text = "打开摄像头",
                variant = "primary",
                fontSize = 12,
                marginTop = 10,
                onClick = function()
                    if onEventCallback then onEventCallback("scan_qr") end
                end,
            },
            UI.Button {
                text = "返回",
                fontSize = 11,
                marginTop = 6,
                backgroundColor = { 60, 60, 80, 255 },
                onClick = function() PhoneUI.CloseApp() end,
            },
        }
    }
    return scanPanel
end

function PhoneUI.CreatePayApp()
    payPanel = UI.Panel {
        id = "payApp",
        visible = false,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        padding = 10,
        gap = 8,
        backgroundColor = { 30, 25, 20, 255 },
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "支付", fontSize = 13, fontColor = { 255, 180, 50, 255 } },
                    UI.Button {
                        text = "X",
                        width = 24, height = 24, fontSize = 12,
                        backgroundColor = { 80, 40, 40, 255 },
                        onClick = function() PhoneUI.CloseApp() end,
                    },
                },
            },
            UI.Label {
                id = "payBalance",
                text = "余额: ¥50.00",
                fontSize = 12,
                fontColor = { 200, 200, 200, 255 },
            },
            -- 支付项目
            UI.Panel {
                id = "payItems",
                flexGrow = 1,
                gap = 6,
            },
        }
    }
    return payPanel
end

function PhoneUI.CreateFakeAppPage()
    fakeAppPanel = UI.Panel {
        id = "fakeAppPage",
        visible = false,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        backgroundColor = { 245, 245, 250, 255 },
        padding = 12,
        gap = 10,
        children = {
            -- 顶部标题栏
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "<",
                        width = 28, height = 28,
                        fontSize = 14,
                        backgroundColor = { 220, 220, 230, 255 },
                        fontColor = { 60, 60, 60, 255 },
                        borderRadius = 14,
                        onClick = function()
                            PhoneUI.CloseFakeApp()
                        end,
                    },
                    UI.Label {
                        text = "应用市场",
                        fontSize = 13,
                        fontColor = { 40, 40, 40, 255 },
                    },
                    UI.Panel { width = 28 }, -- 占位
                },
            },
            -- App 信息区
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                padding = 12,
                backgroundColor = { 255, 255, 255, 255 },
                borderRadius = 10,
                children = {
                    -- App 图标
                    UI.Panel {
                        width = 52, height = 52,
                        backgroundColor = { 80, 200, 120, 255 },
                        borderRadius = 12,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "守",
                                fontSize = 20,
                                fontColor = { 255, 255, 255, 255 },
                            },
                        },
                    },
                    -- App 名称和信息
                    UI.Panel {
                        flexGrow = 1,
                        gap = 3,
                        children = {
                            UI.Label {
                                id = "fakeAppName",
                                text = "电量守护",
                                fontSize = 14,
                                fontColor = { 30, 30, 30, 255 },
                            },
                            UI.Label {
                                text = "生活工具 | 62.3MB",
                                fontSize = 9,
                                fontColor = { 130, 130, 140, 255 },
                            },
                            UI.Label {
                                text = "★★★★☆  4.2分",
                                fontSize = 9,
                                fontColor = { 255, 180, 0, 255 },
                            },
                        },
                    },
                },
            },
            -- 下载进度区
            UI.Panel {
                padding = 12,
                backgroundColor = { 255, 255, 255, 255 },
                borderRadius = 10,
                gap = 8,
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "fakeAppStatus",
                        text = "正在加载...",
                        fontSize = 12,
                        fontColor = { 60, 60, 60, 255 },
                    },
                    -- 进度条背景
                    UI.Panel {
                        width = "90%",
                        height = 12,
                        backgroundColor = { 230, 230, 235, 255 },
                        borderRadius = 6,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                id = "fakeAppProgressBar",
                                width = "0%",
                                height = "100%",
                                backgroundColor = { 80, 180, 80, 255 },
                                borderRadius = 6,
                            },
                        },
                    },
                    UI.Label {
                        id = "fakeAppPercent",
                        text = "0%",
                        fontSize = 10,
                        fontColor = { 100, 100, 110, 255 },
                    },
                },
            },
            -- 假评论区
            UI.Panel {
                flexGrow = 1,
                gap = 6,
                children = {
                    UI.Label {
                        text = "用户评价",
                        fontSize = 11,
                        fontColor = { 80, 80, 90, 255 },
                    },
                    UI.Panel {
                        padding = 8,
                        backgroundColor = { 255, 255, 255, 255 },
                        borderRadius = 8,
                        gap = 4,
                        children = {
                            UI.Label { text = "手机续航提升100%！", fontSize = 10, fontColor = { 60, 60, 70, 255 } },
                            UI.Label { text = "★★★★★ 绝对真实不骗人", fontSize = 9, fontColor = { 150, 150, 160, 255 } },
                        },
                    },
                    UI.Panel {
                        padding = 8,
                        backgroundColor = { 255, 255, 255, 255 },
                        borderRadius = 8,
                        gap = 4,
                        children = {
                            UI.Label { text = "下载了手机就变砖了", fontSize = 10, fontColor = { 60, 60, 70, 255 } },
                            UI.Label { text = "★☆☆☆☆ 已举报", fontSize = 9, fontColor = { 150, 150, 160, 255 } },
                        },
                    },
                },
            },
        }
    }
    return fakeAppPanel
end

function PhoneUI.CreateAdOverlay()
    adOverlay = UI.Panel {
        id = "adOverlay",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 200 },
        children = {
            UI.Panel {
                width = 260,
                padding = 16,
                backgroundColor = { 255, 255, 255, 255 },
                borderRadius = 12,
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Label {
                        id = "adTitle",
                        text = "恭喜！您获得新人礼包",
                        fontSize = 14,
                        fontColor = { 200, 50, 50, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "adBody",
                        text = "下载「电量守护」App\n首月会员仅¥29.99",
                        fontSize = 11,
                        fontColor = { 80, 80, 80, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Button {
                        text = "立即下载",
                        variant = "danger",
                        fontSize = 12,
                        width = "80%",
                        onClick = function()
                            -- 误点广告
                            if onEventCallback then onEventCallback("ad_misclick") end
                        end,
                    },
                    -- 极小关闭按钮
                    UI.Button {
                        id = "adCloseBtn",
                        text = "x",
                        position = "absolute",
                        top = 4, right = 4,
                        width = 18, height = 18,
                        fontSize = 9,
                        backgroundColor = { 200, 200, 200, 100 },
                        borderRadius = 9,
                        onClick = function()
                            PhoneUI.HideAd()
                            if onEventCallback then onEventCallback("ad_closed") end
                        end,
                    },
                },
            },
        }
    }
    return adOverlay
end

-- === 公开 API ===

-- 缓动函数：easeOutBack（带回弹，像拿起手机的感觉）
local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

-- 缓动函数：easeInBack（收回时加速）
local function easeInCubic(t)
    return t * t * t
end

function PhoneUI.Open()
    if not phoneRoot then return end
    phoneRoot:SetVisible(true)
    isVisible = true
    animState = "sliding_in"
    animProgress = 0
    animOffset = 600
    PhoneUI.ShowHome()
    -- 立即更新一次位置
    if phoneSlider then
        phoneSlider:SetStyle({ bottom = math.floor(-animOffset) })
    end
end

function PhoneUI.Close()
    if not phoneRoot then return end
    if animState == "hidden" or animState == "sliding_out" then return end
    animState = "sliding_out"
    animProgress = 0
    currentApp = nil
end

function PhoneUI.IsOpen()
    return isVisible
end

function PhoneUI.IsAnimating()
    return animState == "sliding_in" or animState == "sliding_out"
end

--- 立即关闭（无动画，用于切换到扫码等需要立即关闭的场景）
function PhoneUI.CloseInstant()
    if not phoneRoot then return end
    animState = "hidden"
    animProgress = 0
    animOffset = 600
    isVisible = false
    currentApp = nil
    phoneRoot:SetVisible(false)
    if phoneSlider then
        phoneSlider:SetStyle({ bottom = -600 })
    end
end

--- 每帧更新动画（必须在 main.lua 的 Update 中调用）
function PhoneUI.UpdateAnim(dt)
    if animState == "sliding_in" then
        animProgress = animProgress + dt / ANIM_DURATION
        if animProgress >= 1.0 then
            animProgress = 1.0
            animState = "visible"
        end
        local t = easeOutBack(animProgress)
        animOffset = 600 * (1 - t)  -- 从600→0
        if phoneSlider then
            phoneSlider:SetStyle({ bottom = math.floor(-animOffset) })
        end
        -- 背景渐暗
        local alpha = math.floor(150 * animProgress)
        if phoneRoot then
            phoneRoot:SetBackgroundColor({ 0, 0, 0, alpha })
        end

    elseif animState == "sliding_out" then
        animProgress = animProgress + dt / (ANIM_DURATION * 0.7)  -- 收回稍快
        if animProgress >= 1.0 then
            animProgress = 1.0
            animState = "hidden"
            isVisible = false
            if phoneRoot then
                phoneRoot:SetVisible(false)
            end
        end
        local t = easeInCubic(animProgress)
        animOffset = 600 * t  -- 从0→600
        if phoneSlider then
            phoneSlider:SetStyle({ bottom = math.floor(-animOffset) })
        end
        -- 背景渐亮
        local alpha = math.floor(150 * (1 - animProgress))
        if phoneRoot then
            phoneRoot:SetBackgroundColor({ 0, 0, 0, alpha })
        end
    end
end

function PhoneUI.GetCurrentApp()
    return currentApp
end

function PhoneUI.OpenApp(appName)
    currentApp = appName
    homePanel:SetVisible(false)
    if appName == "map" then
        mapPanel:SetVisible(true)
        scanPanel:SetVisible(false)
        payPanel:SetVisible(false)
    elseif appName == "scan" then
        mapPanel:SetVisible(false)
        scanPanel:SetVisible(true)
        payPanel:SetVisible(false)
    elseif appName == "pay" then
        mapPanel:SetVisible(false)
        scanPanel:SetVisible(false)
        payPanel:SetVisible(true)
    end
end

function PhoneUI.CloseApp()
    currentApp = nil
    if mapPanel then mapPanel:SetVisible(false) end
    if scanPanel then scanPanel:SetVisible(false) end
    if payPanel then payPanel:SetVisible(false) end
    PhoneUI.ShowHome()
end

function PhoneUI.ShowHome()
    if homePanel then homePanel:SetVisible(true) end
    if mapPanel then mapPanel:SetVisible(false) end
    if scanPanel then scanPanel:SetVisible(false) end
    if payPanel then payPanel:SetVisible(false) end
    currentApp = nil
end

function PhoneUI.ShowAd(title, body)
    if adOverlay then
        local titleLabel = adOverlay:FindById("adTitle")
        local bodyLabel = adOverlay:FindById("adBody")
        if titleLabel then titleLabel:SetText(title or "限时优惠！") end
        if bodyLabel then bodyLabel:SetText(body or "立即下载享受优惠") end
        adOverlay:SetVisible(true)
    end
end

function PhoneUI.HideAd()
    if adOverlay then
        adOverlay:SetVisible(false)
    end
end

function PhoneUI.UpdateBattery(percent)
    if phoneRoot then
        local label = phoneRoot:FindById("batteryLabel")
        if label then
            label:SetText(string.format("%.0f%%", percent))
        end
    end
end

function PhoneUI.UpdateBalance(amount)
    if phoneRoot then
        local label = phoneRoot:FindById("payBalance")
        if label then
            label:SetText(string.format("余额: ¥%.2f", amount))
        end
    end
end

-- === 假应用页面 API ===

--- 显示假应用页面（广告误点后跳转到此）
--- @param appName string 应用名称
--- @param battery number 当前电量（决定加载时间）
function PhoneUI.ShowFakeApp(appName, battery)
    if not fakeAppPanel then return end

    fakeAppName = appName or "电量守护"
    fakeAppProgress = 0
    fakeAppDownloading = false
    fakeAppLoading = true
    -- 低电量时加载时间更长（电量越低越卡）
    fakeAppLoadingTime = math.max(0.5, (5.0 - battery) * 0.6)
    -- 下载速度也受电量影响
    fakeAppDownloadSpeed = 8 + battery * 4  -- 电量5%时28%/s，电量1%时12%/s

    -- 隐藏广告覆盖层
    PhoneUI.HideAd()

    -- 隐藏其他面板，显示假应用
    if homePanel then homePanel:SetVisible(false) end
    if mapPanel then mapPanel:SetVisible(false) end
    if scanPanel then scanPanel:SetVisible(false) end
    if payPanel then payPanel:SetVisible(false) end

    -- 更新名称
    local nameLabel = fakeAppPanel:FindById("fakeAppName")
    if nameLabel then nameLabel:SetText(fakeAppName) end

    -- 重置进度条显示
    local statusLabel = fakeAppPanel:FindById("fakeAppStatus")
    if statusLabel then statusLabel:SetText("正在加载...") end
    local progressBar = fakeAppPanel:FindById("fakeAppProgressBar")
    if progressBar then progressBar:SetWidth("0%") end
    local percentLabel = fakeAppPanel:FindById("fakeAppPercent")
    if percentLabel then percentLabel:SetText("连接中...") end

    fakeAppPanel:SetVisible(true)
    currentApp = "fakeapp"
end

--- 关闭假应用页面，返回主屏幕
function PhoneUI.CloseFakeApp()
    if fakeAppPanel then
        fakeAppPanel:SetVisible(false)
    end
    fakeAppDownloading = false
    fakeAppLoading = false
    fakeAppProgress = 0
    PhoneUI.ShowHome()
end

--- 更新假应用下载进度（每帧调用）
--- @param dt number 帧间隔
--- @return boolean 是否仍在假应用页面
function PhoneUI.UpdateFakeApp(dt)
    if not fakeAppPanel or not fakeAppPanel:IsVisible() then
        return false
    end

    -- 阶段1：加载中（转圈）
    if fakeAppLoading then
        fakeAppLoadingTime = fakeAppLoadingTime - dt
        if fakeAppLoadingTime <= 0 then
            fakeAppLoading = false
            fakeAppDownloading = true
            -- 切换到下载状态
            local statusLabel = fakeAppPanel:FindById("fakeAppStatus")
            if statusLabel then statusLabel:SetText("下载中...") end
        else
            -- 更新加载提示（模拟卡顿）
            local dots = string.rep(".", math.floor(fakeAppLoadingTime * 3) % 4)
            local statusLabel = fakeAppPanel:FindById("fakeAppStatus")
            if statusLabel then statusLabel:SetText("正在加载" .. dots) end
        end
        return true
    end

    -- 阶段2：下载中
    if fakeAppDownloading then
        fakeAppProgress = fakeAppProgress + fakeAppDownloadSpeed * dt
        if fakeAppProgress > 100 then fakeAppProgress = 100 end

        -- 更新 UI
        local progressBar = fakeAppPanel:FindById("fakeAppProgressBar")
        if progressBar then
            progressBar:SetWidth(tostring(math.floor(fakeAppProgress)) .. "%")
        end
        local percentLabel = fakeAppPanel:FindById("fakeAppPercent")
        if percentLabel then
            percentLabel:SetText(string.format("%.0f%%  (%.1fMB/62.3MB)", fakeAppProgress, fakeAppProgress * 0.623))
        end

        -- 下载到100%后不自动关闭，玩家必须手动关
        if fakeAppProgress >= 100 then
            fakeAppDownloading = false
            local statusLabel = fakeAppPanel:FindById("fakeAppStatus")
            if statusLabel then statusLabel:SetText("安装中...请稍候") end
        end
        return true
    end

    return true  -- 还在页面上（安装完了也得手动关）
end

--- 是否正在显示假应用
function PhoneUI.IsFakeAppVisible()
    return fakeAppPanel ~= nil and fakeAppPanel:IsVisible()
end

-- ====================================================================
-- 低电量警告弹窗
-- ====================================================================
local lowBatteryOverlay = nil

function PhoneUI.CreateLowBatteryOverlay()
    lowBatteryOverlay = UI.Panel {
        id = "lowBatteryOverlay",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 240,
                padding = 16,
                backgroundColor = { 40, 10, 10, 255 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 255, 60, 60, 255 },
                alignItems = "center",
                gap = 10,
                children = {
                    -- 电量图标（红色）
                    UI.Label {
                        text = "⚠",
                        fontSize = 28,
                        fontColor = { 255, 50, 50, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "电量不足",
                        fontSize = 16,
                        fontColor = { 255, 80, 80, 255 },
                        textAlign = "center",
                        fontWeight = "bold",
                    },
                    UI.Label {
                        id = "lowBatteryMsg",
                        text = "手机将在 30 秒内关机",
                        fontSize = 12,
                        fontColor = { 255, 200, 200, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    -- 倒计时显示
                    UI.Label {
                        id = "lowBatteryCountdown",
                        text = "30",
                        fontSize = 36,
                        fontColor = { 255, 50, 50, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "快去找充电的地方！",
                        fontSize = 11,
                        fontColor = { 200, 200, 200, 255 },
                        textAlign = "center",
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "我知道了",
                        fontSize = 12,
                        width = "80%",
                        height = 30,
                        backgroundColor = { 180, 40, 40, 255 },
                        borderRadius = 6,
                        onClick = function()
                            PhoneUI.HideLowBatteryWarning()
                        end,
                    },
                }
            }
        }
    }
    return lowBatteryOverlay
end

--- 显示低电量警告
function PhoneUI.ShowLowBatteryWarning()
    if lowBatteryOverlay then
        lowBatteryOverlay:SetVisible(true)
    end
end

--- 隐藏低电量警告
function PhoneUI.HideLowBatteryWarning()
    if lowBatteryOverlay then
        lowBatteryOverlay:SetVisible(false)
    end
end

--- 更新倒计时数字
function PhoneUI.UpdateLowBatteryCountdown(seconds)
    if lowBatteryOverlay then
        local label = lowBatteryOverlay:FindById("lowBatteryCountdown")
        if label then
            label:SetText(string.format("%d", math.ceil(seconds)))
        end
    end
end

--- 低电量警告是否可见
function PhoneUI.IsLowBatteryVisible()
    return lowBatteryOverlay ~= nil and lowBatteryOverlay:IsVisible()
end

return PhoneUI
