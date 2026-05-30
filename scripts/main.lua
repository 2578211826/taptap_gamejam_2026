-- ====================================================================
-- main.lua - 《完蛋了，手机没电了》主入口
-- ====================================================================
-- 一个 48h Game Jam 荒诞压力游戏
-- 玩家手机只剩5%电量，需要在城市中找到充电方式
-- ====================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local WorldRenderer = require("WorldRenderer")
local PhoneUI = require("PhoneUI")
local EventSystem = require("EventSystem")
local ScanMiniGame = require("ScanMiniGame")

-- ====================================================================
-- 全局状态
-- ====================================================================
local nvg = nil
local screenW, screenH = 0, 0
local gs = nil  -- GameState
local uiRoot = nil

-- HUD 引用
local batteryBar = nil
local interactHint = nil
local messageBox = nil
local endingPanel = nil

-- ====================================================================
-- 生命周期
-- ====================================================================
function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    local graphics = GetGraphics()
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()

    -- NanoVG
    nvg = nvgCreate(1)
    if not nvg then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/MiSans-Regular.ttf")

    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化游戏状态
    gs = GameState.New()
    GameState.RandomizeWorld(gs)

    -- 初始化世界
    WorldRenderer.Init(screenW, screenH)
    gs.playerY = WorldRenderer.GetGroundY()

    -- 初始化扫码小游戏
    ScanMiniGame.Init(nvg, screenW, screenH)

    -- 初始化手机 UI
    PhoneUI.Init(HandlePhoneEvent)

    -- 创建 UI
    CreateGameUI()

    -- 订阅事件
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")

    -- 显示开始菜单
    ShowMenu()

    print("=== 游戏启动: " .. Config.Title .. " ===")
end

function Stop()
    UI.Shutdown()
    if nvg then
        nvgDelete(nvg)
        nvg = nil
    end
end

-- ====================================================================
-- UI 构建
-- ====================================================================
function CreateGameUI()
    local phonePanel, adPanel = PhoneUI.CreateUI()

    uiRoot = UI.Panel {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- Layer 1: HUD（电量条 + 操作提示，最底层）
            CreateHUD(),
            -- Layer 2: 常驻操作提示（底部）
            CreateActionHints(),
            -- Layer 3: 手机界面
            phonePanel,
            -- Layer 4: 广告覆盖（在手机之上）
            adPanel,
            -- Layer 5: 消息框（在手机和广告之上，确保始终可见）
            CreateMessageBox(),
            -- Layer 6: 结局面板
            CreateEndingPanel(),
            -- Layer 7: 开始菜单（最顶层）
            CreateMenuPanel(),
        }
    }

    UI.SetRoot(uiRoot)
end

function CreateHUD()
    return UI.Panel {
        id = "hud",
        position = "absolute",
        top = 8, left = 8, right = 8,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        pointerEvents = "none",
        children = {
            -- 电量显示
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                padding = 6,
                backgroundColor = { 0, 0, 0, 160 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "电量",
                        fontSize = 11,
                        fontColor = { 200, 200, 200, 255 },
                    },
                    UI.Panel {
                        width = 80, height = 16,
                        backgroundColor = { 40, 40, 50, 255 },
                        borderRadius = 4,
                        borderWidth = 1,
                        borderColor = { 100, 100, 120, 255 },
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                id = "batteryFill",
                                width = "100%",
                                height = "100%",
                                backgroundColor = { 255, 50, 50, 255 },
                                borderRadius = 3,
                            }
                        }
                    },
                    UI.Label {
                        id = "batteryText",
                        text = "5%",
                        fontSize = 11,
                        fontColor = { 255, 80, 80, 255 },
                    },
                }
            },
            -- 移动提示（简化）
            UI.Panel {
                padding = 6,
                backgroundColor = { 0, 0, 0, 160 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "AD移动 空格跳",
                        fontSize = 9,
                        fontColor = { 150, 150, 170, 255 },
                    },
                }
            },
        }
    }
end

