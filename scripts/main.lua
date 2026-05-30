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
local ShopScene = require("ShopScene")
local ItemData = require("ItemData")
local LoanApp = require("LoanApp")
local AdSystem = require("AdSystem")
local DiagLog = require("DiagLog")
local AudioManager = require("AudioManager")
local AssetMap = require("AssetMap")

-- ====================================================================
-- 全局状态
-- ====================================================================
local nvg = nil
local nvgOverlay = nil  -- 高层 NanoVG context，渲染在 UI 系统之上（贷款/DiagLog/低电量HUD）
local screenW, screenH = 0, 0
local gs = nil  -- GameState
local uiRoot = nil

-- HUD 引用
local batteryBar = nil
local interactHint = nil
local messageBox = nil
local endingPanel = nil

-- 追击系统状态
local chaseActive = false
local chaseShopkeeperX = 0    -- 店主位置
local chaseStartX = 0         -- 追击起始位置（商店门口）
local chaseDistance = 0        -- 已追击距离
local chaseGiveUpDist = 0     -- 放弃距离（像素）
local chaseTimer = 0          -- 追击计时（用于动画）

-- 低电量警告状态
local batteryWarning2Shown = false     -- 电量<=2格 警告音效是否已播放
local lowBatteryWarningShown = false   -- 电量<=1格 警告是否已弹出
local lowBatteryCountdown = 0          -- 关机倒计时（动态计算：剩余电量/耗电速率）
local lowBatteryActive = false         -- 倒计时是否激活

-- 鼠标状态（逻辑坐标，与NanoVG绘制坐标一致）
local mouseLogX, mouseLogY = 0, 0
local mouseDpr = 1.0
local mousePressed = false       -- 当前按下状态
local hoveredBtn = nil           -- 当前hover的按钮id
local pressedBtn = nil           -- 当前按下的按钮id

-- 贷款系统状态（广告已改为LoanApp内置NanoVG渲染，不再依赖PhoneUI广告系统）

-- NPC 对话状态
local npcDialogueOpen = false
local npcDialogueText = ""
local npcDialogueOptions = {}  -- { {text, action}, ... }
local npcDialogueChoice = 1
local npcType = nil            -- "good" / "bad" / "neutral"

-- 老虎机博弈状态（NPC对话中触发）
local slotGameOpen = false
local slotPhase = "idle"         -- idle/spinning/result
local slotReels = { 1, 1, 1 }
local slotSpeeds = { 0, 0, 0 }
local slotTimers = { 0, 0, 0 }
local slotStopped = { false, false, false }
local slotResult = nil

local SLOT_SYMBOLS = { "充电", "充电", "无视", "无视", "抢夺" }
local SLOT_COLORS = {
    { 50, 255, 100 },  -- 充电=绿
    { 50, 255, 100 },
    { 180, 180, 180 }, -- 无视=灰
    { 180, 180, 180 },
    { 255, 50, 50 },   -- 抢夺=红
}
local SLOT_NUM_SYMBOLS = #SLOT_SYMBOLS

-- 滚动状态（每个转轮一个连续的偏移值，单位=符号格）
local slotScrollPos = { 0, 0, 0 }     -- 当前滚动位置（浮点）
local slotTargetPos = { 0, 0, 0 }     -- 目标停止位置
local slotScrollSpeed = { 0, 0, 0 }   -- 当前滚动速度（格/秒）
local slotStopping = { false, false, false }  -- 是否正在减速停止
local slotSpinSource = nil             -- 循环旋转音效的 SoundSource 引用
local slotIgnoreCount = 0              -- 连续"无视"次数（3次则NPC拒绝）

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

    -- 创建 overlay NanoVG context（渲染在 UI 系统之上，用于贷款流程/DiagLog/低电量HUD）
    nvgOverlay = nvgCreate(1)
    if nvgOverlay then
        nvgCreateFont(nvgOverlay, "sans", "Fonts/MiSans-Regular.ttf")
        nvgSetRenderOrder(nvgOverlay, 999995)  -- 高于 UI 系统的 999990
    end

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

    -- 初始化商店场景
    ShopScene.Init(nvg, screenW, screenH)

    -- 初始化手机 UI
    PhoneUI.Init(HandlePhoneEvent)

    -- 初始化贷款系统
    LoanApp.Init({
        onLoanComplete = function(amount)
            -- 贷款到账
            gs.money = gs.money + amount
            PhoneUI.UpdateBalance(gs.money)
            print("[LoanApp] 贷款到账: ¥" .. amount)
        end,
        onShowAd = function()
            -- 贷款流程需要显示广告 → 在手机内弹出
            DiagLog.Log("广告", "贷款流程onShowAd触发, 状态=" .. LoanApp.GetState())
            PhoneUI.ShowAd({
                type = "popup",
                content = { title = "限时特惠！充电宝免押金", body = "新用户专享：首次租借0元起\n全城5000+网点，随借随还" },
                acceptText = "立即领取",
                rejectText = "残忍拒绝",
            })
        end,
        onHideAd = function()
            -- 广告结束 → 隐藏 PhoneUI 广告层
            PhoneUI.HideAd()
        end,
    })

    -- 创建 UI
    CreateGameUI()

    -- 订阅事件
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    if nvgOverlay then
        SubscribeToEvent(nvgOverlay, "NanoVGRender", "HandleOverlayRender")
    end
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")

    -- 显示开始菜单
    ShowMenu()

    -- 初始化诊断日志
    DiagLog.Init()
    DiagLog.SetStatusGetter(function()
        return {
            phase = gs.phase or "?",
            battery = gs.battery or 0,
            phoneOpen = gs.phoneOpen,
            loanState = LoanApp.GetState and LoanApp.GetState() or "?",
            adShowing = LoanApp.IsAdShowing and LoanApp.IsAdShowing() or false,
            lowBattery = lowBatteryActive or false,
            lowBatteryCountdown = lowBatteryCountdown or 0,
            extra = string.format("PhoneUI.adVisible=%s | totalTime=%.1f",
                tostring(PhoneUI.IsAdVisible and PhoneUI.IsAdVisible() or "?"), gs.totalTime or 0)
        }
    end)
    DiagLog.Log("系统", "游戏启动: " .. Config.Title)

    -- 初始化音频系统
    AudioManager.Init()
    AudioManager.SetBGMForState(Config.State.MENU)

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
    local phonePanel = PhoneUI.CreateUI()

    uiRoot = UI.Panel {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- Layer 1: 常驻操作提示（底部，最底层）
            CreateActionHints(),
            -- Layer 2: 手机界面（广告和低电量覆盖层已内置在手机面板中）
            phonePanel,
            -- Layer 3: HUD（电量条等，在手机遮罩之上，始终清晰可见）
            CreateHUD(),
            -- Layer 4: 消息框（在手机之上，确保始终可见）
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
            -- 电量显示 + 耗电明细
            UI.Panel {
                gap = 3,
                children = {
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
                    -- 耗电明细面板
                    UI.Panel {
                        id = "drainInfoPanel",
                        paddingLeft = 6, paddingRight = 6, paddingBottom = 4, paddingTop = 2,
                        backgroundColor = { 0, 0, 0, 120 },
                        borderRadius = 6,
                        gap = 1,
                        children = {
                            UI.Label { id = "drainLine1", text = "", fontSize = 9, fontColor = { 180, 180, 180, 200 } },
                            UI.Label { id = "drainLine2", text = "", fontSize = 9, fontColor = { 255, 200, 100, 200 } },
                            UI.Label { id = "drainLine3", text = "", fontSize = 9, fontColor = { 255, 150, 80, 200 } },
                            UI.Label { id = "drainLine4", text = "", fontSize = 9, fontColor = { 255, 80, 80, 200 } },
                        }
                    },
                }
            },
            -- 手机号+移动提示
            UI.Panel {
                alignItems = "flex-end",
                gap = 4,
                children = {
                    UI.Panel {
                        padding = 6,
                        backgroundColor = { 0, 0, 0, 160 },
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                id = "phoneNumberHUD",
                                text = LoanApp.GetPhoneDisplay(),
                                fontSize = 9,
                                fontColor = { 180, 200, 255, 255 },
                            },
                        }
                    },
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
                    -- 结局插画
                    UI.Panel {
                        id = "endIllustration",
                        width = 180,
                        height = 180,
                        borderRadius = 12,
                        backgroundFit = "contain",
                        marginBottom = 4,
                    },
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

    -- 关闭所有对话/博弈面板
    npcDialogueOpen = false
    npcDialogueOptions = {}
    npcDialogueChoice = 1
    slotGameOpen = false
    slotPhase = "idle"
    slotResult = nil
    chaseActive = false

    -- 重置低电量和广告状态
    batteryWarning2Shown = false
    lowBatteryWarningShown = false
    lowBatteryCountdown = 0
    lowBatteryActive = false
    gs.loanPhoneHintStart = nil
    PhoneUI.HideLowBatteryWarning()
    PhoneUI.HideAd()
    PhoneUI.Close()

    GameState.Reset(gs)
    GameState.RandomizeWorld(gs)
    gs.phase = Config.State.PLAYING
    gs.playerX = 200
    gs.playerY = WorldRenderer.GetGroundY()

    WorldRenderer.Init(screenW, screenH)
    gs.playerY = WorldRenderer.GetGroundY()

    -- 重置音频并播放城市 BGM
    AudioManager.ResetBGM()
    AudioManager.SetBGMForState(Config.State.PLAYING)

    print("游戏开始！电量: 5%")
end

function RestartGame()
    StartGame()
end

-- ====================================================================
-- 追击系统
-- ====================================================================
function StartChase()
    chaseActive = true
    gs.phase = Config.State.CHASE
    AudioManager.ChaseAlert()
    AudioManager.SetBGMForState(Config.State.CHASE)
    -- 玩家从商店门口开始跑，给玩家一个合理的领先距离
    chaseStartX = gs.playerX
    -- 店主从商店里面出来，比玩家落后 200 像素（模拟反应时间+从柜台跑到门口）
    chaseShopkeeperX = gs.playerX - 200
    -- 放弃距离 = 5栋楼宽度，约 5 * 150 = 750 像素
    chaseGiveUpDist = Config.Chase.GiveUpDistance * 150
    chaseDistance = 0
    chaseTimer = 0
    print("[Chase] 店主开始追击！玩家领先200px")
end

function UpdateChase(dt)
    if not chaseActive then return end

    chaseTimer = chaseTimer + dt

    -- 玩家手动控制移动（必须自己按键跑）
    local playerSpeed = Config.Chase.PlayerSpeedBoost
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        gs.playerX = gs.playerX + playerSpeed * dt
        gs.facingRight = true
    end
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        gs.playerX = gs.playerX - playerSpeed * 0.5 * dt
        gs.facingRight = false
    end

    -- 跳跃（追击中也能跳，纯视觉效果）
    if input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then
        if gs.playerOnGround then
            gs.playerVelY = -Config.Player.JumpStrength * 0.7
            gs.playerOnGround = false
            AudioManager.Jump()
        end
    end
    -- 重力
    if not gs.playerOnGround then
        gs.playerVelY = gs.playerVelY + 1200 * dt
        gs.playerY = gs.playerY + gs.playerVelY * dt
        if gs.playerY >= WorldRenderer.GetGroundY() then
            gs.playerY = WorldRenderer.GetGroundY()
            gs.playerVelY = 0
            gs.playerOnGround = true
            AudioManager.Land()
        end
    end

    -- 店主追赶（自动向玩家方向跑）
    local shopSpeed = Config.Chase.ShopkeeperSpeed
    -- 店主追赶一段时间后会喘气减速
    if chaseTimer > 3.0 then
        shopSpeed = shopSpeed * 0.85
    end
    if chaseTimer > 5.0 then
        shopSpeed = shopSpeed * 0.7
    end
    -- 店主始终向玩家方向追
    if chaseShopkeeperX < gs.playerX then
        chaseShopkeeperX = chaseShopkeeperX + shopSpeed * dt
    end

    -- 计算追击距离（取玩家与起点的距离）
    chaseDistance = math.abs(gs.playerX - chaseStartX)

    -- 限制边界
    gs.playerX = math.max(20, math.min(gs.playerX, WorldRenderer.GetWorldWidth() - 20))

    -- 相机跟随
    local targetCam = gs.playerX - screenW / 3
    targetCam = math.max(0, math.min(targetCam, WorldRenderer.GetWorldWidth() - screenW))
    gs.cameraX = gs.cameraX + (targetCam - gs.cameraX) * 5 * dt

    -- 判定：被抓住
    if chaseShopkeeperX >= gs.playerX - Config.Chase.CatchDistance then
        chaseActive = false
        AudioManager.ChaseCaught()
        TriggerEnding(Config.Ending.ARRESTED, "偷东西被店主抓住了")
        return
    end

    -- 判定：店主放弃（玩家跑远了）
    if gs.playerX - chaseShopkeeperX >= chaseGiveUpDist then
        chaseActive = false
        AudioManager.ChaseEscape()
        AudioManager.SetBGMForState(Config.State.PLAYING)
        gs.phase = Config.State.PLAYING
        print("[Chase] 店主放弃追击，你逃掉了！但你偷了东西...")
        return
    end
end

-- ====================================================================
-- 低电量 HUD 倒计时（屏幕顶部居中红色横幅）
-- ====================================================================
function RenderLowBatteryHUD(vg, sw, sh)
    -- 获取手机内容区域，将 HUD 限制在手机内
    local phoneRect = PhoneUI.GetPhoneContentRect(sw, sh)
    if not phoneRect then return end

    nvgSave(vg)
    nvgScissor(vg, phoneRect.x, phoneRect.y, phoneRect.w, phoneRect.h)

    local barH = 30
    local barW = math.min(240, phoneRect.w - 10)
    local barX = phoneRect.x + (phoneRect.w - barW) / 2
    local barY = phoneRect.y + 4

    -- 闪烁效果
    local pulse = math.abs(math.sin(gs.totalTime * 4))
    local bgAlpha = math.floor(180 + 75 * pulse)

    -- 背景横幅
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(140, 20, 20, bgAlpha))
    nvgFill(vg)
    -- 红色边框
    nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 左侧警告图标
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, barX + 8, barY + barH / 2, "⚠")

    -- 文字：电量不足
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, barX + 22, barY + barH / 2, "电量不足·关机倒计时")

    -- 右侧倒计时数字
    local secs = math.ceil(lowBatteryCountdown)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, barX + barW - 8, barY + barH / 2, string.format("%ds", secs))

    nvgRestore(vg)
