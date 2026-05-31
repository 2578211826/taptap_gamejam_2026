-- ====================================================================
-- InternetCafeScene.lua - 网吧室内场景
-- ====================================================================
-- 网吧内部场景：电脑区、网管NPC（老虎机）、充电宝柜、USB充电位
-- ====================================================================

local Config = require("Config")
local AudioManager = require("AudioManager")
local PowerbankSystem = require("PowerbankSystem")

local InternetCafeScene = {}

-- 场景状态
local active = false
local nvg = nil
local screenW, screenH = 0, 0
local gameState = nil
local buildingIdx = 0

-- 布局常量
local CAFE_WIDTH = 950
local FLOOR_Y = 0
local CEILING_H = 55

-- 玩家
local playerX = 80
local playerSpeed = 200
local facingRight = true

-- 可交互区域
local interactZones = {}
local nearbyZone = nil

-- 回调
local onExitCallback = nil

-- NPC 对话状态
local npcDialogOpen = false
local npcDialogText = ""
local npcDialogOptions = {}
local npcDialogChoice = 1

-- USB充电状态
local usbCharging = false
local usbChargeTimer = 0
local USB_CHARGE_TIME = 5.0      -- 5秒充1格
local USB_CHARGE_AMOUNT = 3      -- 每次充3格电

-- 充电宝柜交互状态
local cafeStationId = nil        -- 本网吧的充电宝柜ID

-- 电脑装饰动画
local computerGlow = 0

-- 鼠标 hover/pressed 状态
local hoveredBtn = nil
local pressedBtn = nil

-- ====================================================================
-- 初始化
-- ====================================================================
function InternetCafeScene.Init(nvgCtx, sw, sh)
    nvg = nvgCtx
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100
end

-- ====================================================================
-- 进入/离开网吧
-- ====================================================================
function InternetCafeScene.Enter(gs, buildingIndex, exitCallback)
    active = true
    gameState = gs
    buildingIdx = buildingIndex
    playerX = 80
    facingRight = true
    onExitCallback = exitCallback
    nearbyZone = nil
    npcDialogOpen = false
    usbCharging = false
    usbChargeTimer = 0
    computerGlow = 0

    -- 网吧内充电宝柜ID（与 WorldRenderer 中注册的一致）
    cafeStationId = "pb_cafe_" .. buildingIndex

    -- 构建交互区域
    interactZones = {
        { x = 40,  w = 60,  type = "door",      label = "离开网吧" },
        { x = 250, w = 100, type = "computer",   label = "USB充电位" },
        { x = 450, w = 80,  type = "npc",        label = "网管" },
        { x = 700, w = 80,  type = "powerbank",  label = "充电宝柜" },
    }

    -- 注册网吧内充电宝柜到全局系统（如果还没注册）
    local existing = PowerbankSystem.GetById(cafeStationId)
    if not existing then
        PowerbankSystem.Register(cafeStationId, buildingIndex, 700, "网吧内")
    end

    print("[InternetCafe] 进入网吧 (building=" .. buildingIndex .. ")")
end

function InternetCafeScene.Exit()
    active = false
    nearbyZone = nil
    usbCharging = false
    if onExitCallback then
        onExitCallback()
    end
    print("[InternetCafe] 离开网吧")
end

function InternetCafeScene.IsActive()
    return active
end

-- ====================================================================
-- 更新
-- ====================================================================
function InternetCafeScene.Update(dt)
    if not active then return end

    -- 电脑发光动画
    computerGlow = computerGlow + dt

    -- NPC 对话时不允许移动
    if npcDialogOpen then return end

    -- USB充电中
    if usbCharging then
        usbChargeTimer = usbChargeTimer + dt
        if usbChargeTimer >= USB_CHARGE_TIME then
            -- 充电完成
            usbCharging = false
            usbChargeTimer = 0
            if gameState then
                gameState.battery = math.min(gameState.battery + USB_CHARGE_AMOUNT, 100)
                gameState.stats.chargeCount = (gameState.stats.chargeCount or 0) + 1
                print("[InternetCafe] USB充电完成 +" .. USB_CHARGE_AMOUNT .. "% 当前:" .. gameState.battery .. "%")
            end
        end
        return  -- 充电中不能移动
    end

    -- 玩家移动
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        playerX = playerX - playerSpeed * dt
        facingRight = false
    end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        playerX = playerX + playerSpeed * dt
        facingRight = true
    end

    -- 边界限制
    playerX = math.max(40, math.min(playerX, CAFE_WIDTH - 40))

    -- 检测附近交互区
    nearbyZone = nil
    for _, zone in ipairs(interactZones) do
        local zoneCenter = zone.x + zone.w / 2
        if math.abs(playerX - zoneCenter) < zone.w / 2 + 30 then
            nearbyZone = zone
            break
        end
    end