function CreateActionHints()
    return UI.Panel {
        id = "actionHints",
        position = "absolute",
        bottom = 12,
        left = 12,
        gap = 6,
        pointerEvents = "none",
        children = {
            -- [F] 交互 行
            UI.Panel {
                id = "hintF",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                padding = 6,
                paddingHorizontal = 10,
                backgroundColor = { 20, 20, 35, 180 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 60, 60, 80, 150 },
                children = {
                    UI.Label {
                        id = "hintFKey",
                        text = "[F]",
                        fontSize = 12,
                        fontColor = { 140, 140, 160, 255 },
                    },
                    UI.Label {
                        id = "hintFText",
                        text = "交互",
                        fontSize = 11,
                        fontColor = { 140, 140, 160, 255 },
                    },
                },
            },
            -- [Tab] 打开手机 行
            UI.Panel {
                id = "hintTab",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                padding = 6,
                paddingHorizontal = 10,
                backgroundColor = { 20, 20, 35, 180 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 60, 60, 80, 150 },
                children = {
                    UI.Label {
                        id = "hintTabKey",
                        text = "[Tab]",
                        fontSize = 12,
                        fontColor = { 140, 140, 160, 255 },
                    },
                    UI.Label {
                        id = "hintTabText",
                        text = "打开手机",
                        fontSize = 11,
                        fontColor = { 140, 140, 160, 255 },
                    },
                },
            },
        }
    }
end

function CreateMessageBox()
    return UI.Panel {
        id = "messageBox",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 150 },
        children = {
            UI.Panel {
                width = 300,
                padding = 20,
                backgroundColor = { 35, 35, 50, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 80, 120, 200 },
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "msgTitle",
                        text = "提示",
                        fontSize = 14,
                        fontColor = { 255, 220, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "msgBody",
                        text = "",
                        fontSize = 12,
                        fontColor = { 200, 200, 220, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Button {
                        id = "msgBtn",
                        text = "确定",
                        variant = "primary",
                        fontSize = 12,
                        onClick = function()
                            HideMessage()
                        end,
                    },
                }
            }
        }
    }
end