end

function RenderChase(vg, sw, sh)
    -- 渲染店主（在城市场景之上）
    local shopkeeperScreenX = chaseShopkeeperX - gs.cameraX
    local groundY = WorldRenderer.GetGroundY()

    -- 店主身体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, shopkeeperScreenX - 12, groundY - 48, 24, 40, 4)
    nvgFillColor(vg, nvgRGBA(180, 60, 60, 255))
    nvgFill(vg)

    -- 店主头
    nvgBeginPath(vg)
    nvgCircle(vg, shopkeeperScreenX, groundY - 56, 10)
    nvgFillColor(vg, nvgRGBA(255, 200, 150, 255))
    nvgFill(vg)

    -- 怒气符号（闪烁）
    if math.floor(chaseTimer * 4) % 2 == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 50, 50, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, shopkeeperScreenX, groundY - 72, "!!!")
    end

    -- 追击提示条（顶部）
    local progress = math.min(1.0, chaseDistance / chaseGiveUpDist)
    local barW = sw * 0.4
    local barX = (sw - barW) / 2
    local barY = 20

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, 20, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 进度条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX + 2, barY + 2, (barW - 4) * progress, 16, 4)
    nvgFillColor(vg, nvgRGBA(50, 200, 100, 255))
    nvgFill(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, sw / 2, barY + 10, "店主追击中！快跑！")

    -- 操作提示
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(255, 255, 100, 200))
    nvgText(vg, sw / 2, barY + 40, "A/D移动  空格跳跃  快跑别停！")
end

function TriggerEnding(endingType, reason)
    gs.phase = Config.State.ENDING
    gs.ending = endingType
    gs.endingReason = reason

    -- 停止 BGM 并播放结局音效
    AudioManager.StopBGM()
    if endingType == Config.Ending.WIN then
        AudioManager.EndingChargeSuccess()
    elseif endingType == Config.Ending.NO_BATTERY then
        AudioManager.PhoneShutdown()
        -- EndingNoBattery 延迟播放（在 PhoneShutdown 之后）
        -- 简化处理：直接播放，引擎会自动混合
        AudioManager.EndingNoBattery()
    elseif endingType == Config.Ending.STOLEN then
        AudioManager.EndingStolen()
    elseif endingType == Config.Ending.ARRESTED then
        AudioManager.EndingArrested()
    end

    -- 停止低电量倒计时并隐藏警告
    lowBatteryActive = false
    PhoneUI.HideLowBatteryWarning()

    PhoneUI.CloseInstant()
    gs.phoneOpen = false

    local panel = uiRoot:FindById("endingPanel")
    if not panel then return end
    panel:SetVisible(true)

    -- 设置结局插画
    local illustration = panel:FindById("endIllustration")
    if illustration then
        local imgPath = AssetMap.Endings[endingType]
        if imgPath then
            illustration:SetBackgroundImage(imgPath)
            illustration:SetVisible(true)
        else
            illustration:SetVisible(false)
        end
    end

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
        DiagLog.LogWithEnv("事件", "手机关闭", {battery=gs.battery, phase=gs.phase, loanState=LoanApp.GetState(), phoneOpen=gs.phoneOpen})
        -- 贷款流程不随手机关闭而清理（重新打开手机时继续）
        if LoanApp.IsActive() then
            DiagLog.Log("贷款", "[保留] 手机关闭但贷款流程保持, state=" .. LoanApp.GetState())
        end
        -- 动画结束后会自动切回 PLAYING（见 HandleUpdate 中的检查）
        -- 这里不立即改状态，让滑出动画播放完

    elseif event == "loan_start" then
        DiagLog.LogWithEnv("贷款", "收到loan_start事件（按钮被点击）", {battery=gs.battery, phase=gs.phase, loanState=LoanApp.GetState(), phoneOpen=gs.phoneOpen})
        -- 如果之前的贷款流程还在（理论上不会，但防御性重置）
        if LoanApp.IsActive() then
            DiagLog.Log("警告", "loan_start时发现旧贷款流程未关闭, 强制重置, 旧状态=" .. LoanApp.GetState())
            LoanApp.Close()
        end
        LoanApp.Start()
        gs.loanPhoneHintStart = nil  -- 重置自言自语提示计时
        DiagLog.Log("贷款", "LoanApp.Start()执行完毕, 新状态=" .. LoanApp.GetState() .. ", IsActive=" .. tostring(LoanApp.IsActive()))
        -- 隐藏支付面板，防止底层按钮再次被点击
        PhoneUI.HidePayPanel()
        DiagLog.Log("贷款", "已隐藏支付面板")

    elseif event == "app_open" then
        AudioManager.AppTap()
        gs.battery = gs.battery - Config.Battery.CostOpenApp
        gs.stats.phoneOpenCount = gs.stats.phoneOpenCount + 1
        -- 可能弹广告
        if AdSystem.ShouldTrigger(gs.battery) then
            local ad = AdSystem.TriggerAd(gs.battery)
            DiagLog.Log("广告", "app_open触发广告: " .. (ad.title or "?") .. " 类型=" .. (ad.type or "?"))
            AudioManager.AdPopup()
            PhoneUI.ShowAd(ad)
            gs.stats.adWatchCount = gs.stats.adWatchCount + 1
        end

    elseif event == "scan_qr" then
        -- 扫码逻辑 - 启动扫码小游戏
        if gs.nearbyInteractable and gs.nearbyInteractable.type == "powerbank" then
            -- 立即关闭手机 UI（无动画），进入扫码小游戏
            PhoneUI.CloseInstant()
            gs.phoneOpen = false
            gs.phase = Config.State.SCANNING
            ScanMiniGame.Start(gs.battery, HandleScanResult)
        else
            ShowMessage("扫码失败", "附近没有可扫描的二维码", "知道了")
        end

    elseif event == "ad_misclick" then
        AudioManager.AdMisclick()
        gs.stats.adMisclickCount = gs.stats.adMisclickCount + 1
        gs.battery = gs.battery - Config.Battery.CostAdClick
        -- 误点广告 → 推进贷款流程（广告算"看完了"）+ 跳转假应用
        if LoanApp.IsAdShowing() then
            LoanApp.DismissAd()
            DiagLog.Log("贷款", "ad_misclick → 广告被点击，推进流程, 新状态=" .. LoanApp.GetState())
        end
        -- 跳转到假应用市场页面（玩家必须手动关闭）
        PhoneUI.ShowFakeApp("电量守护", gs.battery)

    elseif event == "ad_closed" then
        AudioManager.AdClose()
        -- 广告关闭 → 如果贷款处于广告状态，推进流程
        if LoanApp.IsAdShowing() then
            LoanApp.DismissAd()
            DiagLog.Log("贷款", "ad_closed → DismissAd, 新状态=" .. LoanApp.GetState())
        end
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
        -- 进入商店室内场景
        AudioManager.DoorEnter()
        AudioManager.SetBGMForState(Config.State.SHOP)
        gs.phase = Config.State.SHOP
        ShopScene.Enter(gs, function(hasUnpaid)
            -- 退出商店回调
            AudioManager.DoorExit()
            if hasUnpaid then
                -- 带着未付款物品离开 → 触发追击
                StartChase()
            else
                AudioManager.SetBGMForState(Config.State.PLAYING)
                gs.phase = Config.State.PLAYING
            end
        end)

    elseif item.type == "outlet" then
        -- 使用物品兼容链验证（完整链路）
        local chainOk, chainReason = ItemData.CheckChargingChain(gs.inventory, gs.phonePort, gs.outletType)
        if chainOk then
            -- 链路完整，还需检查插座是否工作
            if gs.world.outletWorking then
                TriggerEnding(Config.Ending.WIN, "找到插座充电（兼容链完整）")
            else
                ShowMessage("插座故障", "插座是坏的...\n你的充电链完美匹配，\n但这个插座显然不这么认为。", "服了")
                gs.stats.rejectCount = gs.stats.rejectCount + 1
            end
        else
            -- 链路不完整，提示具体原因
            ShowMessage("无法充电", chainReason, "知道了")
        end

    elseif item.type == "npc" then
        AudioManager.Interact()
        OpenNPCDialogue()
    end