end

-- ====================================================================
-- 按F交互
-- ====================================================================
function InternetCafeScene.OnInteract()
    if not active then return false end
    if npcDialogOpen then return false end
    if usbCharging then return false end
    if not nearbyZone then return false end

    if nearbyZone.type == "door" then
        InternetCafeScene.Exit()
        return true

    elseif nearbyZone.type == "computer" then
        -- USB充电：慢速但免费
        if gameState.battery >= 100 then
            -- 已满电
            npcDialogOpen = true
            npcDialogText = "电量已满，不需要充电了。"
            npcDialogOptions = { { text = "好的", action = "close" } }
            npcDialogChoice = 1
        else
            usbCharging = true
            usbChargeTimer = 0
            AudioManager.Interact()
            print("[InternetCafe] 开始USB充电...")
        end
        return true

    elseif nearbyZone.type == "npc" then
        -- 网管对话 → 老虎机博弈
        AudioManager.NpcTalk()
        OpenNPCDialog()
        return true

    elseif nearbyZone.type == "powerbank" then
        -- 充电宝柜交互
        local canUse, msg = PowerbankSystem.CanUse(cafeStationId)
        if not canUse then
            npcDialogOpen = true
            npcDialogText = msg
            npcDialogOptions = { { text = "知道了", action = "close" } }
            npcDialogChoice = 1
        else
            -- 提示需要扫码
            npcDialogOpen = true
            npcDialogText = "充电宝柜可用！\n需要用手机扫码才能借用。"
            npcDialogOptions = {
                { text = "打开手机扫码", action = "scan" },
                { text = "算了", action = "close" },
            }
            npcDialogChoice = 1
        end
        return true
    end

    return false
end

-- ====================================================================
-- NPC 对话
-- ====================================================================
function OpenNPCDialog()
    npcDialogOpen = true
    npcDialogChoice = 1
    npcDialogText = "网管：哟，充手机的？\n想在这充电得先赢我一把！"
    npcDialogOptions = {
        { text = "来吧（老虎机）", action = "gamble" },
        { text = "算了不玩", action = "close" },
    }
end

function InternetCafeScene.CloseDialog()
    npcDialogOpen = false
    npcDialogOptions = {}
end

function InternetCafeScene.DialogConfirm()
    if not npcDialogOpen then return end
    local option = npcDialogOptions[npcDialogChoice]
    if not option then return end

    if option.action == "close" then
        InternetCafeScene.CloseDialog()

    elseif option.action == "gamble" then
        -- 切换到老虎机博弈（复用 main.lua 的全局老虎机系统）
        InternetCafeScene.CloseDialog()
        -- 通过修改 gs.phase 触发 main.lua 的老虎机
        -- 调用全局 OpenSlotGame 函数
        if OpenSlotGame then
            OpenSlotGame()
        end

    elseif option.action == "scan" then
        -- 打开手机扫码
        InternetCafeScene.CloseDialog()
        if gameState then
            gameState.phoneOpen = true
            gameState.phase = Config.State.PHONE
            -- PhoneUI 会处理后续扫码流程
        end
    end
end

function InternetCafeScene.DialogNavigate(dir)
    if not npcDialogOpen or #npcDialogOptions == 0 then return end
    npcDialogChoice = npcDialogChoice + dir
    if npcDialogChoice < 1 then npcDialogChoice = #npcDialogOptions end
    if npcDialogChoice > #npcDialogOptions then npcDialogChoice = 1 end
end

function InternetCafeScene.IsDialogOpen()
    return npcDialogOpen
end

function InternetCafeScene.IsUsbCharging()
    return usbCharging
end