function CreateEndingPanel()
    return UI.Panel {
        id = "endingPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 220 },
        children = {
            UI.Panel {
                width = 320,
                padding = 24,
                backgroundColor = { 25, 25, 40, 255 },
                borderRadius = 16,
                borderWidth = 2,
                borderColor = { 80, 80, 120, 200 },
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "endTitle",
                        text = "游戏结束",
                        fontSize = 18,
                        fontColor = { 255, 100, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "endSubtitle",
                        text = "",
                        fontSize = 12,
                        fontColor = { 200, 200, 220, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Panel {
                        id = "endStats",
                        gap = 4,
                        width = "100%",
                        marginTop = 8,
                    },
                    UI.Button {
                        text = "再来一局",
                        variant = "primary",
                        fontSize = 13,
                        marginTop = 8,
                        onClick = function()
                            RestartGame()
                        end,
                    },
                }
            }
        }
    }
end

function CreateMenuPanel()
    return UI.Panel {
        id = "menuPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 10, 8, 25, 250 },
        children = {
            UI.Panel {
                width = 320,
                padding = 32,
                gap = 16,
                alignItems = "center",
                backgroundColor = { 20, 18, 35, 255 },
                borderRadius = 20,
                borderWidth = 1,
                borderColor = { 60, 60, 100, 200 },
                children = {
                    UI.Label {
                        text = "完蛋了",
                        fontSize = 28,
                        fontColor = { 255, 80, 80, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "手机没电了",
                        fontSize = 22,
                        fontColor = { 255, 200, 50, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "你的手机只剩5%电量\n在这座疯狂的城市里\n找到充电方式吧",
                        fontSize = 12,
                        fontColor = { 180, 180, 200, 255 },
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "开始游戏",
                        variant = "primary",
                        fontSize = 14,
                        width = 180,
                        height = 44,
                        onClick = function()
                            StartGame()
                        end,
                    },
                    UI.Label {
                        text = "AD移动 | 空格跳跃 | Tab打开手机 | F交互",
                        fontSize = 9,
                        fontColor = { 120, 120, 150, 255 },
                        textAlign = "center",
                    },
                }
            }
        }
    }
end

-- ====================================================================
-- 游戏流程控制
-- ====================================================================
function ShowMenu()
    gs.phase = Config.State.MENU
    local menu = uiRoot:FindById("menuPanel")
    if menu then menu:SetVisible(true) end
end

function StartGame()
    local menu = uiRoot:FindById("menuPanel")
    if menu then menu:SetVisible(false) end
    local ending = uiRoot:FindById("endingPanel")
    if ending then ending:SetVisible(false) end

    GameState.Reset(gs)
    GameState.RandomizeWorld(gs)
    gs.phase = Config.State.PLAYING
    gs.playerX = 200
    gs.playerY = WorldRenderer.GetGroundY()

    WorldRenderer.Init(screenW, screenH)
    gs.playerY = WorldRenderer.GetGroundY()

    print("游戏开始！电量: 5%")
end

function RestartGame()
    StartGame()
end

function TriggerEnding(endingType, reason)
    gs.phase = Config.State.ENDING
    gs.ending = endingType
    gs.endingReason = reason

    PhoneUI.Close()

    local panel = uiRoot:FindById("endingPanel")
    if not panel then return end
    panel:SetVisible(true)

    local title = panel:FindById("endTitle")
    local subtitle = panel:FindById("endSubtitle")
    local stats = panel:FindById("endStats")

    -- 标题和副标题
    local titles = {
        [Config.Ending.WIN] = { "你充上电了！", "文明社会再次证明：\n只要你还有1%电量，\n你就还有被收费的资格。" },
        [Config.Ending.NO_BATTERY] = { "手机关机了", "你失去了地图、支付、联系人、\n身份证明，以及作为现代人的\n大部分器官。" },
        [Config.Ending.STOLEN] = { "手机被抢了", "他拿着你的手机跑了。\n恭喜，你的电量问题被永久解决了。" },
        [Config.Ending.DEAD] = { "你死了", "但好消息是，手机还剩" .. string.format("%.1f", gs.battery) .. "%。" },
        [Config.Ending.ARRESTED] = { "你被逮捕了", "警方表示：这是本市本周第37起\n低电量引发的尊严崩塌案件。" },
    }

    local data = titles[endingType] or { "游戏结束", reason }
    if title then
        title:SetText(data[1])
        if endingType == Config.Ending.WIN then
            title:SetFontColor({ 50, 255, 100, 255 })
        else
            title:SetFontColor({ 255, 80, 80, 255 })
        end
    end
    if subtitle then subtitle:SetText(data[2]) end

    -- 统计
    if stats then
        stats:ClearChildren()
        local statLines = {
            string.format("剩余电量: %.1f%%", gs.battery),
            string.format("耗时: %.0f秒", gs.stats.timeElapsed),
            string.format("打开手机: %d次", gs.stats.phoneOpenCount),
            string.format("观看广告: %d次", gs.stats.adWatchCount),
            string.format("误点广告: %d次", gs.stats.adMisclickCount),
            string.format("花费: ¥%.2f", gs.stats.moneySpent),
        }
        for _, line in ipairs(statLines) do
            stats:AddChild(UI.Label {
                text = line,
                fontSize = 10,
                fontColor = { 160, 160, 180, 255 },
            })
        end
    end
end

-- ====================================================================
-- 消息显示
-- ====================================================================
function ShowMessage(title, body, btnText, callback)
    local box = uiRoot:FindById("messageBox")
    if not box then return end
    box:SetVisible(true)
    gs.phase = Config.State.EVENT

    local t = box:FindById("msgTitle")
    local b = box:FindById("msgBody")
    local btn = box:FindById("msgBtn")
    if t then t:SetText(title or "提示") end
    if b then b:SetText(body or "") end
    if btn then
        btn:SetText(btnText or "确定")
    end

    -- 存回调
    gs._messageCallback = callback
end

function HideMessage()
    local box = uiRoot:FindById("messageBox")
    if box then box:SetVisible(false) end
    -- 恢复到弹消息前的状态
    if gs.phase == Config.State.EVENT then
        if gs.phoneOpen then
            gs.phase = Config.State.PHONE
        else
            gs.phase = Config.State.PLAYING
        end
    end
    if gs._messageCallback then
        gs._messageCallback()
        gs._messageCallback = nil
    end
end

-- ====================================================================
-- 扫码小游戏结果回调
-- ====================================================================
function HandleScanResult(result)
    if result == "success" then
        -- 扫码成功 → 弹出支付确认
        gs.phase = Config.State.EVENT
        ShowMessage("支付确认", "共享充电宝押金\n¥99.99\n\n确认支付？", "支付¥99.99", function()
            if gs.money >= 99.99 then
                gs.money = gs.money - 99.99
                gs.stats.moneySpent = gs.stats.moneySpent + 99.99
                gs.stats.payCount = gs.stats.payCount + 1
                TriggerEnding(Config.Ending.WIN, "通过共享充电宝充电")
            else
                ShowMessage("支付失败", "余额不足！需要¥99.99\n\n你明明扫上了...", "穷死了", function()
                    gs.phase = Config.State.PLAYING
                end)
                gs.stats.rejectCount = gs.stats.rejectCount + 1
            end
        end)
    end
end

-- ====================================================================
-- 手机事件回调
-- ====================================================================
function HandlePhoneEvent(event)
    if event == "phone_close" then
        gs.phoneOpen = false
        gs.phase = Config.State.PLAYING

    elseif event == "app_open" then
        gs.battery = gs.battery - Config.Battery.CostOpenApp
        gs.stats.phoneOpenCount = gs.stats.phoneOpenCount + 1
        -- 可能弹广告
        if EventSystem.ShouldShowAd(gs.battery) then
            local ad = EventSystem.GetRandomAd()
            PhoneUI.ShowAd(ad.title, ad.body)
            gs.stats.adWatchCount = gs.stats.adWatchCount + 1
        end

    elseif event == "scan_qr" then
        -- 扫码逻辑 - 启动扫码小游戏
        if gs.nearbyInteractable and gs.nearbyInteractable.type == "powerbank" then
            -- 关闭手机 UI，进入扫码小游戏
            PhoneUI.Close()
            gs.phoneOpen = false
            gs.phase = Config.State.SCANNING
            ScanMiniGame.Start(gs.battery, HandleScanResult)
        else
            ShowMessage("扫码失败", "附近没有可扫描的二维码", "知道了")
        end

    elseif event == "ad_misclick" then
        gs.stats.adMisclickCount = gs.stats.adMisclickCount + 1
        gs.battery = gs.battery - Config.Battery.DrainAd
        -- 跳转到假应用市场页面（玩家必须手动关闭）
        PhoneUI.ShowFakeApp("电量守护", gs.battery)

    elseif event == "ad_closed" then
        -- 关闭广告，继续
    end

    -- 检查电量
    CheckBattery()
end

-- ====================================================================
-- 交互逻辑
-- ====================================================================
function HandleInteract()
    if not gs.nearbyInteractable then return end
    local item = gs.nearbyInteractable

    if item.type == "powerbank" then
        -- 需要打开手机扫码
        ShowMessage("共享充电宝", "需要扫码才能使用\n请打开手机 → 扫码App", "好的", function()
            -- 提示玩家打开手机
        end)

    elseif item.type == "shop" then
        local result, text = EventSystem.GetShopResult(gs.world)
        if result == "buy_cable" then
            ShowMessage("购买", text, "购买¥25", function()
                if gs.money >= 25 then
                    gs.money = gs.money - 25
                    gs.stats.moneySpent = gs.stats.moneySpent + 25
                    gs.stats.payCount = gs.stats.payCount + 1
                    gs.chargeProgress.boughtCable = true
                    gs.chargeProgress.cableType = "typec"
                    ShowMessage("购买成功", "你买了一根Type-C数据线", "不错")
                else
                    ShowMessage("余额不足", "你的钱不够！", "穷死了")
                end
            end)
        elseif result == "buy_cable_and_plug" then
            ShowMessage("购买", text, "购买¥45", function()
                if gs.money >= 45 then
                    gs.money = gs.money - 45
                    gs.stats.moneySpent = gs.stats.moneySpent + 45
                    gs.stats.payCount = gs.stats.payCount + 1
                    gs.chargeProgress.boughtCable = true
                    gs.chargeProgress.cableType = "typec"
                    ShowMessage("购买成功", "你买了数据线+插头套装", "稳")
                else
                    ShowMessage("余额不足", "你的钱不够！", "穷死了")
                end
            end)
        else
            ShowMessage("商店", text, "离谱")
            gs.stats.rejectCount = gs.stats.rejectCount + 1
        end

    elseif item.type == "outlet" then
        local result, text = EventSystem.GetOutletResult(gs.world, gs.chargeProgress.boughtCable)
        if result == "success" then
            TriggerEnding(Config.Ending.WIN, "找到插座充电")
        elseif result == "no_cable" then
            ShowMessage("无法充电", text, "去买线")
        else
            ShowMessage("插座故障", text, "服了")
            gs.stats.rejectCount = gs.stats.rejectCount + 1
        end

    elseif item.type == "npc" then
        local result, text = EventSystem.GetNPCResult(gs.world)
        if result == "help" then
            gs.battery = math.min(gs.battery + 2.0, 5.0)
            ShowMessage("好心路人", text .. "\n\n电量+2%！", "谢谢")
        elseif result == "steal" then
            ShowMessage("！！！", text, "...", function()
                TriggerEnding(Config.Ending.STOLEN, "手机被路人抢走")
            end)
        else
            ShowMessage("路人", text, "好吧")
            gs.stats.rejectCount = gs.stats.rejectCount + 1
        end
    end
end

-- ====================================================================
-- 电量检查
-- ====================================================================
function CheckBattery()
    if gs.battery <= 0 then
        gs.battery = 0
        TriggerEnding(Config.Ending.NO_BATTERY, "手机关机")
    end
end

-- ====================================================================
-- 更新逻辑
-- ====================================================================
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 菜单/结局/游戏结束 不更新
    if gs.phase == Config.State.MENU or gs.phase == Config.State.ENDING or gs.phase == Config.State.GAMEOVER then
        return
    end

    -- 扫码小游戏更新
    if gs.phase == Config.State.SCANNING then
        ScanMiniGame.UpdateBattery(gs.battery)
        ScanMiniGame.Update(dt)
    end

    -- 假应用页面更新（下载进度动画）
    if gs.phase == Config.State.PHONE then
        PhoneUI.UpdateFakeApp(dt)
    end

    gs.stats.timeElapsed = gs.stats.timeElapsed + dt
    gs.totalTime = gs.totalTime + dt

    -- 电量消耗：任何游戏状态都扣基础电量
    local drain = Config.Battery.DrainBase
    -- 手机打开或扫码状态时 +50% 基础消耗
    if gs.phoneOpen or gs.phase == Config.State.SCANNING then
        drain = drain * 1.5
    end
    -- App 额外消耗
    if gs.phoneOpen and PhoneUI.GetCurrentApp() then
        drain = drain + Config.Battery.DrainApp
    end
    gs.battery = gs.battery - drain * dt
    CheckBattery()

    -- 更新电量 UI
    UpdateBatteryUI()

    -- 玩家移动（非手机模式时）
    if gs.phase == Config.State.PLAYING then
        UpdatePlayerMovement(dt)
        UpdateNearbyInteractable()
    end

    -- 操作提示只在 PLAYING 状态显示
    local actionHints = uiRoot:FindById("actionHints")
    if actionHints then
        actionHints:SetVisible(gs.phase == Config.State.PLAYING)
    end

    -- 更新手机电量显示
    PhoneUI.UpdateBattery(gs.battery)
    PhoneUI.UpdateBalance(gs.money)
end

function UpdatePlayerMovement(dt)
    local speed = Config.Player.Speed
    local moved = false

    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        gs.playerX = gs.playerX - speed * dt
        gs.facingRight = false
        moved = true
    end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        gs.playerX = gs.playerX + speed * dt
        gs.facingRight = true
        moved = true
    end

    -- 重力和跳跃
    if not gs.playerOnGround then
        gs.playerVelY = gs.playerVelY + 1200 * dt
        gs.playerY = gs.playerY + gs.playerVelY * dt
        if gs.playerY >= WorldRenderer.GetGroundY() then
            gs.playerY = WorldRenderer.GetGroundY()
            gs.playerVelY = 0
            gs.playerOnGround = true
        end
    end

    -- 限制边界
    gs.playerX = math.max(20, math.min(gs.playerX, WorldRenderer.GetWorldWidth() - 20))

    -- 相机跟随
    local targetCam = gs.playerX - screenW / 3
    targetCam = math.max(0, math.min(targetCam, WorldRenderer.GetWorldWidth() - screenW))
    gs.cameraX = gs.cameraX + (targetCam - gs.cameraX) * 5 * dt
end

function UpdateNearbyInteractable()
    local interactables = WorldRenderer.GetInteractables()
    gs.nearbyInteractable = nil

    for _, item in ipairs(interactables) do
        local dist = math.abs(item.x - gs.playerX)
        if dist < Config.InteractDistance then
            gs.nearbyInteractable = item
            break
        end
    end

    -- 更新底部操作提示高亮
    UpdateActionHints()
end

function UpdateActionHints()
    if not uiRoot then return end

    local hintF = uiRoot:FindById("hintF")
    local hintTab = uiRoot:FindById("hintTab")
    local hintFKey = uiRoot:FindById("hintFKey")
    local hintFText = uiRoot:FindById("hintFText")
    local hintTabKey = uiRoot:FindById("hintTabKey")
    local hintTabText = uiRoot:FindById("hintTabText")

    if not hintF or not hintTab then return end

    local hasInteractable = gs.nearbyInteractable ~= nil and gs.phase == Config.State.PLAYING

    -- 脉动动画缩放（用 sin 模拟）
    local pulse = 1.0
    if hasInteractable then
        pulse = 1.0 + math.sin(gs.totalTime * 4) * 0.06
    end

    -- [F] 行
    if hasInteractable then
        local itemLabel = gs.nearbyInteractable.label or "交互"
        -- 高亮：判断该物品是否需要用 F 交互（充电宝不用F，用Tab打开手机扫码）
        local needsF = (gs.nearbyInteractable.type == "shop" or
                        gs.nearbyInteractable.type == "outlet" or
                        gs.nearbyInteractable.type == "npc")
        if needsF then
            hintF:SetStyle({
                backgroundColor = { 40, 50, 80, 230 },
                borderColor = { 100, 180, 255, 255 },
                transform = { scale = pulse },
            })
            if hintFKey then hintFKey:SetFontColor({ 100, 200, 255, 255 }) end
            if hintFText then
                hintFText:SetText("交互 - " .. itemLabel)
                hintFText:SetFontColor({ 220, 240, 255, 255 })
            end
        else
            hintF:SetStyle({
                backgroundColor = { 20, 20, 35, 180 },
                borderColor = { 60, 60, 80, 150 },
                transform = { scale = 1.0 },
            })
            if hintFKey then hintFKey:SetFontColor({ 140, 140, 160, 255 }) end
            if hintFText then
                hintFText:SetText("交互")
                hintFText:SetFontColor({ 140, 140, 160, 255 })
            end
        end

        -- [Tab] 行：如果附近有充电宝类型，提示需要打开手机扫码
        local needsPhone = (gs.nearbyInteractable.type == "powerbank")
        if needsPhone then
            hintTab:SetStyle({
                backgroundColor = { 40, 50, 80, 230 },
                borderColor = { 100, 180, 255, 255 },
                transform = { scale = pulse },
            })
            if hintTabKey then hintTabKey:SetFontColor({ 100, 200, 255, 255 }) end
            if hintTabText then
                hintTabText:SetText("打开手机 - 附近有充电宝")
                hintTabText:SetFontColor({ 220, 240, 255, 255 })
            end
        else
            hintTab:SetStyle({
                backgroundColor = { 20, 20, 35, 180 },
                borderColor = { 60, 60, 80, 150 },
                transform = { scale = 1.0 },
            })
            if hintTabKey then hintTabKey:SetFontColor({ 140, 140, 160, 255 }) end
            if hintTabText then
                hintTabText:SetText("打开手机")
                hintTabText:SetFontColor({ 140, 140, 160, 255 })
            end
        end
    else
        -- 无可交互物品，恢复默认暗色
        hintF:SetStyle({
            backgroundColor = { 20, 20, 35, 180 },
            borderColor = { 60, 60, 80, 150 },
            transform = { scale = 1.0 },
        })
        if hintFKey then hintFKey:SetFontColor({ 140, 140, 160, 255 }) end
        if hintFText then
            hintFText:SetText("交互")
            hintFText:SetFontColor({ 140, 140, 160, 255 })
        end

        hintTab:SetStyle({
            backgroundColor = { 20, 20, 35, 180 },
            borderColor = { 60, 60, 80, 150 },
            transform = { scale = 1.0 },
        })
        if hintTabKey then hintTabKey:SetFontColor({ 140, 140, 160, 255 }) end
        if hintTabText then
            hintTabText:SetText("打开手机")
            hintTabText:SetFontColor({ 140, 140, 160, 255 })
        end
    end
end

function UpdateBatteryUI()
    local fill = uiRoot:FindById("batteryFill")
    local text = uiRoot:FindById("batteryText")
    if fill then
        local pct = math.max(0, gs.battery / 5.0)
        fill:SetWidth(tostring(math.floor(pct * 100)) .. "%")
        -- 颜色变化
        if gs.battery <= 1 then
            fill:SetStyle({ backgroundColor = { 255, 0, 0, 255 } })
        elseif gs.battery <= 2 then
            fill:SetStyle({ backgroundColor = { 255, 80, 0, 255 } })
        elseif gs.battery <= 3 then
            fill:SetStyle({ backgroundColor = { 255, 150, 0, 255 } })
        else
            fill:SetStyle({ backgroundColor = { 255, 50, 50, 255 } })
        end
    end
    if text then
        text:SetText(string.format("%.1f%%", math.max(0, gs.battery)))
    end
end

-- ====================================================================
-- 输入处理
-- ====================================================================
---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if gs.phase == Config.State.MENU then
        if key == KEY_RETURN or key == KEY_SPACE then
            StartGame()
        end
        return
    end

    if gs.phase == Config.State.ENDING then
        if key == KEY_RETURN or key == KEY_SPACE then
            RestartGame()
        end
        return
    end

    if gs.phase == Config.State.EVENT then
        if key == KEY_RETURN or key == KEY_SPACE then
            HideMessage()
        end
        return
    end

    -- 扫码小游戏中，ESC 退出
    if gs.phase == Config.State.SCANNING then
        if key == KEY_ESCAPE then
            ScanMiniGame.Stop()
            gs.phase = Config.State.PLAYING
        end
        return
    end

    -- Tab 键打开/关闭手机
    if key == KEY_TAB then
        if gs.phoneOpen then
            PhoneUI.Close()
            gs.phoneOpen = false
            gs.phase = Config.State.PLAYING
        else
            gs.phoneOpen = true
            gs.phase = Config.State.PHONE
            gs.battery = gs.battery - Config.Battery.CostOpenPhone
            gs.stats.phoneOpenCount = gs.stats.phoneOpenCount + 1
            PhoneUI.Open()
            CheckBattery()

            -- 打开时有概率弹广告
            if EventSystem.ShouldShowAd(gs.battery) then
                local ad = EventSystem.GetRandomAd()
                PhoneUI.ShowAd(ad.title, ad.body)
                gs.stats.adWatchCount = gs.stats.adWatchCount + 1
            end
        end
        return
    end

    -- F 键交互
    if key == KEY_F and gs.phase == Config.State.PLAYING then
        HandleInteract()
        return
    end

    -- 空格跳跃
    if key == KEY_SPACE and gs.phase == Config.State.PLAYING then
        if gs.playerOnGround then
            gs.playerVelY = -Config.Player.JumpStrength
            gs.playerOnGround = false
        end
        return
    end
end

-- ====================================================================
-- 鼠标点击处理
-- ====================================================================
---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    -- 扫码小游戏中，点击 = 拍摄
    if gs.phase == Config.State.SCANNING and ScanMiniGame.IsActive() then
        ScanMiniGame.OnClick()
    end
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================
function HandleRender(eventType, eventData)
    if not nvg then return end

    local dpr = graphics:GetDPR()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    screenW = physW / dpr
    screenH = physH / dpr

    nvgBeginFrame(nvg, physW, physH, dpr)

    if gs.phase ~= Config.State.MENU then
        -- 渲染城市世界
        WorldRenderer.Render(nvg, gs.cameraX, screenW, screenH)

        -- 渲染玩家
        local playerScreenX = gs.playerX - gs.cameraX
        WorldRenderer.RenderPlayer(nvg, playerScreenX, gs.playerY, gs.facingRight, gs.phoneOpen)

        -- 电量低时的屏幕效果
        if gs.battery <= 2 then
            -- 红色闪烁警告
            local alpha = math.floor(math.abs(math.sin(gs.totalTime * 3)) * 30)
            nvgBeginPath(nvg)
            nvgRect(nvg, 0, 0, screenW, screenH)
            nvgFillColor(nvg, nvgRGBA(255, 0, 0, alpha))
            nvgFill(nvg)
        end

        -- 卡顿效果（电量低时屏幕抖动）
        if gs.battery <= 1 and gs.phoneOpen then
            local shake = math.sin(gs.totalTime * 20) * 2
            nvgBeginPath(nvg)
            nvgRect(nvg, shake, 0, screenW, 2)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 50))
            nvgFill(nvg)
        end

        -- 扫码小游戏覆盖渲染
        if gs.phase == Config.State.SCANNING and ScanMiniGame.IsActive() then
            ScanMiniGame.Render(nvg, screenW, screenH)
        end
    end

    nvgEndFrame(nvg)
end