end

-- ====================================================================
-- NPC 对话系统
-- ====================================================================
function OpenNPCDialogue()
    AudioManager.NpcTalk()
    -- 判断 NPC 类型
    if gs.world.npcWillSteal then
        npcType = "bad"
    elseif gs.world.npcWillHelp then
        npcType = "good"
    else
        npcType = "neutral"
    end

    npcDialogueOpen = true
    npcDialogueChoice = 1
    gs.phase = Config.State.EVENT

    -- 根据 NPC 类型展示不同开场白和选项
    if npcType == "bad" then
        npcDialogueText = "路人：你好！手机没电了？\n我来帮你看看吧~"
        npcDialogueOptions = {
            { text = "能不能借我充电宝", action = "gamble" },
            { text = "算了，谢谢", action = "leave" },
        }
    elseif npcType == "good" then
        npcDialogueText = "路人：怎么了？手机没电了啊...\n我这有一点点电。"
        npcDialogueOptions = {
            { text = "能不能借我充电宝", action = "gamble" },
            { text = "算了，谢谢", action = "leave" },
        }
    else
        npcDialogueText = "路人：啊？干嘛？\n我赶时间呢..."
        npcDialogueOptions = {
            { text = "能不能借我充电宝", action = "gamble" },
            { text = "算了，谢谢", action = "leave" },
        }
    end
end

function CloseNPCDialogue()
    npcDialogueOpen = false
    npcDialogueOptions = {}
    if gs.phase == Config.State.EVENT and not slotGameOpen then
        gs.phase = Config.State.PLAYING
    end
end

function NPCDialogueConfirm()
    if not npcDialogueOpen then return end
    local option = npcDialogueOptions[npcDialogueChoice]
    if not option then return end

    npcDialogueOpen = false

    if option.action == "leave" then
        CloseNPCDialogue()
    elseif option.action == "gamble" then
        -- 进入博弈说服
        OpenSlotGame()
    end
end

-- ====================================================================
-- 老虎机博弈（NPC 发起）
-- ====================================================================
function OpenSlotGame()
    slotGameOpen = true
    slotPhase = "idle"
    slotResult = nil
    slotReels = { math.random(1, 5), math.random(1, 5), math.random(1, 5) }
    slotStopped = { false, false, false }
    gs.phase = Config.State.EVENT
    print("[SlotGame] NPC老虎机博弈开始")
end

function CloseSlotGame()
    -- 确保停止旋转音效
    if slotSpinSource then
        AudioManager.StopSFXLoop(slotSpinSource)
        slotSpinSource = nil
    end
    slotGameOpen = false
    slotPhase = "idle"
    slotResult = nil
    gs.phase = Config.State.PLAYING
    -- 如果倒计时仍激活，回到 PLAYING 后自动弹出手机警告
    if lowBatteryActive and gs.battery > 0 then
        gs.phoneOpen = true
        gs.phase = Config.State.PHONE
        PhoneUI.Open()
        PhoneUI.ShowLowBatteryWarning()
    end
end

function SlotInsertCoin()
    if slotPhase ~= "idle" then return end
    slotPhase = "spinning"
    slotResult = nil
    slotStopped = { false, false, false }
    slotStopping = { false, false, false }
    -- 各转轮不同速度，增加视觉层次
    slotScrollSpeed = { 12 + math.random() * 4, 14 + math.random() * 4, 16 + math.random() * 4 }
    -- 从当前位置继续滚
    slotTargetPos = { 0, 0, 0 }
    -- 停止之前可能残留的旋转音效
    if slotSpinSource then
        AudioManager.StopSFXLoop(slotSpinSource)
        slotSpinSource = nil
    end
    slotSpinSource = AudioManager.SlotSpin()
end

function SlotStopNext()
    if slotPhase ~= "spinning" then return end
    AudioManager.SlotStop()
    for i = 1, 3 do
        if not slotStopped[i] and not slotStopping[i] then
            slotStopping[i] = true
            -- 决定最终停在哪个符号（随机）
            local finalSymbol = math.random(1, SLOT_NUM_SYMBOLS)
            slotReels[i] = finalSymbol
            -- 计算目标位置：当前位置向前至少滚2圈 + 对齐到目标符号
            local currentPos = slotScrollPos[i]
            local extraRolls = 2 * SLOT_NUM_SYMBOLS  -- 至少再滚2整圈
            local targetAligned = math.ceil(currentPos + extraRolls)
            -- 对齐到目标符号位置
            targetAligned = targetAligned - (targetAligned % SLOT_NUM_SYMBOLS) + (finalSymbol - 1)
            if targetAligned <= currentPos + extraRolls then
                targetAligned = targetAligned + SLOT_NUM_SYMBOLS
            end
            slotTargetPos[i] = targetAligned
            return
        end
    end
end

function EvaluateSlotResult()
    local s1 = SLOT_SYMBOLS[slotReels[1]]
    local s2 = SLOT_SYMBOLS[slotReels[2]]
    local s3 = SLOT_SYMBOLS[slotReels[3]]

    if s1 == "充电" and s2 == "充电" and s3 == "充电" then
        slotResult = "win"
    elseif s1 == "抢夺" and s2 == "抢夺" and s3 == "抢夺" then
        slotResult = "steal"
    elseif s1 == "无视" and s2 == "无视" and s3 == "无视" then
        -- 三无视：NPC直接拒绝，结束博弈
        slotResult = "refuse"
    else
        local chargeCount = 0
        if s1 == "充电" then chargeCount = chargeCount + 1 end
        if s2 == "充电" then chargeCount = chargeCount + 1 end
        if s3 == "充电" then chargeCount = chargeCount + 1 end
        -- 统计无视数量，累加连续无视计数
        local ignoreCount = 0
        if s1 == "无视" then ignoreCount = ignoreCount + 1 end
        if s2 == "无视" then ignoreCount = ignoreCount + 1 end
        if s3 == "无视" then ignoreCount = ignoreCount + 1 end
        if ignoreCount >= 2 then
            slotIgnoreCount = slotIgnoreCount + 1
        else
            slotIgnoreCount = 0  -- 有充电或抢夺出现时重置
        end
        -- 累计3次高无视则NPC失去耐心
        if slotIgnoreCount >= 3 then
            slotResult = "refuse"
        elseif chargeCount == 2 then
            slotResult = "差一点就说服他了..."
        else
            slotResult = "他不太愿意..."
        end
    end
end

function SlotAcknowledge()
    if slotResult == "win" then
        AudioManager.SlotWin()
        slotGameOpen = false
        TriggerEnding(Config.Ending.WIN, "NPC博弈赢得充电宝")
    elseif slotResult == "steal" then
        AudioManager.SlotLose()
        slotGameOpen = false
        TriggerEnding(Config.Ending.STOLEN, "NPC博弈失败，手机被没收")
    elseif slotResult == "refuse" then
        -- 三无视：NPC拒绝继续博弈，关闭老虎机
        AudioManager.SlotLose()
        slotGameOpen = false
        slotPhase = "idle"
        slotResult = nil
        slotIgnoreCount = 0
        -- 回到正常游戏，NPC不再理你
        gs.phase = Config.State.PLAYING
    else
        -- 没中：回到 idle 可以再试
        AudioManager.SlotLose()
        slotPhase = "idle"
        slotResult = "没说服他...再试一次？"
    end
end