-- ====================================================================
-- 鼠标支持
-- ====================================================================
function InternetCafeScene.SetHoverState(hovered, pressed)
    hoveredBtn = hovered
    pressedBtn = pressed
end

function InternetCafeScene.GetButtonAtPosition(mx, my)
    if not npcDialogOpen then return nil end

    -- 对话面板按钮检测
    local panelW = 340
    local panelH = 180
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2
    local optStartY = panelY + panelH - 20 - #npcDialogOptions * 32

    for i = 1, #npcDialogOptions do
        local oy = optStartY + (i - 1) * 32
        local btnLeft = panelX + 20
        local btnRight = panelX + panelW - 20
        if mx >= btnLeft and mx <= btnRight and my >= oy and my <= oy + 28 then
            return "cafe_dialog_" .. i
        end
    end
    return nil
end

function InternetCafeScene.ExecuteButtonClick(btnId)
    if not btnId then return false end

    if btnId:sub(1, 12) == "cafe_dialog_" then
        local idx = tonumber(btnId:sub(13))
        if idx and idx >= 1 and idx <= #npcDialogOptions then
            npcDialogChoice = idx
            InternetCafeScene.DialogConfirm()
        end
        return true
    end

    return false
end

-- ====================================================================
-- 获取当前附近交互区
-- ====================================================================
function InternetCafeScene.GetNearbyZone()
    return nearbyZone
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================
function InternetCafeScene.Render(nvgCtx, sw, sh)
    if not active then return end
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100

    -- 背景（网吧暗色调）
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(25, 20, 35, 255))
    nvgFill(nvgCtx)

    -- 地板（深色地毯）
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, FLOOR_Y, screenW, screenH - FLOOR_Y)
    nvgFillColor(nvgCtx, nvgRGBA(40, 35, 50, 255))
    nvgFill(nvgCtx)

    -- 地毯纹理
    nvgStrokeColor(nvgCtx, nvgRGBA(50, 45, 60, 120))
    nvgStrokeWidth(nvgCtx, 1)
    for i = 0, math.ceil(screenW / 40) do
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, i * 40, FLOOR_Y)
        nvgLineTo(nvgCtx, i * 40, screenH)
        nvgStroke(nvgCtx)
    end

    -- 天花板（暗色）
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, CEILING_H)
    nvgFillColor(nvgCtx, nvgRGBA(15, 12, 25, 255))
    nvgFill(nvgCtx)

    -- LED灯条（蓝紫色）
    for i = 1, 4 do
        local lx = screenW * i / 5
        local pulse = math.sin(computerGlow * 2 + i) * 0.3 + 0.7
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, lx - 35, CEILING_H - 5, 70, 4)
        nvgFillColor(nvgCtx, nvgRGBA(100, 50, 255, math.floor(180 * pulse)))
        nvgFill(nvgCtx)
        -- 光晕
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, lx - 50, CEILING_H, 100, 12)
        nvgFillColor(nvgCtx, nvgRGBA(80, 40, 200, math.floor(25 * pulse)))
        nvgFill(nvgCtx)
    end

    -- 后墙装饰线（霓虹）
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, CEILING_H, screenW, 2)
    nvgFillColor(nvgCtx, nvgRGBA(0, 200, 255, 150))
    nvgFill(nvgCtx)

    -- 渲染门
    RenderCafeDoor(nvgCtx)

    -- 渲染电脑区
    RenderComputers(nvgCtx)

    -- 渲染网管NPC
    RenderNPC(nvgCtx)

    -- 渲染充电宝柜
    RenderPowerbankStation(nvgCtx)

    -- 渲染玩家
    RenderCafePlayer(nvgCtx)

    -- 交互提示
    if nearbyZone and not npcDialogOpen and not usbCharging then
        RenderCafeInteractPrompt(nvgCtx)
    end

    -- USB充电进度条
    if usbCharging then
        RenderUSBCharging(nvgCtx)
    end

    -- NPC对话面板
    if npcDialogOpen then
        RenderNPCDialog(nvgCtx)
    end
end

-- ====================================================================
-- 子渲染函数
-- ====================================================================

