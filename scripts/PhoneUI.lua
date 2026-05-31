-- ====================================================================
-- PhoneUI.lua - 手机界面系统
-- ====================================================================

local Config = require("Config")
local UI = require("urhox-libs/UI")
local DiagLog = require("DiagLog")

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

-- 地图 App 状态
local mapListPanel = nil       -- 地图列表容器引用
local cachedPlayerX = 0        -- 缓存玩家世界X坐标

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
    -- 地图列表容器（动态刷新）
    mapListPanel = UI.Panel {
        id = "mapList",
        flexGrow = 1,
        gap = 5,
        overflow = "scroll",
    }

    mapPanel = UI.Panel {
        id = "mapApp",
        visible = false,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        padding = 10,
        gap = 6,
        backgroundColor = { 20, 28, 25, 255 },
        children = {
            -- 标题栏
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "附近充电点", fontSize = 13, fontColor = { 80, 230, 80, 255 } },
                    UI.Button {
                        text = "X",
                        width = 24, height = 24,
                        fontSize = 12,
                        backgroundColor = { 80, 40, 40, 255 },
                        onClick = function() PhoneUI.CloseApp() end,
                    },
                },
            },
            -- 玩家位置指示
            UI.Panel {
                id = "mapPlayerPos",
                padding = 6,
                backgroundColor = { 30, 50, 40, 200 },
                borderRadius = 4,
                children = {
                    UI.Label { id = "mapPosLabel", text = "当前位置: --", fontSize = 9, fontColor = { 130, 200, 130, 255 } },
                },
            },
            -- 动态列表
            mapListPanel,
            -- 底部广告
            UI.Label {
                text = "广告：充电困难？下载「闪电充」全城找桩",
                fontSize = 8,
                fontColor = { 140, 140, 140, 200 },
                textAlign = "center",
            },
        }
    }
    return mapPanel
end