function UpdateSlotAnimation(dt)
    if not slotGameOpen or slotPhase ~= "spinning" then return end

    local allDone = true
    for i = 1, 3 do
        if slotStopped[i] then
            -- 已完全停止，不处理
        elseif slotStopping[i] then
            -- 减速阶段：平滑趋近目标位置
            local dist = slotTargetPos[i] - slotScrollPos[i]
            if dist <= 0.01 then
                -- 到达目标，完全对齐
                slotScrollPos[i] = slotTargetPos[i]
                slotStopped[i] = true
                slotScrollSpeed[i] = 0
                -- 检查是否全部停止
                if slotStopped[1] and slotStopped[2] and slotStopped[3] then
                    slotPhase = "result"
                    -- 停止旋转循环音效
                    if slotSpinSource then
                        AudioManager.StopSFXLoop(slotSpinSource)
                        slotSpinSource = nil
                    end
                    EvaluateSlotResult()
                end
            else
                -- 减速公式：速度与剩余距离成正比，但有最小速度保证能到达
                local decelSpeed = math.max(3.0, dist * 5.0)
                slotScrollSpeed[i] = math.min(slotScrollSpeed[i], decelSpeed)
                slotScrollPos[i] = slotScrollPos[i] + slotScrollSpeed[i] * dt
                -- 不超过目标
                if slotScrollPos[i] >= slotTargetPos[i] then
                    slotScrollPos[i] = slotTargetPos[i]
                end
                allDone = false
            end
        else
            -- 自由滚动阶段
            slotScrollPos[i] = slotScrollPos[i] + slotScrollSpeed[i] * dt
            allDone = false
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

    -- 音频系统更新（crossfade 等）
    AudioManager.Update(dt)

    -- 手机滑入/滑出动画（在所有状态下都要更新）
    PhoneUI.UpdateAnim(dt)

    -- 手机滑出动画完成 → 切回 PLAYING
    if gs.phoneOpen and not PhoneUI.IsOpen() and not PhoneUI.IsAnimating() then
        gs.phoneOpen = false
        if gs.phase == Config.State.PHONE then
            gs.phase = Config.State.PLAYING
            AudioManager.SetBGMForState(Config.State.PLAYING)
        end
    end

    -- 菜单/结局/游戏结束 不更新
    if gs.phase == Config.State.MENU or gs.phase == Config.State.ENDING or gs.phase == Config.State.GAMEOVER then
        return
    end

    -- 扫码小游戏更新
    if gs.phase == Config.State.SCANNING then
        ScanMiniGame.UpdateBattery(gs.battery)
        ScanMiniGame.Update(dt)
    end

    -- 商店场景更新
    if gs.phase == Config.State.SHOP then
        ShopScene.Update(dt)
    end

    -- 追击更新
    if gs.phase == Config.State.CHASE then
        UpdateChase(dt)
    end

    -- NPC老虎机动画更新
    if gs.phase == Config.State.EVENT and slotGameOpen then
        UpdateSlotAnimation(dt)
    end

    -- 假应用页面更新（下载进度动画）
    if gs.phase == Config.State.PHONE then
        PhoneUI.UpdateFakeApp(dt)
        PhoneUI.UpdateAd(dt)
    end

    -- 贷款系统更新（在手机打开时才运行）
    if gs.phoneOpen and LoanApp.IsActive() then
        LoanApp.Update(dt)
    end

    gs.stats.timeElapsed = gs.stats.timeElapsed + dt
    gs.totalTime = gs.totalTime + dt

    -- 电量消耗：分项计算，用于显示明细
    local drainBase = Config.Battery.DrainBase       -- 基础耗电（始终存在）
    local drainScreen = 0                            -- 手机屏幕额外
    local drainApp = 0                               -- App 额外
    local drainAd = 0                                -- 广告额外

    -- 手机屏幕打开时
    if gs.phoneOpen or gs.phase == Config.State.SCANNING or gs.phase == Config.State.SHOP then
        drainScreen = Config.Battery.DrainScreenOn
    end
    -- App 运行时
    if gs.phoneOpen and PhoneUI.GetCurrentApp() then
        drainApp = Config.Battery.DrainApp
    end
    -- 广告播放时（持续耗电）
    if LoanApp.IsAdShowing and LoanApp.IsAdShowing() then
        drainAd = Config.Battery.DrainAd
    end

    local drain = drainBase + drainScreen + drainApp + drainAd
    gs.battery = gs.battery - drain * dt
    -- 保存当前耗电明细供 UI 显示
    gs.drainInfo = {
        base = drainBase,
        screen = drainScreen,
        app = drainApp,
        ad = drainAd,
        total = drain,
    }
    -- 电量联动 BGM 变调/音量
    AudioManager.UpdateBatteryEffect(gs.battery)
    CheckBattery()

    -- 电量 <= 2格 播放警告音效（只一次）
    if gs.battery <= 2.0 and gs.battery > 0 and not batteryWarning2Shown then
        batteryWarning2Shown = true
        AudioManager.BatteryWarning()
    end

    -- 低电量警告检测：电量 <= 1格 时激活倒计时
    if gs.battery <= 1.0 and gs.battery > 0 and not lowBatteryWarningShown then
        lowBatteryWarningShown = true
        lowBatteryActive = true
        AudioManager.BatteryCritical()
        -- 如果当前在自由行走状态，自动弹出手机并显示警告
        if gs.phase == Config.State.PLAYING then
            gs.phoneOpen = true
            gs.phase = Config.State.PHONE
            PhoneUI.Open()
            PhoneUI.ShowLowBatteryWarning()
        end
    end

    -- 低电量倒计时（动态计算：剩余电量 / 当前耗电速率，保证归零时电量正好没电）
    if lowBatteryActive and gs.battery > 0 then
        lowBatteryCountdown = gs.battery / drain  -- 实时计算剩余秒数
        PhoneUI.UpdateLowBatteryCountdown(lowBatteryCountdown)
    elseif gs.battery <= 0 then
        lowBatteryCountdown = 0
        lowBatteryActive = false
    end

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

    -- 脚步声（地面移动时）
    if moved and gs.playerOnGround then
        AudioManager.Footstep()
    end

    -- 重力和跳跃
    if not gs.playerOnGround then
        gs.playerVelY = gs.playerVelY + 1200 * dt
        gs.playerY = gs.playerY + gs.playerVelY * dt
        if gs.playerY >= WorldRenderer.GetGroundY() then
            gs.playerY = WorldRenderer.GetGroundY()
            gs.playerVelY = 0
            gs.playerOnGround = true
            AudioManager.Land()
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
            fill:SetStyle({ backgroundColor = { 50, 200, 50, 255 } })
        end
    end
    if text then
        text:SetText(string.format("%.1f%%", math.max(0, gs.battery)))
    end

    -- 更新耗电明细显示
    local info = gs.drainInfo
    if info then
        local line1 = uiRoot:FindById("drainLine1")
        local line2 = uiRoot:FindById("drainLine2")
        local line3 = uiRoot:FindById("drainLine3")
        local line4 = uiRoot:FindById("drainLine4")

        -- 第一行始终显示基础耗电
        if line1 then
            line1:SetText(string.format("基础耗电 %.3f/s", info.base))
        end

        -- 第二行：手机屏幕（仅在有时显示）
        if line2 then
            if info.screen > 0 then
                line2:SetText(string.format("手机屏幕 +%.3f/s", info.screen))
                line2:SetVisible(true)
            else
                line2:SetText("")
                line2:SetVisible(false)
            end
        end

        -- 第三行：App运行
        if line3 then
            if info.app > 0 then
                line3:SetText(string.format("运行App +%.3f/s", info.app))
                line3:SetVisible(true)
            else
                line3:SetText("")
                line3:SetVisible(false)
            end
        end

        -- 第四行：广告
        if line4 then
            if info.ad > 0 then
                line4:SetText(string.format("广告播放 +%.3f/s", info.ad))
                line4:SetVisible(true)
            else
                line4:SetText("")
                line4:SetVisible(false)
            end
        end
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
        -- NPC 对话面板输入
        if npcDialogueOpen then
            -- 鼠标点击选项，键盘仅ESC关闭
            if key == KEY_ESCAPE then
                CloseNPCDialogue()
            end
            return
        end
        -- 老虎机博弈面板输入
        if slotGameOpen then
            if key == KEY_F or key == KEY_RETURN then
                if slotPhase == "result" then
                    SlotAcknowledge()
                elseif slotPhase == "spinning" then
                    SlotStopNext()
                else
                    SlotInsertCoin()
                end
            elseif key == KEY_ESCAPE then
                CloseSlotGame()
            end
            return
        end
        -- 普通消息框
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

    -- 商店场景中
    if gs.phase == Config.State.SHOP then
        if ShopScene.IsDoorWarningOpen() then
            -- 门口警告面板（最高优先级）
            if key == KEY_W or key == KEY_UP then
                ShopScene.DoorWarningNavigate(-1)
            elseif key == KEY_S or key == KEY_DOWN then
                ShopScene.DoorWarningNavigate(1)
            elseif key == KEY_F or key == KEY_RETURN then
                ShopScene.DoorWarningConfirm()
            elseif key == KEY_ESCAPE then
                ShopScene.CloseDoorWarning()
            end
        elseif ShopScene.IsCounterOpen() then
            -- 柜台对话面板打开时
            if key == KEY_W or key == KEY_UP then
                ShopScene.CounterNavigate(-1)
            elseif key == KEY_S or key == KEY_DOWN then
                ShopScene.CounterNavigate(1)
            elseif key == KEY_F or key == KEY_RETURN then
                ShopScene.CounterConfirm()
            elseif key == KEY_ESCAPE then
                ShopScene.CloseCounter()
            end
        elseif ShopScene.IsShelfOpen() then
            -- 货架面板打开时（鼠标点击拿取，键盘仅关闭）
            if key == KEY_ESCAPE then
                ShopScene.CloseShelf()
            end
        elseif ShopScene.IsInventoryMode() then
            -- 携带栏操作模式
            if key == KEY_A or key == KEY_LEFT then
                ShopScene.InventoryNavigate(-1)
            elseif key == KEY_D or key == KEY_RIGHT then
                ShopScene.InventoryNavigate(1)
            elseif key == KEY_Q then
                ShopScene.DiscardItem()
            elseif key == KEY_TAB or key == KEY_ESCAPE then
                ShopScene.ToggleInventoryMode()
            end
        else
            -- 正常商店浏览
            if key == KEY_F then
                ShopScene.OnInteract()
            elseif key == KEY_TAB then
                ShopScene.ToggleInventoryMode()
            elseif key == KEY_ESCAPE then
                -- ESC离开也需要检查未付款物品
                local unpaid = ShopScene.GetUnpaidItems()
                if #unpaid > 0 then
                    -- 弹出门口警告（和走到门口按F交互相同逻辑）
                    ShopScene.ShowDoorWarning()
                else
                    ShopScene.Exit()
                end
            end
        end
        return
    end

    -- 贷款系统键盘输入（手机打开且贷款流程激活时）
    if gs.phoneOpen and LoanApp.IsActive() then
        -- 广告正在显示时：按任意键关闭（如果可关闭）
        if LoanApp.IsAdShowing() then
            if LoanApp.IsAdDismissable() then
                DiagLog.Log("输入", "按键关闭贷款内置广告, 当前状态=" .. LoanApp.GetState())
                LoanApp.DismissAd()
                DiagLog.Log("贷款", "广告关闭后新状态=" .. LoanApp.GetState())
            else
                DiagLog.Log("输入", "按键尝试关闭广告但尚不可关闭, adTimer=" .. string.format("%.1f", LoanApp.GetAdTimer()))
            end
            -- 广告期间拦截所有按键（除Tab）
            if key ~= KEY_TAB then return end
        else
            -- 正常贷款输入处理
            -- 数字键 0-9
            if key >= KEY_0 and key <= KEY_9 then
                LoanApp.OnDigitInput(string.format("%d", key - KEY_0))
                return
            end
            -- 小键盘数字
            if key >= KEY_KP_0 and key <= KEY_KP_9 then
                LoanApp.OnDigitInput(string.format("%d", key - KEY_KP_0))
                return
            end
            -- 退格
            if key == KEY_BACKSPACE then
                LoanApp.OnBackspace()
                return
            end
            -- 回车确认
            if key == KEY_RETURN or key == KEY_KP_ENTER then
                LoanApp.OnConfirm()
                -- 如果贷款流程已关闭（loan_done/failed后按Enter），恢复支付面板
                if not LoanApp.IsActive() then
                    PhoneUI.ShowPayPanel()
                end
                return
            end
            -- ESC 退出贷款流程
            if key == KEY_ESCAPE then
                LoanApp.Close()
                PhoneUI.ShowPayPanel()
                return
            end
        end
        -- 贷款流程中不处理其他按键（除了Tab关手机）
        if key ~= KEY_TAB then return end
    end

    -- Tab 键打开/关闭手机
    if key == KEY_TAB then
        if gs.phoneOpen then
            -- 触发滑出动画，状态在动画完成后切换
            AudioManager.PhoneClose()
            PhoneUI.Close()
            -- 关闭手机时隐藏低电量警告弹窗（倒计时继续）
            PhoneUI.HideLowBatteryWarning()
        elseif not PhoneUI.IsAnimating() then
            gs.phoneOpen = true
            gs.phase = Config.State.PHONE
            gs.battery = gs.battery - Config.Battery.CostOpenPhone
            gs.stats.phoneOpenCount = gs.stats.phoneOpenCount + 1
            AudioManager.PhoneOpen()
            AudioManager.SetBGMForState(Config.State.PHONE)
            PhoneUI.Open()
            CheckBattery()

            -- 打开时如果倒计时激活，重新显示低电量警告
            if lowBatteryActive then
                PhoneUI.ShowLowBatteryWarning()
            elseif AdSystem.ShouldTrigger(gs.battery) then
                -- 打开时有概率弹广告（仅在无低电量警告时）
                local ad = AdSystem.TriggerAd(gs.battery)
                DiagLog.Log("广告", "phone_open触发广告: " .. (ad.title or "?") .. " 类型=" .. (ad.type or "?"))
                PhoneUI.ShowAd(ad)
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
            AudioManager.Jump()
        end
        return
    end
end