function RenderCafeDoor(nvgCtx)
    local dx = 40
    local dw = 50
    local dh = 90
    local dy = FLOOR_Y - dh

    -- 门框
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx - 3, dy - 3, dw + 6, dh + 3)
    nvgFillColor(nvgCtx, nvgRGBA(50, 40, 60, 255))
    nvgFill(nvgCtx)
    -- 门板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx, dy, dw, dh)
    nvgFillColor(nvgCtx, nvgRGBA(80, 60, 90, 255))
    nvgFill(nvgCtx)
    -- 门把手
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, dx + dw - 10, dy + dh / 2, 4)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 255))
    nvgFill(nvgCtx)
    -- EXIT标志
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(0, 255, 100, 255))
    nvgText(nvgCtx, dx + dw / 2, dy - 12, "EXIT")
end

function RenderComputers(nvgCtx)
    -- 电脑桌区域（3台电脑）
    local startX = 180
    local deskW = 70
    local deskGap = 20

    for i = 1, 3 do
        local cx = startX + (i - 1) * (deskW + deskGap)
        local deskH = 50
        local deskY = FLOOR_Y - deskH

        -- 桌子
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cx, deskY, deskW, deskH, 3)
        nvgFillColor(nvgCtx, nvgRGBA(60, 50, 70, 255))
        nvgFill(nvgCtx)

        -- 显示器
        local monW = 45
        local monH = 35
        local monX = cx + (deskW - monW) / 2
        local monY = deskY - monH - 5

        -- 显示器外框
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, monX - 2, monY - 2, monW + 4, monH + 4, 3)
        nvgFillColor(nvgCtx, nvgRGBA(20, 20, 30, 255))
        nvgFill(nvgCtx)

        -- 屏幕（动态发光）
        local glow = math.sin(computerGlow * 1.5 + i * 1.2) * 0.2 + 0.8
        local screenColors = {
            { 30, 80, 200 },   -- 蓝屏
            { 40, 180, 80 },   -- 绿屏（游戏）
            { 180, 50, 50 },   -- 红屏（直播）
        }
        local sc = screenColors[i]
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, monX, monY, monW, monH)
        nvgFillColor(nvgCtx, nvgRGBA(
            math.floor(sc[1] * glow),
            math.floor(sc[2] * glow),
            math.floor(sc[3] * glow), 255))
        nvgFill(nvgCtx)

        -- 显示器支架
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, cx + deskW / 2 - 3, deskY - 5, 6, 5)
        nvgFillColor(nvgCtx, nvgRGBA(40, 40, 50, 255))
        nvgFill(nvgCtx)

        -- 键盘
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cx + 8, deskY + 5, 35, 12, 2)
        nvgFillColor(nvgCtx, nvgRGBA(30, 30, 40, 255))
        nvgFill(nvgCtx)

        -- 椅子
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cx + deskW / 2 - 12, FLOOR_Y - 35, 24, 30, 4)
        nvgFillColor(nvgCtx, nvgRGBA(40, 40, 55, 255))
        nvgFill(nvgCtx)

        -- USB标识（在第2台电脑上方）
        if i == 2 then
            nvgFontSize(nvgCtx, 8)
            nvgFontFace(nvgCtx, "sans")
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(0, 200, 100, 200))
            nvgText(nvgCtx, cx + deskW / 2, deskY - monH - 14, "⚡USB")
        end
    end

    -- "电脑区"标签
    nvgFontSize(nvgCtx, 10)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(100, 100, 140, 200))
    nvgText(nvgCtx, startX + (3 * deskW + 2 * deskGap) / 2, FLOOR_Y + 5, "电脑区 (USB充电)")
end