--- 刷新地图数据（每次打开地图App时调用）
---@param playerX number 玩家世界X坐标
function PhoneUI.RefreshMapData(playerX)
    if not mapListPanel then return end
    mapListPanel:ClearChildren()

    -- 更新玩家位置标签
    local posLabel = mapPanel:FindById("mapPosLabel")
    if posLabel then
        local posStr = string.format("当前位置: %.0fm", (playerX or 0))
        posLabel:SetText(posStr)
    end

    -- 获取世界建筑/交互物数据
    local WorldRenderer = require("WorldRenderer")
    local PowerbankSystem = require("PowerbankSystem")
    local items = WorldRenderer.GetInteractables()
    if not items then return end

    -- 按距离排序
    local sortedItems = {}
    for _, item in ipairs(items) do
        -- 只显示有意义的地点（充电宝柜、网吧、杂货铺、插座）
        if item.type == "powerbank" or item.type == "internet_cafe"
            or item.type == "shop" or item.type == "outlet" then
            local dist = math.abs((item.x or 0) - (playerX or 0))
            table.insert(sortedItems, { item = item, dist = dist })
        end
    end
    table.sort(sortedItems, function(a, b) return a.dist < b.dist end)

    -- 生成列表项（最多显示8个）
    local count = math.min(#sortedItems, 8)
    for i = 1, count do
        local entry = sortedItems[i]
        local item = entry.item
        local dist = entry.dist
        local distStr = string.format("%.0fm", dist)

        -- 确定名称、状态、颜色
        local name, status, color = PhoneUI.GetMapItemInfo(item)

        mapListPanel:AddChild(PhoneUI.MapItem(name, distStr, status, color))
    end

    -- 如果列表为空，显示提示
    if count == 0 then
        mapListPanel:AddChild(UI.Label {
            text = "附近无充电设施",
            fontSize = 10,
            fontColor = { 150, 150, 150, 200 },
            textAlign = "center",
            marginTop = 20,
        })
    end
end

--- 根据交互物类型获取地图显示信息
function PhoneUI.GetMapItemInfo(item)
    local PowerbankSystem = require("PowerbankSystem")

    if item.type == "powerbank" then
        local stationId = item.stationId
        local station = stationId and PowerbankSystem.GetById(stationId)
        if station then
            local stateLabel = PowerbankSystem.GetStateLabel(station.state)
            if station.state == PowerbankSystem.State.AVAILABLE then
                return "充电宝柜", stateLabel, { 50, 230, 50, 255 }
            elseif station.state == PowerbankSystem.State.EMPTY then
                return "充电宝柜", stateLabel, { 200, 200, 50, 255 }
            else
                return "充电宝柜", stateLabel, { 150, 60, 60, 255 }
            end
        end
        return "充电宝柜", "状态未知", { 150, 150, 150, 255 }
    elseif item.type == "internet_cafe" then
        return "网吧 (有充电)", "可进入", { 100, 150, 255, 255 }
    elseif item.type == "shop" then
        return "杂货铺", "营业中", { 200, 180, 50, 255 }
    elseif item.type == "outlet" then
        return "墙壁插座", "可能有电", { 180, 130, 50, 255 }
    end
    return item.label or "未知", "", { 150, 150, 150, 255 }
end

function PhoneUI.MapItem(name, dist, status, color)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = 7,
        backgroundColor = { 35, 48, 42, 255 },
        borderRadius = 5,
        children = {
            UI.Panel {
                gap = 2,
                flexShrink = 1,
                children = {
                    UI.Label { text = name, fontSize = 11, fontColor = { 220, 220, 220, 255 } },
                    UI.Label { text = status, fontSize = 9, fontColor = color },
                },
            },
            UI.Label { text = dist, fontSize = 10, fontColor = { 130, 130, 130, 255 } },
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
            -- 贷款入口（醒目的大按钮）
            UI.Panel {
                padding = 8,
                backgroundColor = { 180, 50, 20, 240 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 255, 100, 50, 255 },
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label {
                        text = "💰 极速贷款",
                        fontSize = 14,
                        fontColor = { 255, 220, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "3秒到账 · 最高200元",
                        fontSize = 9,
                        fontColor = { 255, 200, 180, 255 },
                        textAlign = "center",
                    },
                    UI.Button {
                        text = "立即申请",
                        fontSize = 11,
                        width = "80%",
                        height = 28,
                        backgroundColor = { 255, 80, 30, 255 },
                        borderRadius = 14,
                        onClick = function()
                            DiagLog.Log("事件", "「立即申请」按钮被点击, callback存在=" .. tostring(onEventCallback ~= nil))
                            if onEventCallback then onEventCallback("loan_start") end
                        end,
                    },
                },
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
            -- Popup 弹窗（默认显示）
            UI.Panel {
                id = "adPopupCard",
                width = 250,
                padding = 14,
                backgroundColor = { 255, 255, 255, 255 },
                borderRadius = 12,
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        id = "adTitle",
                        text = "限时优惠！",
                        fontSize = 14,
                        fontColor = { 200, 50, 50, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "adBody",
                        text = "立即下载享受优惠",
                        fontSize = 11,
                        fontColor = { 80, 80, 80, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    -- 大且鲜艳的"接受"按钮（误导性）
                    UI.Button {
                        id = "adAcceptBtn",
                        text = "立即前往",
                        fontSize = 13,
                        width = "85%",
                        height = 36,
                        backgroundColor = { 255, 60, 30, 255 },
                        borderRadius = 18,
                        fontColor = { 255, 255, 255, 255 },
                        onClick = function()
                            if onEventCallback then onEventCallback("ad_misclick") end
                        end,
                    },
                    -- 小且灰的"拒绝"按钮
                    UI.Button {
                        id = "adRejectBtn",
                        text = "残忍拒绝",
                        fontSize = 9,
                        width = "50%",
                        height = 22,
                        backgroundColor = { 200, 200, 200, 80 },
                        fontColor = { 140, 140, 140, 255 },
                        borderRadius = 4,
                        onClick = function()
                            print("[PhoneUI] Popup '残忍拒绝' clicked → HideAd + ad_closed")
                            PhoneUI.HideAd()
                            if onEventCallback then onEventCallback("ad_closed") end
                        end,
                    },
                    -- 延迟出现的极小x关闭（position absolute）
                    UI.Button {
                        id = "adCloseBtn",
                        text = "×",
                        visible = false,
                        position = "absolute",
                        top = 2, right = 2,
                        width = 16, height = 16,
                        fontSize = 9,
                        backgroundColor = { 200, 200, 200, 60 },
                        fontColor = { 160, 160, 160, 255 },
                        borderRadius = 8,
                        onClick = function()
                            PhoneUI.HideAd()
                            if onEventCallback then onEventCallback("ad_closed") end
                        end,
                    },
                },
            },
            -- Fullscreen 全屏广告
            UI.Panel {
                id = "adFullscreen",
                visible = false,
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 20, 20, 40, 255 },
                children = {
                    UI.Label {
                        id = "adFullTitle",
                        text = "广告",
                        fontSize = 18,
                        fontColor = { 255, 220, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "adFullBody",
                        text = "精彩内容加载中...",
                        fontSize = 12,
                        fontColor = { 200, 200, 220, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                        marginTop = 10,
                    },
                    -- 大按钮（误导）
                    UI.Button {
                        id = "adFullAccept",
                        text = "查看详情",
                        fontSize = 13,
                        width = "70%",
                        height = 36,
                        marginTop = 20,
                        backgroundColor = { 255, 80, 30, 255 },
                        borderRadius = 18,
                        fontColor = { 255, 255, 255, 255 },
                        onClick = function()
                            if onEventCallback then onEventCallback("ad_misclick") end
                        end,
                    },
                    -- 跳过按钮（右上角，延迟出现）
                    UI.Button {
                        id = "adSkipBtn",
                        text = "跳过 3s",
                        visible = false,
                        position = "absolute",
                        top = 8, right = 8,
                        width = 56, height = 22,
                        fontSize = 9,
                        backgroundColor = { 80, 80, 80, 180 },
                        fontColor = { 200, 200, 200, 255 },
                        borderRadius = 11,
                        onClick = function()
                            print("[PhoneUI] Fullscreen '跳过' clicked → HideAd + ad_closed")
                            PhoneUI.HideAd()
                            if onEventCallback then onEventCallback("ad_closed") end
                        end,
                    },
                },
            },
            -- Banner 横幅广告（顶部，状态栏下方）
            UI.Panel {
                id = "adBanner",
                visible = false,
                position = "absolute",
                top = 28, left = 8, right = 8,
                height = 36,
                backgroundColor = { 255, 245, 230, 250 },
                borderRadius = 6,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingHorizontal = 8,
                children = {
                    UI.Label {
                        id = "adBannerIcon",
                        text = "🎮",
                        fontSize = 12,
                        width = 18,
                    },
                    UI.Label {
                        id = "adBannerText",
                        text = "广告文案",
                        fontSize = 9,
                        fontColor = { 80, 60, 30, 255 },
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Button {
                        text = "×",
                        width = 18, height = 18,
                        fontSize = 9,
                        backgroundColor = { 180, 170, 150, 120 },
                        borderRadius = 9,
                        onClick = function()
                            print("[PhoneUI] Banner × clicked → HideAd + ad_closed")
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
        -- 打开地图时动态刷新数据
        PhoneUI.RefreshMapData(cachedPlayerX)
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

--- 设置玩家世界位置（main.lua 每帧或打开手机时调用）
function PhoneUI.SetPlayerPosition(x)
    cachedPlayerX = x or 0
end

function PhoneUI.CloseApp()
    currentApp = nil
    if mapPanel then mapPanel:SetVisible(false) end
    if scanPanel then scanPanel:SetVisible(false) end
    if payPanel then payPanel:SetVisible(false) end
    PhoneUI.ShowHome()
end

--- 隐藏支付面板（贷款流程激活时调用，防止底层按钮干扰）
function PhoneUI.HidePayPanel()
    DiagLog.Log("页面", "隐藏支付面板(payPanel), payPanel存在=" .. tostring(payPanel ~= nil))
    if payPanel then payPanel:SetVisible(false) end
end

--- 显示支付面板（贷款流程结束时恢复）
function PhoneUI.ShowPayPanel()
    DiagLog.Log("页面", "显示支付面板(payPanel), payPanel存在=" .. tostring(payPanel ~= nil))
    if payPanel then payPanel:SetVisible(true) end
end

function PhoneUI.ShowHome()
    if homePanel then homePanel:SetVisible(true) end
    if mapPanel then mapPanel:SetVisible(false) end
    if scanPanel then scanPanel:SetVisible(false) end
    if payPanel then payPanel:SetVisible(false) end
    currentApp = nil
end

--- 显示广告（支持多种类型）
--- @param adData table {type="popup"|"fullscreen"|"banner", content={title,body}, acceptText, rejectText, bannerText}
function PhoneUI.ShowAd(adData)
    if not adOverlay then
        print("[PhoneUI] ShowAd FAILED: adOverlay is nil!")
        return
    end
    print("[PhoneUI] ShowAd called, type=" .. tostring(adData and adData.type or "nil"))

    -- 兼容旧接口：如果传入字符串参数
    if type(adData) == "string" then
        adData = { type = "popup", content = { title = adData, body = "" }, acceptText = "立即前往", rejectText = "残忍拒绝" }
    end
    if not adData then
        adData = { type = "popup", content = { title = "限时优惠！", body = "立即下载享受优惠" }, acceptText = "立即前往", rejectText = "残忍拒绝" }
    end

    local adType = adData.type or "popup"

    -- 隐藏所有子类型
    local popupCard = adOverlay:FindById("adPopupCard")
    local fullscreen = adOverlay:FindById("adFullscreen")
    local banner = adOverlay:FindById("adBanner")
    if popupCard then popupCard:SetVisible(false) end
    if fullscreen then fullscreen:SetVisible(false) end
    if banner then banner:SetVisible(false) end

    -- 重置关闭按钮/跳过按钮
    local closeBtn = adOverlay:FindById("adCloseBtn")
    local skipBtn = adOverlay:FindById("adSkipBtn")
    if closeBtn then closeBtn:SetVisible(false) end
    if skipBtn then skipBtn:SetVisible(false) end

    -- 重置 pointerEvents（popup/fullscreen阻挡，banner穿透）
    adOverlay:SetProp("pointerEvents", "auto")

    if adType == "popup" then
        -- 弹窗广告
        if popupCard then popupCard:SetVisible(true) end
        local titleL = adOverlay:FindById("adTitle")
        local bodyL = adOverlay:FindById("adBody")
        local acceptBtn = adOverlay:FindById("adAcceptBtn")
        local rejectBtn = adOverlay:FindById("adRejectBtn")
        if titleL then titleL:SetText(adData.content and adData.content.title or "限时优惠！") end
        if bodyL then bodyL:SetText(adData.content and adData.content.body or "立即下载享受优惠") end
        if acceptBtn then acceptBtn:SetText(adData.acceptText or "立即前往") end
        if rejectBtn then rejectBtn:SetText(adData.rejectText or "残忍拒绝") end
        -- 背景半透明
        adOverlay:SetBackgroundColor({ 0, 0, 0, 200 })

    elseif adType == "fullscreen" then
        -- 全屏广告
        if fullscreen then fullscreen:SetVisible(true) end
        local titleL = adOverlay:FindById("adFullTitle")
        local bodyL = adOverlay:FindById("adFullBody")
        local acceptBtn = adOverlay:FindById("adFullAccept")
        if titleL then titleL:SetText(adData.content and adData.content.title or "广告") end
        if bodyL then bodyL:SetText(adData.content and adData.content.body or "") end
        if acceptBtn then acceptBtn:SetText(adData.acceptText or "查看详情") end
        -- 全屏不需要背景（自己覆盖整个屏幕）
        adOverlay:SetBackgroundColor({ 0, 0, 0, 0 })

    elseif adType == "banner" then
        -- 横幅广告
        if banner then banner:SetVisible(true) end
        local bannerText = adOverlay:FindById("adBannerText")
        if bannerText then bannerText:SetText(adData.bannerText or "广告") end
        -- 横幅不需要遮罩背景；overlay自身不拦截但子元素（banner关闭按钮）仍可点击
        adOverlay:SetBackgroundColor({ 0, 0, 0, 0 })
        adOverlay:SetProp("pointerEvents", "box-none")
    end

    -- 记录当前广告类型（用于延迟显示逻辑）
    PhoneUI._currentAdType = adType
    PhoneUI._adTimer = 0

    adOverlay:SetVisible(true)
end

function PhoneUI.HideAd()
    if adOverlay then
        adOverlay:SetVisible(false)
    end
    PhoneUI._currentAdType = nil
    PhoneUI._adTimer = 0
end

--- 更新广告计时器（用于延迟显示关闭/跳过按钮）
function PhoneUI.UpdateAd(dt)
    if not adOverlay or not adOverlay:IsVisible() then return end
    if not PhoneUI._currentAdType then return end

    PhoneUI._adTimer = (PhoneUI._adTimer or 0) + dt

    if PhoneUI._currentAdType == "popup" then
        -- 1.5秒后显示x关闭按钮
        if PhoneUI._adTimer >= 1.5 then
            local closeBtn = adOverlay:FindById("adCloseBtn")
            if closeBtn and not closeBtn:IsVisible() then
                closeBtn:SetVisible(true)
            end
        end
    elseif PhoneUI._currentAdType == "fullscreen" then
        -- 3秒后显示跳过按钮
        local skipBtn = adOverlay:FindById("adSkipBtn")
        if skipBtn then
            if PhoneUI._adTimer >= 3.0 then
                if not skipBtn:IsVisible() then
                    skipBtn:SetVisible(true)
                    skipBtn:SetText("跳过")
                end
            else
                local remaining = math.ceil(3.0 - PhoneUI._adTimer)
                skipBtn:SetVisible(true)
                skipBtn:SetText(remaining .. "s后跳过")
                -- 在倒计时期间禁用点击（通过设置灰色提示即可，按钮onClick里做判定）
            end
        end
    end
    -- banner不需要计时逻辑（有x按钮即可关闭）
end

--- 广告是否可见
function PhoneUI.IsAdVisible()
    return adOverlay ~= nil and adOverlay:IsVisible()
end

--- 广告是否阻挡操作（popup/fullscreen阻挡，banner不阻挡）
function PhoneUI.IsAdBlocking()
    if not adOverlay or not adOverlay:IsVisible() then return false end
    local t = PhoneUI._currentAdType
    return t == "popup" or t == "fullscreen"
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

--- 获取手机内容区域的屏幕逻辑坐标（用于 NanoVG overlay 裁剪）
--- @param screenW number 屏幕逻辑宽度
--- @param screenH number 屏幕逻辑高度
--- @return table|nil {x, y, w, h} 手机内容区域坐标，手机不可见时返回nil
function PhoneUI.GetPhoneContentRect(screenW, screenH)
    if not isVisible or animState == "hidden" then return nil end
    -- 手机布局常量:
    --   phoneSlider: bottom=0 (visible), height=620, full width, alignItems=center, justifyContent=flex-end
    --   phoneBody: width=280, height=480, padding=8
    --   statusBar: height=24
    --   phoneContent: flexGrow=1 (fills remaining)
    --   bottomButtons: height=32
    --   handGrip: height=120 (below phoneBody)
    -- 计算（phoneSlider justifyContent=flex-end，内容从底部向上排列）:
    --   handGrip bottom = screenH - animOffset
    --   phoneBody bottom = screenH - animOffset - 120
    --   phoneBody top = screenH - animOffset - 120 - 480 = screenH - animOffset - 600
    local phoneBodyTop = screenH - animOffset - 600
    local phoneBodyLeft = (screenW - 280) / 2
    -- phoneContent 在 phoneBody 内部:
    --   top offset: padding(8) + statusBar(24) = 32
    --   bottom offset: padding(8) + bottomButtons(32) = 40
    local contentX = phoneBodyLeft + 8
    local contentY = phoneBodyTop + 8 + 24
    local contentW = 280 - 16  -- 264
    local contentH = 480 - 8 - 24 - 32 - 8  -- 408
    return { x = contentX, y = contentY, w = contentW, h = contentH }
end

return PhoneUI