-- ====================================================================
-- 鼠标事件处理（坐标转换为逻辑坐标，匹配NanoVG绘制空间）
-- ====================================================================
function HandleMouseMove(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    -- 转换物理像素 → 逻辑坐标（与NanoVG绘制空间一致）
    mouseDpr = graphics:GetDPR()
    mouseLogX = px / mouseDpr
    mouseLogY = py / mouseDpr

    -- 更新 hover 状态
    hoveredBtn = GetButtonAtPosition(mouseLogX, mouseLogY)

    -- 同步 hover/pressed 状态给 ShopScene（用于按钮视觉反馈）
    if gs.phase == Config.State.SHOP then
        ShopScene.SetHoverState(hoveredBtn, pressedBtn)
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    mousePressed = false

    -- 点击确认：按下和释放在同一个按钮上
    if pressedBtn and pressedBtn == hoveredBtn then
        ExecuteButtonClick(pressedBtn)
    end
    pressedBtn = nil

    -- 清除 ShopScene 的 pressed 状态
    if gs.phase == Config.State.SHOP then
        ShopScene.SetHoverState(hoveredBtn, nil)
    end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    -- 右键双击电量条区域 → 触发诊断日志面板
    if button == MOUSEB_RIGHT then
        -- 电量条区域：左上角约 (0, 0) ~ (120, 30)
        local batteryRect = { x = 0, y = 0, w = 140, h = 40 }
        if DiagLog.OnRightClick(mouseLogX, mouseLogY, batteryRect) then
            return
        end
        return
    end

    if button ~= MOUSEB_LEFT then return end
    mousePressed = true

    -- 扫码小游戏中，点击 = 拍摄
    if gs.phase == Config.State.SCANNING and ScanMiniGame.IsActive() then
        ScanMiniGame.OnClick()
        return
    end

    -- 商店货架面板中，点击 = 拿取商品（逻辑坐标）
    if gs.phase == Config.State.SHOP and ShopScene.IsShelfOpen() then
        ShopScene.HandleShelfClick(mouseLogX, mouseLogY)
        return
    end

    -- 记录按下的按钮（释放时才触发点击）
    local btn = GetButtonAtPosition(mouseLogX, mouseLogY)
    if btn then
        pressedBtn = btn
        -- 同步 pressed 状态给 ShopScene
        if gs.phase == Config.State.SHOP then
            ShopScene.SetHoverState(hoveredBtn, pressedBtn)
        end
        return
    end

    -- 点击商店面板外 → 关闭面板
    if gs.phase == Config.State.SHOP then
        if ShopScene.IsDoorWarningOpen() then
            local panelW = 320
            local panelH = 180
            local panelX = (screenW - panelW) / 2
            local panelY = (screenH - panelH) / 2
            if mouseLogX < panelX or mouseLogX > panelX + panelW or mouseLogY < panelY or mouseLogY > panelY + panelH then
                ShopScene.CloseDoorWarning()
                return
            end
        elseif ShopScene.IsCounterOpen() then
            local panelW = 340
            local panelH = 200
            local panelX = (screenW - panelW) / 2
            local panelY = (screenH - panelH) / 2
            if mouseLogX < panelX or mouseLogX > panelX + panelW or mouseLogY < panelY or mouseLogY > panelY + panelH then
                ShopScene.CloseCounter()
                return
            end
        end
    end

    -- 点击面板外 → 关闭面板
    if gs.phase == Config.State.EVENT and slotGameOpen then
        local panelW = 340
        local panelH = 360
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        if mouseLogX < panelX or mouseLogX > panelX + panelW or mouseLogY < panelY or mouseLogY > panelY + panelH then
            CloseSlotGame()
            return
        end
    end

    if gs.phase == Config.State.EVENT and npcDialogueOpen then
        local panelW = 360
        local panelH = 320
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        if mouseLogX < panelX or mouseLogX > panelX + panelW or mouseLogY < panelY or mouseLogY > panelY + panelH then
            CloseNPCDialogue()
            return
        end
    end
end

-- 判断逻辑坐标(mx,my)处有什么按钮
function GetButtonAtPosition(mx, my)
    -- 商店场景面板按钮（门口警告、柜台对话）
    if gs.phase == Config.State.SHOP then
        local shopBtn = ShopScene.GetButtonAtPosition(mx, my)
        if shopBtn then return shopBtn end
        -- 商店面板打开时不检测其他按钮
        if ShopScene.IsDoorWarningOpen() or ShopScene.IsCounterOpen() then
            return nil
        end
    end

    -- 老虎机面板按钮
    if gs.phase == Config.State.EVENT and slotGameOpen then
        local panelW = 340
        local panelH = 360
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        local btnY = panelY + panelH - 50
        local btnW = 100
        local btnH = 30
        local btnGap = 20
        local actionBtnX = panelX + panelW / 2 - btnW - btnGap / 2
        local closeBtnX = panelX + panelW / 2 + btnGap / 2

        if mx >= actionBtnX and mx <= actionBtnX + btnW and my >= btnY and my <= btnY + btnH then
            return "slot_action"
        end
        if slotPhase ~= "result" then
            if mx >= closeBtnX and mx <= closeBtnX + btnW and my >= btnY and my <= btnY + btnH then
                return "slot_close"
            end
        end
        return nil
    end

    -- NPC 对话选项按钮
    if gs.phase == Config.State.EVENT and npcDialogueOpen then
        local panelW = 360
        local panelH = 320
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        local optStartY = panelY + panelH - 20 - #npcDialogueOptions * 36

        for i, opt in ipairs(npcDialogueOptions) do
            local oy = optStartY + (i - 1) * 36
            local optLeft = panelX + 20
            local optRight = panelX + panelW - 20
            if mx >= optLeft and mx <= optRight and my >= oy and my <= oy + 30 then
                return "npc_opt_" .. i
            end
        end
        return nil
    end

    return nil
end

-- 执行按钮点击动作
function ExecuteButtonClick(btnId)
    if not btnId then return end

    -- 商店场景按钮（门口警告、柜台对话）
    if ShopScene.ExecuteButtonClick(btnId) then
        return
    end

    if btnId == "slot_action" then
        if slotPhase == "idle" then
            SlotInsertCoin()
        elseif slotPhase == "spinning" then
            SlotStopNext()
        elseif slotPhase == "result" then
            SlotAcknowledge()
        end
    elseif btnId == "slot_close" then
        CloseSlotGame()
    elseif btnId:sub(1, 8) == "npc_opt_" then
        local idx = tonumber(btnId:sub(9))
        if idx and idx >= 1 and idx <= #npcDialogueOptions then
            npcDialogueChoice = idx
            NPCDialogueConfirm()
        end
    end
end

-- ====================================================================
-- NPC 对话面板渲染
-- ====================================================================
function RenderNPCDialogue(vg, sw, sh)
    if not npcDialogueOpen then return end

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(vg)

    -- 面板（加大高度容纳两个小人）
    local panelW = 360
    local panelH = 320
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(vg, nvgRGBA(25, 30, 50, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 200, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- ============ 两个小人面对面 + 对话气泡 ============
    local charAreaY = panelY + 16
    local charAreaH = 110

    -- 玩家小人（左侧，面朝右）
    local playerCX = panelX + 70
    local playerCY = charAreaY + charAreaH - 10
    DrawStickFigure(vg, playerCX, playerCY, {60, 160, 255}, true)  -- 蓝色，面朝右

    -- NPC 小人（右侧，面朝左）
    local npcCX = panelX + panelW - 70
    local npcCY = charAreaY + charAreaH - 10
    local npcColor = { 120, 120, 120 }
    if npcType == "good" then npcColor = { 80, 200, 100 }
    elseif npcType == "bad" then npcColor = { 200, 80, 80 }
    end
    DrawStickFigure(vg, npcCX, npcCY, npcColor, false)  -- 面朝左

    -- NPC 对话气泡（右上方，自动播放文字动画）
    local bubbleText = ""
    local lines = {}
    for line in npcDialogueText:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    -- 取第一行NPC台词（去掉"路人："前缀）
    if #lines > 0 then
        bubbleText = lines[1]:gsub("^路人：", "")
    end
    if #bubbleText > 12 then
        bubbleText = bubbleText:sub(1, 12 * 3) .. "..."  -- 截断避免太长（中文约12字）
    end

    -- NPC 气泡
    local bubbleW = 110
    local bubbleH = 32
    local bubbleX = npcCX - bubbleW - 5
    local bubbleY = charAreaY + 5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bubbleX, bubbleY, bubbleW, bubbleH, 8)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgFill(vg)
    -- 气泡小尾巴
    nvgBeginPath(vg)
    nvgMoveTo(vg, bubbleX + bubbleW - 15, bubbleY + bubbleH)
    nvgLineTo(vg, bubbleX + bubbleW - 5, bubbleY + bubbleH + 8)
    nvgLineTo(vg, bubbleX + bubbleW - 25, bubbleY + bubbleH)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgFill(vg)
    -- 气泡文字
    nvgFontSize(vg, 10)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(30, 30, 50, 255))
    nvgText(vg, bubbleX + bubbleW / 2, bubbleY + bubbleH / 2, bubbleText)

    -- 玩家气泡（左上方，显示"..."或当前意图）
    local playerBubbleW = 70
    local playerBubbleH = 28
    local playerBubbleX = playerCX + 5
    local playerBubbleY = charAreaY + 10
    nvgBeginPath(vg)
    nvgRoundedRect(vg, playerBubbleX, playerBubbleY, playerBubbleW, playerBubbleH, 8)
    nvgFillColor(vg, nvgRGBA(200, 230, 255, 230))
    nvgFill(vg)
    -- 气泡小尾巴
    nvgBeginPath(vg)
    nvgMoveTo(vg, playerBubbleX + 10, playerBubbleY + playerBubbleH)
    nvgLineTo(vg, playerBubbleX + 5, playerBubbleY + playerBubbleH + 7)
    nvgLineTo(vg, playerBubbleX + 20, playerBubbleY + playerBubbleH)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 230, 255, 230))
    nvgFill(vg)
    -- 玩家气泡文字
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(30, 50, 100, 255))
    nvgText(vg, playerBubbleX + playerBubbleW / 2, playerBubbleY + playerBubbleH / 2, "手机没电了...")

    -- 标签
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 180, 255, 200))
    nvgText(vg, playerCX, playerCY + 4, "你")
    local typeLabel = "路人"
    if npcType == "good" then typeLabel = "热心路人"
    elseif npcType == "bad" then typeLabel = "可疑路人"
    end
    nvgFillColor(vg, nvgRGBA(npcColor[1], npcColor[2], npcColor[3], 200))
    nvgText(vg, npcCX, npcCY + 4, typeLabel)

    -- ============ 分隔线 ============
    local sepY = charAreaY + charAreaH + 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 20, sepY)
    nvgLineTo(vg, panelX + panelW - 20, sepY)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 140, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 对话文本区域 ============
    local textY = sepY + 10
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 220, 240, 255))
    for i, line in ipairs(lines) do
        nvgText(vg, panelX + 20, textY + (i - 1) * 18, line)
    end

    -- ============ 选项列表（鼠标 hover/pressed 高亮） ============
    local mx, my = mouseLogX, mouseLogY
    local optStartY = panelY + panelH - 20 - #npcDialogueOptions * 36
    for i, opt in ipairs(npcDialogueOptions) do
        local oy = optStartY + (i - 1) * 36
        local optLeft = panelX + 20
        local optRight = panelX + panelW - 20
        local btnId = "npc_opt_" .. i
        local isHover = (hoveredBtn == btnId)
        local isPressed = (pressedBtn == btnId and mousePressed)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, optLeft, oy, panelW - 40, 30, 6)
        if isPressed then
            -- 按下态：更亮的背景 + 缩进效果
            nvgFillColor(vg, nvgRGBA(70, 100, 160, 250))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 210, 255, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        elseif isHover then
            -- 悬浮态：高亮背景 + 边框
            nvgFillColor(vg, nvgRGBA(50, 70, 120, 230))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        else
            -- 普通态
            nvgFillColor(vg, nvgRGBA(40, 45, 65, 180))
            nvgFill(vg)
        end

        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isPressed then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        elseif isHover then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 180, 200, 255))
        end
        nvgText(vg, panelX + panelW / 2, oy + 15, opt.text)
    end

    -- 操作提示
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 120, 160, 180))
    nvgText(vg, panelX + panelW / 2, panelY + panelH - 8, "点击选项  [ESC]离开")