function RenderNPC(nvgCtx)
    -- 网管位置
    local npcX = 470
    local npcY = FLOOR_Y

    -- 网管柜台
    local counterW = 80
    local counterH = 50
    local counterX = npcX - counterW / 2
    local counterY = FLOOR_Y - counterH

    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, counterX, counterY, counterW, counterH, 4)
    nvgFillColor(nvgCtx, nvgRGBA(60, 50, 70, 255))
    nvgFill(nvgCtx)

    -- 柜台面板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, counterX + 5, counterY + 3, counterW - 10, 12)
    nvgFillColor(nvgCtx, nvgRGBA(80, 70, 100, 255))
    nvgFill(nvgCtx)

    -- NPC身体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, npcX - 12, npcY - 55, 24, 35, 4)
    nvgFillColor(nvgCtx, nvgRGBA(50, 50, 60, 255))
    nvgFill(nvgCtx)
    -- 帽子（网管标志）
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, npcX - 10, npcY - 78, 20, 10, 3)
    nvgFillColor(nvgCtx, nvgRGBA(200, 50, 50, 255))
    nvgFill(nvgCtx)
    -- 头
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, npcX, npcY - 65, 12)
    nvgFillColor(nvgCtx, nvgRGBA(240, 200, 160, 255))
    nvgFill(nvgCtx)
    -- 腿
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, npcX - 7, npcY - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(30, 30, 45, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, npcX + 2, npcY - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(30, 30, 45, 255))
    nvgFill(nvgCtx)

    -- 名牌
    nvgFontSize(nvgCtx, 8)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, npcX - 14, npcY - 42, 28, 12, 2)
    nvgFillColor(nvgCtx, nvgRGBA(200, 50, 50, 200))
    nvgFill(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, npcX, npcY - 36, "网管")
end

function RenderPowerbankStation(nvgCtx)
    -- 充电宝柜
    local pbX = 680
    local pbW = 60
    local pbH = 80
    local pbY = FLOOR_Y - pbH

    -- 柜体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, pbX, pbY, pbW, pbH, 4)
    nvgFillColor(nvgCtx, nvgRGBA(70, 70, 80, 255))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 100, 120, 200))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 充电宝槽位（4格）
    for row = 1, 4 do
        local slotY = pbY + 8 + (row - 1) * 18
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, pbX + 6, slotY, pbW - 12, 14, 2)
        nvgFillColor(nvgCtx, nvgRGBA(40, 40, 50, 255))
        nvgFill(nvgCtx)

        -- 状态指示灯
        local station = PowerbankSystem.GetById(cafeStationId)
        local stateColor = { 50, 255, 100 }  -- 默认绿色（可用）
        if station then
            if station.state == PowerbankSystem.State.EMPTY then
                stateColor = { 255, 200, 50 }
            elseif station.state == PowerbankSystem.State.OFFLINE then
                stateColor = { 150, 150, 150 }
            end
        end

        -- 只有 row <= 2 且可用时显示充电宝
        if station and station.state == PowerbankSystem.State.AVAILABLE and row <= 2 then
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, pbX + 9, slotY + 2, pbW - 18, 10, 2)
            nvgFillColor(nvgCtx, nvgRGBA(50, 200, 100, 200))
            nvgFill(nvgCtx)
        end
    end

    -- 状态灯
    local station = PowerbankSystem.GetById(cafeStationId)
    local ledColor = { 50, 255, 100 }
    if station then
        if station.state == PowerbankSystem.State.EMPTY then
            ledColor = { 255, 200, 50 }
        elseif station.state == PowerbankSystem.State.OFFLINE then
            ledColor = { 150, 150, 150 }
        end
    end
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, pbX + pbW / 2, pbY - 6, 4)
    nvgFillColor(nvgCtx, nvgRGBA(ledColor[1], ledColor[2], ledColor[3], 255))
    nvgFill(nvgCtx)

    -- 标签
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(100, 100, 140, 200))
    nvgText(nvgCtx, pbX + pbW / 2, FLOOR_Y + 5, "充电宝柜")
end

function RenderCafePlayer(nvgCtx)
    local px = playerX
    local py = FLOOR_Y

    -- 腿
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, px - 6, py - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(60, 60, 80, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, px + 1, py - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(60, 60, 80, 255))
    nvgFill(nvgCtx)

    -- 身体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px - 10, py - 50, 20, 30, 4)
    nvgFillColor(nvgCtx, nvgRGBA(180, 80, 180, 255))
    nvgFill(nvgCtx)

    -- 头
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, px, py - 60, 10)
    nvgFillColor(nvgCtx, nvgRGBA(240, 200, 160, 255))
    nvgFill(nvgCtx)

    -- 眼睛
    local eyeOffset = facingRight and 3 or -3
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, px + eyeOffset - 2, py - 62, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, px + eyeOffset + 2, py - 62, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)
end

function RenderCafeInteractPrompt(nvgCtx)
    if not nearbyZone then return end

    local text = "[F] " .. nearbyZone.label
    local tx = playerX
    local ty = FLOOR_Y - 85

    nvgFontSize(nvgCtx, 12)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local tw = nvgTextBounds(nvgCtx, 0, 0, text)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, tx - tw / 2 - 8, ty - 10, tw + 16, 20, 6)
    nvgFillColor(nvgCtx, nvgRGBA(20, 20, 40, 220))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 80, 255, 200))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    nvgFillColor(nvgCtx, nvgRGBA(200, 180, 255, 255))
    nvgText(nvgCtx, tx, ty, text)
end

function RenderUSBCharging(nvgCtx)
    -- 充电进度条（屏幕中央）
    local barW = 200
    local barH = 20
    local barX = (screenW - barW) / 2
    local barY = screenH / 2 - 40

    -- 背景遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 100))
    nvgFill(nvgCtx)

    -- 提示文字
    nvgFontSize(nvgCtx, 14)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(0, 220, 100, 255))
    nvgText(nvgCtx, screenW / 2, barY - 20, "⚡ USB充电中...")

    -- 进度条背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, barX, barY, barW, barH, 5)
    nvgFillColor(nvgCtx, nvgRGBA(30, 30, 50, 230))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(0, 200, 100, 200))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 进度条填充
    local progress = usbChargeTimer / USB_CHARGE_TIME
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, barX + 2, barY + 2, (barW - 4) * progress, barH - 4, 3)
    nvgFillColor(nvgCtx, nvgRGBA(0, 220, 100, 255))
    nvgFill(nvgCtx)

    -- 百分比
    nvgFontSize(nvgCtx, 11)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, screenW / 2, barY + barH + 15,
        string.format("%.0f%%  (+" .. USB_CHARGE_AMOUNT .. "%%电量)", progress * 100))
end

function RenderNPCDialog(nvgCtx)
    -- 半透明遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 130))
    nvgFill(nvgCtx)

    -- 对话面板
    local panelW = 340
    local panelH = 180
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    -- 面板背景（网吧风格 暗紫）
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvgCtx, nvgRGBA(30, 20, 45, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 60, 200, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- NPC头像
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, panelX + 28, panelY + 28, 16)
    nvgFillColor(nvgCtx, nvgRGBA(200, 50, 50, 255))
    nvgFill(nvgCtx)
    nvgFontSize(nvgCtx, 10)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, panelX + 28, panelY + 28, "管")

    -- 名字
    nvgFontSize(nvgCtx, 11)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(200, 150, 255, 255))
    nvgText(nvgCtx, panelX + 50, panelY + 24, "网管")

    -- 对话文本
    nvgFontSize(nvgCtx, 12)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(220, 220, 240, 255))

    local lines = {}
    for line in npcDialogText:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    for i, line in ipairs(lines) do
        nvgText(nvgCtx, panelX + 20, panelY + 50 + (i - 1) * 18, line)
    end

    -- 选项
    local optStartY = panelY + panelH - 20 - #npcDialogOptions * 32
    for i, opt in ipairs(npcDialogOptions) do
        local oy = optStartY + (i - 1) * 32
        local btnId = "cafe_dialog_" .. i
        local isSelected = (i == npcDialogChoice)
        local isHovered = (hoveredBtn == btnId)
        local isPressed = (pressedBtn == btnId) and isHovered

        if isHovered then
            npcDialogChoice = i
            isSelected = true
        end

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 20, oy, panelW - 40, 28, 5)
        if isPressed then
            nvgFillColor(nvgCtx, nvgRGBA(80, 40, 140, 250))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(180, 100, 255, 255))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)
        elseif isSelected or isHovered then
            nvgFillColor(nvgCtx, nvgRGBA(60, 30, 100, 230))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(150, 80, 255, 220))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
        else
            nvgFillColor(nvgCtx, nvgRGBA(40, 25, 60, 180))
            nvgFill(nvgCtx)
        end

        nvgFontSize(nvgCtx, 12)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, (isSelected or isHovered) and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 160, 200, 255))
        nvgText(nvgCtx, panelX + panelW / 2, oy + 14, opt.text)
    end

    -- 操作提示
    nvgFontSize(nvgCtx, 9)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(120, 100, 160, 180))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH - 8, "[W/S]选择  [F]确认  [ESC]离开")
end

return InternetCafeScene