end

-- 绘制火柴人（简约小人）
function DrawStickFigure(vg, cx, bottomY, color, facingRight)
    local r, g, b = color[1], color[2], color[3]
    local headR = 10
    local bodyH = 25
    local legH = 18
    local armLen = 15

    local headY = bottomY - legH - bodyH - headR
    local bodyTopY = headY + headR
    local bodyBotY = bodyTopY + bodyH
    local dir = facingRight and 1 or -1

    -- 头
    nvgBeginPath(vg)
    nvgCircle(vg, cx, headY, headR)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgFill(vg)

    -- 身体
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, bodyTopY)
    nvgLineTo(vg, cx, bodyBotY)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 双腿（八字）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, bodyBotY)
    nvgLineTo(vg, cx - 8, bottomY)
    nvgMoveTo(vg, cx, bodyBotY)
    nvgLineTo(vg, cx + 8, bottomY)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, 255))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 手臂（朝对方伸出一只手）
    local armY = bodyTopY + 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, armY)
    nvgLineTo(vg, cx + dir * armLen, armY + 5)
    -- 另一只手自然下垂
    nvgMoveTo(vg, cx, armY)
    nvgLineTo(vg, cx - dir * 6, armY + 12)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, 255))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 表情（简单的眼睛和嘴）
    local eyeOff = facingRight and 3 or -3
    nvgBeginPath(vg)
    nvgCircle(vg, cx + eyeOff, headY - 2, 1.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
end

-- ====================================================================
-- 老虎机博弈面板渲染
-- ====================================================================
function RenderSlotGame(vg, sw, sh)
    if not slotGameOpen then return end

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 面板（加高容纳小人）
    local panelW = 340
    local panelH = 360
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 14)
    nvgFillColor(vg, nvgRGBA(60, 15, 15, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- ============ 两个小人对峙 + 谈判气泡 ============
    local charY = panelY + 75
    local playerCX = panelX + 60
    local npcCX = panelX + panelW - 60
    local npcColor = { 120, 120, 120 }
    if npcType == "good" then npcColor = { 80, 200, 100 }
    elseif npcType == "bad" then npcColor = { 200, 80, 80 }
    end
    DrawStickFigure(vg, playerCX, charY, {60, 160, 255}, true)
    DrawStickFigure(vg, npcCX, charY, npcColor, false)

    -- 谈判中的气泡（根据状态变化）
    local playerSays = "借我充电宝..."
    local npcSays = "嗯..."
    if slotPhase == "spinning" then
        playerSays = "拜托了！"
        npcSays = "让我想想..."
    elseif slotPhase == "result" then
        if slotResult == "win" then
            npcSays = "好吧给你"
            playerSays = "太好了！"
        elseif slotResult == "steal" then
            npcSays = "手机给我！"
            playerSays = "啊！？"
        else
            npcSays = "不太行..."
            playerSays = "再商量商量？"
        end
    end

    -- 玩家气泡
    nvgFontSize(vg, 9)
    nvgFontFace(vg, "sans")
    local pbW = 72
    local pbH = 22
    local pbX = playerCX + 5
    local pbY = panelY + 10
    nvgBeginPath(vg)
    nvgRoundedRect(vg, pbX, pbY, pbW, pbH, 6)
    nvgFillColor(vg, nvgRGBA(200, 230, 255, 220))
    nvgFill(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(30, 50, 100, 255))
    nvgText(vg, pbX + pbW / 2, pbY + pbH / 2, playerSays)

    -- NPC 气泡
    local nbW = 72
    local nbH = 22
    local nbX = npcCX - nbW - 5
    local nbY = panelY + 10
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nbX, nbY, nbW, nbH, 6)
    nvgFillColor(vg, nvgRGBA(255, 240, 220, 220))
    nvgFill(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(80, 30, 30, 255))
    nvgText(vg, nbX + nbW / 2, nbY + nbH / 2, npcSays)

    -- 标题（小人下方）
    local contentTop = panelY + 88
    nvgFontSize(vg, 14)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
    nvgText(vg, panelX + panelW / 2, contentTop, "说服路人！")

    -- 副标题
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(200, 180, 150, 200))
    nvgText(vg, panelX + panelW / 2, contentTop + 16, "三充电=借到充电宝 | 三抢夺=手机被抢")

    -- 转轮区域（滚动式）
    local reelAreaY = contentTop + 34
    local reelW = 70
    local reelH = 80
    local reelGap = 15
    local totalReelW = 3 * reelW + 2 * reelGap
    local reelStartX = panelX + (panelW - totalReelW) / 2
    local symbolH = 28  -- 每个符号格高度

    -- 转轮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, reelStartX - 10, reelAreaY - 5, totalReelW + 20, reelH + 10, 8)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)

    -- 三个转轮（带滚动效果）
    for i = 1, 3 do
        local rx = reelStartX + (i - 1) * (reelW + reelGap)
        local ry = reelAreaY

        -- 转轮背景框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx, ry, reelW, reelH, 5)
        nvgFillColor(vg, nvgRGBA(30, 30, 45, 255))
        nvgFill(vg)

        -- 裁剪区域：只显示转轮内的符号
        nvgSave(vg)
        nvgScissor(vg, rx, ry, reelW, reelH)

        -- 计算当前滚动偏移
        local scrollPos = slotScrollPos[i]
        local fracOffset = scrollPos % 1.0  -- 小数部分=当前符号内的偏移比例
        local baseIdx = math.floor(scrollPos) % SLOT_NUM_SYMBOLS  -- 当前基准符号索引

        -- 绘制可见的符号（中间行 + 上下各一行，共3行）
        local centerY = ry + reelH / 2
        for row = -1, 1 do
            local symOffset = baseIdx + row
            local symIdx = (symOffset % SLOT_NUM_SYMBOLS) + 1
            local sym = SLOT_SYMBOLS[symIdx]
            local col = SLOT_COLORS[symIdx]

            -- 符号的Y位置（向下滚动）
            local drawY = centerY + (row - fracOffset) * symbolH

            -- 越靠近中心越不透明
            local distFromCenter = math.abs(drawY - centerY)
            local alpha = math.max(60, math.floor(255 - distFromCenter * 4))

            nvgFontSize(vg, 20)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], alpha))
            nvgText(vg, rx + reelW / 2, drawY, sym)
        end

        nvgResetScissor(vg)
        nvgRestore(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx, ry, reelW, reelH, 5)
        if slotStopped[i] then
            nvgStrokeColor(vg, nvgRGBA(50, 255, 100, 200))
        elseif slotStopping[i] then
            nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 200))
        else
            nvgStrokeColor(vg, nvgRGBA(80, 80, 120, 200))
        end
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 中线指示（对准线）
        nvgBeginPath(vg)
        nvgMoveTo(vg, rx + 2, ry + reelH / 2)
        nvgLineTo(vg, rx + 6, ry + reelH / 2)
        nvgMoveTo(vg, rx + reelW - 6, ry + reelH / 2)
        nvgLineTo(vg, rx + reelW - 2, ry + reelH / 2)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 50, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 状态/结果
    local statusY = reelAreaY + reelH + 25
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if slotPhase == "idle" then
        if slotResult and slotResult ~= "win" and slotResult ~= "steal" then
            nvgFillColor(vg, nvgRGBA(255, 180, 80, 255))
            nvgText(vg, panelX + panelW / 2, statusY, slotResult)
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 220, 255))
            nvgText(vg, panelX + panelW / 2, statusY, "点击 [开始] 试试说服他！")
        end
    elseif slotPhase == "spinning" then
        local stoppedCount = 0
        for i = 1, 3 do if slotStopped[i] then stoppedCount = stoppedCount + 1 end end
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
        nvgText(vg, panelX + panelW / 2, statusY, "谈判中... 点击停止 (" .. stoppedCount .. "/3)")
    elseif slotPhase == "result" then
        if slotResult == "win" then
            nvgFillColor(vg, nvgRGBA(50, 255, 100, 255))
            nvgText(vg, panelX + panelW / 2, statusY, "成功！他借你充电宝了！")
        elseif slotResult == "steal" then
            nvgFillColor(vg, nvgRGBA(255, 50, 50, 255))
            nvgText(vg, panelX + panelW / 2, statusY, "糟糕！他抢走了你的手机！")
        elseif slotResult == "refuse" then
            nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
            nvgText(vg, panelX + panelW / 2, statusY, "他不耐烦了，拒绝和你谈...")
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 220, 255))
            nvgText(vg, panelX + panelW / 2, statusY, slotResult)
        end
    end

    -- 操作按钮（可点击，带 hover/pressed 反馈）
    local btnY = panelY + panelH - 50
    local btnW = 100
    local btnH = 30
    local btnGap = 20
    local actionBtnX = panelX + panelW / 2 - btnW - btnGap / 2
    local closeBtnX = panelX + panelW / 2 + btnGap / 2

    -- 主操作按钮
    local actionText = ""
    if slotPhase == "idle" then actionText = "开始说服"
    elseif slotPhase == "spinning" then actionText = "停止"
    elseif slotPhase == "result" then
        if slotResult == "refuse" then
            actionText = "离开"
        else
            actionText = "确认"
        end
    end

    local actionHover = (hoveredBtn == "slot_action")
    local actionPressed = (pressedBtn == "slot_action" and mousePressed)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, actionBtnX, btnY, btnW, btnH, 6)
    if actionPressed then
        nvgFillColor(vg, nvgRGBA(100, 230, 150, 255))
    elseif actionHover then
        nvgFillColor(vg, nvgRGBA(80, 200, 120, 240))
    else
        nvgFillColor(vg, nvgRGBA(50, 150, 80, 220))
    end
    nvgFill(vg)
    if actionHover or actionPressed then
        nvgStrokeColor(vg, nvgRGBA(150, 255, 180, 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, actionBtnX + btnW / 2, btnY + btnH / 2, actionText)

    -- 放弃按钮（result时不显示，只显示确认）
    if slotPhase ~= "result" then
        local closeHover = (hoveredBtn == "slot_close")
        local closePressed = (pressedBtn == "slot_close" and mousePressed)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, closeBtnX, btnY, btnW, btnH, 6)
        if closePressed then
            nvgFillColor(vg, nvgRGBA(230, 100, 100, 255))
        elseif closeHover then
            nvgFillColor(vg, nvgRGBA(200, 80, 80, 240))
        else
            nvgFillColor(vg, nvgRGBA(140, 60, 60, 220))
        end
        nvgFill(vg)
        if closeHover or closePressed then
            nvgStrokeColor(vg, nvgRGBA(255, 150, 150, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, closeBtnX + btnW / 2, btnY + btnH / 2, "放弃")
    end
end

-- ====================================================================
-- 贷款流程 NanoVG 渲染
-- ====================================================================
local _lastLoggedLoanState = nil  -- 避免每帧重复日志

function RenderLoanFlow(vg, sw, sh)
    if not LoanApp.IsActive() then return end
    local loanState = LoanApp.GetState()
    if loanState == "idle" then return end

    -- 广告状态：由 PhoneUI.ShowAd() 在手机内显示，这里不绘制任何东西
    if loanState == "ad_before" or loanState == "ad_after_code" or LoanApp.IsAdShowing() then
        return
    end

    -- 状态变化时记录一次日志
    if loanState ~= _lastLoggedLoanState then
        DiagLog.Log("渲染", "贷款面板渲染中, 状态=" .. loanState)
        _lastLoggedLoanState = loanState
    end

    -- 获取手机内容区域，将渲染裁剪到手机屏幕内
    local phoneRect = PhoneUI.GetPhoneContentRect(sw, sh)
    if not phoneRect then return end  -- 手机不可见时不渲染

    -- 设置裁剪区域 = 手机内容区域
    nvgSave(vg)
    nvgScissor(vg, phoneRect.x, phoneRect.y, phoneRect.w, phoneRect.h)

    -- 手机内容区域内的暗色背景
    nvgBeginPath(vg)
    nvgRect(vg, phoneRect.x, phoneRect.y, phoneRect.w, phoneRect.h)
    nvgFillColor(vg, nvgRGBA(10, 12, 25, 240))
    nvgFill(vg)

    -- 面板尺寸（适配手机内容区域）
    local panelW = math.min(250, phoneRect.w - 10)
    local panelH = 220
    local panelX = phoneRect.x + (phoneRect.w - panelW) / 2
    local panelY = phoneRect.y + (phoneRect.h - panelH) / 2
    local centerX = phoneRect.x + phoneRect.w / 2

    -- 绘制面板背景
    local function DrawPanel(title, h)
        h = h or panelH
        local py = phoneRect.y + (phoneRect.h - h) / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX, py, panelW, h, 10)
        nvgFillColor(vg, nvgRGBA(25, 30, 50, 245))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 140, 255, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 255))
        nvgText(vg, centerX, py + 12, title)
        return py
    end

    -- 绘制输入框
    local function DrawInputField(x, y, w, text, maxLen, placeholder)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, 28, 5)
        nvgFillColor(vg, nvgRGBA(15, 15, 30, 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(60, 100, 200, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 文字
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if #text > 0 then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            local displayText = text
            if math.floor(gs.totalTime * 2) % 2 == 0 then
                displayText = displayText .. "|"
            end
            nvgText(vg, x + 8, y + 14, displayText)
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 140, 180))
            nvgText(vg, x + 8, y + 14, placeholder or "")
        end
        -- 位数提示
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 100, 140, 180))
        nvgText(vg, x + w - 6, y + 14, #text .. "/" .. maxLen)
    end

    -- 错误信息
    local function DrawError(py, h)
        local err = LoanApp.GetErrorMsg()
        if err and #err > 0 then
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
            nvgText(vg, centerX, py + h - 30, err)
        end
    end

    -- ===== 各状态渲染 =====

    if loanState == "input_phone" then
        local py = DrawPanel("身份验证 - 输入手机号")
        -- 说明文字
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(160, 170, 200, 220))
        nvgText(vg, centerX, py + 40, "请输入手机号以验证身份")
        -- 输入框
        DrawInputField(panelX + 15, py + 70, panelW - 30, LoanApp.GetPhoneInput(), 12, "请输入12位手机号")
        -- 提示
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(100, 120, 160, 180))
        nvgText(vg, centerX, py + 110, "数字键输入 | Enter确认 | Esc退出")
        -- 错误
        local err = LoanApp.GetErrorMsg()
        if err and #err > 0 then
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
            nvgText(vg, centerX, py + 135, err)
        end

        -- 自言自语对话泡泡（逐渐显露手机号）
        local fullPhone = LoanApp.GetFullPhone()
        -- 根据时间逐字显露（每0.6秒显示1位）
        local elapsed = gs.totalTime - (gs.loanPhoneHintStart or gs.totalTime)
        if not gs.loanPhoneHintStart then
            gs.loanPhoneHintStart = gs.totalTime
        end
        local revealCount = math.min(#fullPhone, math.floor(elapsed / 0.6))
        local revealed = string.sub(fullPhone, 1, revealCount)
        if revealCount < #fullPhone then
            revealed = revealed .. "_"
        end

        -- 绘制思考气泡（面板下方）
        local bubbleY = py + panelH + 8
        local bubbleW = math.min(200, phoneRect.w - 20)
        local bubbleH = 36
        local bubbleX = centerX - bubbleW / 2

        -- 思考小圆点（气泡尾巴）
        nvgBeginPath(vg)
        nvgCircle(vg, centerX - 30, bubbleY - 2, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, 180))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, centerX - 20, bubbleY + 2, 4)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, 200))
        nvgFill(vg)

        -- 气泡背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bubbleX, bubbleY + 4, bubbleW, bubbleH, 8)
        nvgFillColor(vg, nvgRGBA(255, 255, 230, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 180, 100, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 气泡内文字
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(80, 60, 20, 255))
        nvgText(vg, bubbleX + 8, bubbleY + 4 + bubbleH / 2, "我的手机号是..." .. revealed)

    elseif loanState == "sms_sent" then
        local py = DrawPanel("短信验证码")
        -- 已发送提示
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(100, 220, 100, 220))
        nvgText(vg, centerX, py + 38, "验证码已发送至 " .. LoanApp.GetPhoneDisplay())
        -- 验证码输入框
        DrawInputField(panelX + 40, py + 65, panelW - 80, LoanApp.GetCodeInput(), 6, "6位验证码")
        -- 重发按钮/倒计时
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if LoanApp.CanResend() then
            nvgFillColor(vg, nvgRGBA(80, 160, 255, 255))
            nvgText(vg, centerX, py + 108, "[重新发送]")
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 140, 180))
            nvgText(vg, centerX, py + 108, "重新发送(" .. LoanApp.GetResendTimer() .. "s)")
        end
        -- 操作提示
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(100, 120, 160, 180))
        nvgText(vg, centerX, py + 130, "数字键输入 | Enter确认 | Esc退出")
        -- 错误
        local err = LoanApp.GetErrorMsg()
        if err and #err > 0 then
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
            nvgText(vg, centerX, py + 155, err)
        end

    elseif loanState == "face_game" then
        -- 人脸识别音游 - 使用手机内容区域
        local fPanelH = math.min(300, phoneRect.h - 20)
        local fPanelW = math.min(panelW + 10, phoneRect.w - 6)
        local fPanelX = phoneRect.x + (phoneRect.w - fPanelW) / 2
        local fPanelY = phoneRect.y + (phoneRect.h - fPanelH) / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, fPanelX, fPanelY, fPanelW, fPanelH, 10)
        nvgFillColor(vg, nvgRGBA(15, 20, 40, 250))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(50, 200, 100, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(100, 255, 150, 255))
        nvgText(vg, centerX, fPanelY + 8, "人脸识别验证")

        local facePhase = LoanApp.GetFacePhase()

        if facePhase == "ready" then
            -- 准备页面：详细按键说明
            local ry = fPanelY + 30
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
            nvgText(vg, centerX, ry, "请根据提示完成面部动作验证")
            ry = ry + 20

            -- 操作按键说明表
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local keyX = fPanelX + 20
            local descX = fPanelX + 55

            -- 表头
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
            nvgText(vg, keyX, ry, "按键")
            nvgText(vg, descX, ry, "动作")
            ry = ry + 4
            nvgBeginPath(vg)
            nvgMoveTo(vg, keyX, ry + 10)
            nvgLineTo(vg, fPanelX + fPanelW - 20, ry + 10)
            nvgStrokeColor(vg, nvgRGBA(60, 100, 150, 120))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            ry = ry + 14

            -- 四个按键
            local actions = {
                { key = "1", name = "眨眼", icon = "👁" },
                { key = "2", name = "张嘴", icon = "👄" },
                { key = "3", name = "摇头", icon = "↔" },
                { key = "4", name = "点头", icon = "↕" },
            }
            for _, act in ipairs(actions) do
                nvgFillColor(vg, nvgRGBA(255, 220, 100, 240))
                nvgText(vg, keyX + 5, ry, act.key)
                nvgFillColor(vg, nvgRGBA(220, 220, 240, 220))
                nvgText(vg, descX, ry, act.icon .. " " .. act.name)
                ry = ry + 16
            end
            ry = ry + 6

            -- 判定说明
            nvgFillColor(vg, nvgRGBA(140, 160, 200, 180))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgText(vg, centerX, ry, "动作出现时按对应按键，越准分越高")
            ry = ry + 14
            nvgText(vg, centerX, ry, "Perfect=4分  Great=2分  Good=1分")
            ry = ry + 14
            nvgFillColor(vg, nvgRGBA(255, 180, 80, 200))
            nvgText(vg, centerX, ry, "需要 " .. LoanApp.GetPassScore() .. " 分通过 (满分32)")
            ry = ry + 22

            -- 开始按钮提示
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(100, 255, 150, 255))
            local blink = math.floor(gs.totalTime * 2) % 2 == 0
            if blink then
                nvgText(vg, centerX, ry, "[ Enter 开始验证 ]")
            end

        elseif facePhase == "playing" or facePhase == "paused_ad" then
            -- 分数和连击
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgText(vg, fPanelX + 8, fPanelY + 28, "分数: " .. LoanApp.GetFaceScore())
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            local combo = LoanApp.GetFaceCombo()
            if combo > 1 then
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
                nvgText(vg, fPanelX + fPanelW - 8, fPanelY + 28, combo .. "x COMBO!")
            end

            -- 时间轴
            local tlX = fPanelX + 8
            local tlW = fPanelW - 16
            local tlY = fPanelY + 50
            local tlH = 4
            -- 背景线
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tlX, tlY, tlW, tlH, 2)
            nvgFillColor(vg, nvgRGBA(60, 60, 80, 200))
            nvgFill(vg)
            -- 进度指示
            local progress = LoanApp.GetFaceTimer() / LoanApp.GetFaceDuration()
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tlX, tlY, tlW * progress, tlH, 2)
            nvgFillColor(vg, nvgRGBA(50, 200, 100, 200))
            nvgFill(vg)
            -- 当前位置指针
            local cursorX2 = tlX + tlW * progress
            nvgBeginPath(vg)
            nvgCircle(vg, cursorX2, tlY + 2, 4)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgFill(vg)

            -- 节拍标记
            local beats = LoanApp.GetFaceBeats()
            for _, beat in ipairs(beats) do
                local beatX = tlX + tlW * (beat.timing / LoanApp.GetFaceDuration())
                local beatY2 = tlY + 2
                -- 圆圈
                nvgBeginPath(vg)
                nvgCircle(vg, beatX, beatY2, 5)
                if beat.judged then
                    if beat.result == "Perfect" then
                        nvgFillColor(vg, nvgRGBA(255, 215, 0, 255))
                    elseif beat.result == "Great" then
                        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
                    elseif beat.result == "Good" then
                        nvgFillColor(vg, nvgRGBA(100, 255, 100, 200))
                    else
                        nvgFillColor(vg, nvgRGBA(255, 60, 60, 200))
                    end
                else
                    nvgFillColor(vg, nvgRGBA(200, 200, 220, 150))
                end
                nvgFill(vg)
                -- 动作图标（在节拍下方显示）
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                nvgText(vg, beatX, tlY + 10, beat.action.icon)
                -- 按键提示
                nvgFontSize(vg, 8)
                nvgFillColor(vg, nvgRGBA(180, 180, 200, 160))
                nvgText(vg, beatX, tlY + 24, beat.action.key)
            end

            -- 即将到来的动作提示（大字居中）
            local nextBeat = nil
            local timer = LoanApp.GetFaceTimer()
            for _, beat in ipairs(beats) do
                if not beat.judged and beat.timing > timer - 0.1 then
                    nextBeat = beat
                    break
                end
            end
            if nextBeat then
                local timeUntil = nextBeat.timing - timer
                if timeUntil < 1.5 and timeUntil > -0.2 then
                    local alpha = 255
                    if timeUntil < 0.3 then alpha = math.floor(255 * (timeUntil / 0.3)) end
                    nvgFontSize(vg, 28)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
                    nvgText(vg, centerX, fPanelY + 130, nextBeat.action.icon)
                    nvgFontSize(vg, 11)
                    nvgFillColor(vg, nvgRGBA(200, 220, 255, alpha))
                    nvgText(vg, centerX, fPanelY + 155, "按 " .. nextBeat.action.key .. " (" .. nextBeat.action.name .. ")")
                end
            end

            -- 判定文字动画
            local judge = LoanApp.GetFaceLastJudge()
            local judgeTimer = LoanApp.GetFaceLastJudgeTimer()
            if judge and judgeTimer > 0 then
                local jAlpha = math.floor(255 * math.min(1, judgeTimer / 0.5))
                local jY = fPanelY + 200 - (1 - judgeTimer) * 12
                nvgFontSize(vg, 16)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if judge == "Perfect" then
                    nvgFillColor(vg, nvgRGBA(255, 215, 0, jAlpha))
                elseif judge == "Great" then
                    nvgFillColor(vg, nvgRGBA(100, 200, 255, jAlpha))
                elseif judge == "Good" then
                    nvgFillColor(vg, nvgRGBA(100, 255, 100, jAlpha))
                else
                    nvgFillColor(vg, nvgRGBA(255, 60, 60, jAlpha))
                end
                nvgText(vg, centerX, jY, judge)
            end

            -- 暂停提示（广告弹出时）
            if facePhase == "paused_ad" then
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
                nvgText(vg, centerX, fPanelY + fPanelH - 30, "广告中... 关闭后继续")
            end

            -- 按键说明（底部）
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(120, 140, 180, 160))
            nvgText(vg, centerX, fPanelY + fPanelH - 6, "1=眨眼 2=张嘴 3=摇头 4=点头")
        end

    elseif loanState == "face_result" then
        local py = DrawPanel("人脸验证通过", 200)
        -- 成功图标
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 255, 120, 255))
        nvgText(vg, centerX, py + 38, "✓")
        -- 贷款信息
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
        nvgText(vg, centerX, py + 75, "贷款申请成功")
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
        nvgText(vg, centerX, py + 95, "额度:¥" .. LoanApp.GetLoanLimit() .. " 利率:" .. LoanApp.GetLoanRate())
        -- 提示
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(120, 160, 200, 180))
        nvgText(vg, centerX, py + 125, "按 Enter 继续")

    elseif loanState == "loan_input" then
        local py = DrawPanel("选择贷款金额", 200)
        -- 额度信息
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
        nvgText(vg, centerX, py + 38, "可用额度: ¥" .. LoanApp.GetLoanLimit())
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 180, 80, 200))
        nvgText(vg, centerX, py + 55, "月利率 " .. LoanApp.GetLoanRate() .. " (请谨慎借贷)")
        -- 金额输入
        DrawInputField(panelX + 30, py + 75, panelW - 60, LoanApp.GetLoanInput(), 3, "输入金额")
        -- 操作提示
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(100, 120, 160, 180))
        nvgText(vg, centerX, py + 118, "数字键输入 | Enter确认 | Esc退出")
        -- 错误
        local err = LoanApp.GetErrorMsg()
        if err and #err > 0 then
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
            nvgText(vg, centerX, py + 140, err)
        end

    elseif loanState == "loan_done" then
        local py = DrawPanel("贷款到账", 170)
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 255, 120, 255))
        nvgText(vg, centerX, py + 38, "¥" .. LoanApp.GetLoanInput())
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 200))
        nvgText(vg, centerX, py + 72, "已到账至余额")
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 180, 80, 180))
        nvgText(vg, centerX, py + 95, "请于月底前还款，逾期上报征信")
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(100, 120, 160, 180))
        nvgText(vg, centerX, py + 120, "按 Enter 关闭")

    elseif loanState == "failed" then
        local py = DrawPanel("验证失败", 260)
        -- 失败图标
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgText(vg, centerX, py + 25, "✗")
        -- 分数
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
        nvgText(vg, centerX, py + 50, "识别分数: " .. LoanApp.GetFaceScore() .. "/" .. LoanApp.GetPassScore())
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(255, 180, 80, 200))
        nvgText(vg, centerX, py + 66, "人脸识别未通过，请重试")

        -- 按键教程（帮助玩家理解操作）
        local tutY = py + 86
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 180))
        nvgText(vg, centerX, tutY, "-- 操作提示 --")
        tutY = tutY + 14
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local keyX = phoneRect.x + (phoneRect.w - panelW) / 2 + 25
        local actions = {
            { key = "1", name = "眨眼", icon = "👁" },
            { key = "2", name = "张嘴", icon = "👄" },
            { key = "3", name = "摇头", icon = "↔" },
            { key = "4", name = "点头", icon = "↕" },
        }
        for _, act in ipairs(actions) do
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
            nvgText(vg, keyX, tutY, "按 " .. act.key)
            nvgFillColor(vg, nvgRGBA(200, 210, 230, 200))
            nvgText(vg, keyX + 35, tutY, "→ " .. act.icon .. " " .. act.name)
            tutY = tutY + 13
        end
        tutY = tutY + 4
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(140, 160, 200, 160))
        nvgText(vg, centerX, tutY, "节拍出现时按对应键，越准分越高")

        -- 操作
        tutY = tutY + 16
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(100, 255, 150, 200))
        nvgText(vg, centerX, tutY, "Enter=重试 | Esc=放弃")
    end

    -- ===== SMS 横幅（手机内容区顶部）=====
    if LoanApp.IsSmsVisible() then
        local smsY = phoneRect.y + LoanApp.GetSmsSlideY()
        local smsW = math.min(240, phoneRect.w - 10)
        local smsH = 48
        local smsX = phoneRect.x + (phoneRect.w - smsW) / 2
        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, smsX, smsY, smsW, smsH, 8)
        nvgFillColor(vg, nvgRGBA(40, 45, 60, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 255, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 短信图标 + 标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(140, 160, 200, 200))
        nvgText(vg, smsX + 8, smsY + 5, "短信")
        -- 内容
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, smsX + 8, smsY + 18, "【极速贷】验证码: " .. LoanApp.GetVerifyCode())
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(140, 160, 200, 160))
        nvgText(vg, smsX + 8, smsY + 34, "5分钟内有效，请勿告知他人")
    end

    -- 恢复裁剪状态
    nvgRestore(vg)
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
        -- 商店室内场景
        if gs.phase == Config.State.SHOP then
            ShopScene.Render(nvg, screenW, screenH)
        else
            -- 渲染城市世界
            WorldRenderer.Render(nvg, gs.cameraX, screenW, screenH)

            -- 渲染玩家
            local playerScreenX = gs.playerX - gs.cameraX
            WorldRenderer.RenderPlayer(nvg, playerScreenX, gs.playerY, gs.facingRight, gs.phoneOpen)

            -- 追击时渲染店主和HUD
            if gs.phase == Config.State.CHASE and chaseActive then
                RenderChase(nvg, screenW, screenH)
            end
        end

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

        -- NPC 对话面板（EVENT状态覆盖在城市之上）
        if npcDialogueOpen then
            RenderNPCDialogue(nvg, screenW, screenH)
        end

        -- 老虎机博弈面板
        if slotGameOpen then
            RenderSlotGame(nvg, screenW, screenH)
        end

    end

    nvgEndFrame(nvg)
end

-- ====================================================================
-- Overlay 渲染（在 UI 系统之上，renderOrder=999995）
-- 贷款流程/低电量HUD/诊断日志在这里绘制，不会被手机UI遮挡
-- ====================================================================
function HandleOverlayRender(eventType, eventData)
    if not nvgOverlay then return end

    local dpr = graphics:GetDPR()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()

    nvgBeginFrame(nvgOverlay, physW, physH, dpr)

    if gs.phase ~= Config.State.MENU then
        -- 贷款流程面板（覆盖在手机UI之上）
        if gs.phoneOpen and LoanApp.IsActive() then
            RenderLoanFlow(nvgOverlay, screenW, screenH)
        end
        -- 首帧检测：如果贷款Active但phoneOpen为false，说明条件不满足
        if LoanApp.IsActive() and not gs.phoneOpen and _lastLoggedLoanState ~= "blocked_no_phone" then
            DiagLog.Log("错误", "贷款IsActive=true但phoneOpen=false, 渲染被跳过!")
            _lastLoggedLoanState = "blocked_no_phone"
        end

        -- 低电量倒计时由 PhoneUI 的 UI 组件覆盖层处理（已在手机内部正确显示）
        -- 不再使用 NanoVG overlay 绘制（会超出手机边界）
    end

    -- 诊断日志浮层（最顶层，始终可渲染）
    DiagLog.Render(nvgOverlay, screenW, screenH)

    nvgEndFrame(nvgOverlay)
end

