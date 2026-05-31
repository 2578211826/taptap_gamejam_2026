-- ====================================================================
-- GenericInteriorScene.lua - 通用建筑室内场景
-- ====================================================================
-- 用于所有没有专属场景的建筑（药房、写字楼、KTV、拉面店等）
-- 支持专属配置覆盖（customConfig=true时按建筑类型定制）
-- 包含：NPC、充电宝柜（概率）、可乱翻的装饰物、进出门
-- ====================================================================

local Config = require("Config")
local AudioManager = require("AudioManager")

local GenericInteriorScene = {}

-- ====================================================================
-- 建筑配置表（专属开关 + 室内参数）
-- customConfig=true 的建筑未来可覆盖所有字段实现专属逻辑
-- ====================================================================
GenericInteriorScene.BuildingConfigs = {
    -- texIdx 对应 AssetMap.Buildings 中的索引
    -- 药房 (AssetMap index 4)
    pharmacy = {
        customConfig = false,   -- false=使用通用模板
        name = "药房",
        npcName = "药剂师",
        npcColor = { 80, 160, 80 },    -- NPC 衣服颜色
        wallColor = { 235, 245, 235 },  -- 墙壁颜色
        floorColor = { 180, 200, 180 }, -- 地板颜色
        powerbankChance = 0.3,          -- 充电宝出现概率
        decorations = {
            { label = "药柜", w = 70, h = 100, color = { 200, 220, 200 } },
            { label = "展示架", w = 60, h = 90, color = { 180, 200, 180 } },
            { label = "纸箱", w = 40, h = 35, color = { 180, 150, 100 } },
        },
        npcDialogues = {
            "需要什么药？感冒药还是创可贴？",
            "最近流感严重，注意身体。",
            "充电宝？我们这里没有卖的...",
        },
    },
    -- 废弃店面 (AssetMap index 5)
    abandoned = {
        customConfig = false,
        name = "废弃店面",
        npcName = "流浪者",
        npcColor = { 100, 90, 80 },
        wallColor = { 200, 195, 185 },
        floorColor = { 140, 130, 120 },
        powerbankChance = 0.15,
        decorations = {
            { label = "旧纸箱", w = 45, h = 35, color = { 160, 130, 90 } },
            { label = "破沙发", w = 80, h = 50, color = { 120, 100, 80 } },
            { label = "垃圾袋", w = 35, h = 40, color = { 50, 50, 60 } },
            { label = "旧报纸堆", w = 50, h = 25, color = { 200, 190, 170 } },
        },
        npcDialogues = {
            "嗯？你在找什么？",
            "这里什么都没有了...",
            "以前这里是个不错的店。",
        },
    },
    -- 拉面店 (AssetMap index 6)
    ramen = {
        customConfig = false,
        name = "拉面店",
        npcName = "拉面师傅",
        npcColor = { 200, 200, 200 },
        wallColor = { 245, 235, 220 },
        floorColor = { 160, 130, 100 },
        powerbankChance = 0.4,
        decorations = {
            { label = "食材箱", w = 50, h = 40, color = { 180, 140, 80 } },
            { label = "调料架", w = 55, h = 80, color = { 140, 100, 60 } },
            { label = "啤酒箱", w = 45, h = 35, color = { 60, 120, 60 } },
        },
        npcDialogues = {
            "来碗拉面？今天的汤底很浓。",
            "手机没电？先坐下歇歇。",
            "后厨忙着呢，别乱跑。",
        },
    },
    -- 写字楼 (AssetMap index 7 - 但7是网吧，所以写字楼出现在其他循环)
    office = {
        customConfig = false,
        name = "写字楼大厅",
        npcName = "保安",
        npcColor = { 40, 40, 60 },
        wallColor = { 240, 240, 245 },
        floorColor = { 180, 180, 190 },
        powerbankChance = 0.5,
        decorations = {
            { label = "快递箱", w = 45, h = 35, color = { 180, 140, 80 } },
            { label = "绿植盆栽", w = 35, h = 60, color = { 60, 140, 60 } },
            { label = "报刊架", w = 40, h = 70, color = { 100, 80, 60 } },
        },
        npcDialogues = {
            "这里是写字楼大厅，闲人免进。",
            "充电宝？前台那边可能有。",
            "别在这里逗留太久。",
        },
    },
    -- KTV (AssetMap index 8)
    ktv = {
        customConfig = false,
        name = "KTV",
        npcName = "前台小妹",
        npcColor = { 200, 80, 150 },
        wallColor = { 50, 40, 60 },
        floorColor = { 80, 60, 100 },
        powerbankChance = 0.5,
        decorations = {
            { label = "音响设备", w = 50, h = 60, color = { 30, 30, 40 } },
            { label = "抱枕堆", w = 55, h = 30, color = { 200, 100, 150 } },
            { label = "零食箱", w = 40, h = 35, color = { 220, 180, 50 } },
        },
        npcDialogues = {
            "欢迎来到KTV！要开房间吗？",
            "现在没电唱不了歌啊。",
            "隔壁包间唱得真大声...",
        },
    },
    -- 居民楼 (AssetMap index 3)
    residential = {
        customConfig = false,
        name = "居民楼门厅",
        npcName = "大爷",
        npcColor = { 120, 100, 80 },
        wallColor = { 230, 225, 215 },
        floorColor = { 160, 150, 140 },
        powerbankChance = 0.2,
        decorations = {
            { label = "信箱", w = 50, h = 70, color = { 100, 120, 140 } },
            { label = "旧自行车", w = 70, h = 50, color = { 80, 80, 90 } },
            { label = "杂物堆", w = 55, h = 40, color = { 150, 130, 110 } },
        },
        npcDialogues = {
            "年轻人找谁？这里不能随便进。",
            "快递放楼下了，自己找吧。",
            "现在的年轻人，手机不离手...",
        },
    },
}

-- 建筑类型索引映射（旧版 fallback，新版直接传 interiorKey）
-- 保留仅用于兼容，新代码应直接传 interiorKey
GenericInteriorScene.BuildingIndexMap = {}

-- ====================================================================
-- 场景状态
-- ====================================================================
local active = false
local nvg = nil
local screenW, screenH = 0, 0
local gameState = nil
local currentConfig = nil      -- 当前建筑配置
local currentBuildingIdx = 0

-- 布局常量
local SCENE_WIDTH = 900
local FLOOR_Y = 0
local CEILING_H = 60
local DOOR_X = 100
local NPC_X = 750

-- 玩家
local playerX = 130
local playerSpeed = 200
local facingRight = true

-- 交互区
local interactZones = {}
local nearbyZone = nil

-- 充电宝
local hasPowerbank = false
local powerbankX = 30
local stationId = nil

-- 装饰物（可乱翻）
local decorItems = {}   -- { x, w, h, label, color, searched, searchResult }

-- NPC 对话
local dialogOpen = false
local dialogText = ""
local dialogOptions = {}
local dialogSelectedIdx = 1

-- 乱翻弹窗（两阶段：searching → result）
local rummagePopup = false
local rummageText = ""
local rummageTimer = 0
local rummagePhase = "idle"  -- "idle" / "searching" / "result"
local rummageResultText = ""  -- 阶段2显示的结果文本
local rummageDecoIdx = nil    -- 当前乱翻的装饰物索引

-- 鼠标支持
local hoveredBtn = nil
local pressedBtn = nil

-- 回调
local onExitCallback = nil

-- ====================================================================
-- 初始化
-- ====================================================================
function GenericInteriorScene.Init(nvgCtx, sw, sh)
    nvg = nvgCtx
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100
end

-- ====================================================================
-- 获取建筑配置（优先使用 interiorKey，fallback 到 buildingIndex 映射）
-- ====================================================================
function GenericInteriorScene.GetConfig(buildingIndex, interiorKey)
    -- 新版：直接用 interiorKey
    if interiorKey and GenericInteriorScene.BuildingConfigs[interiorKey] then
        return GenericInteriorScene.BuildingConfigs[interiorKey], interiorKey
    end
    -- 旧版 fallback：通过 buildingIndex 映射
    local key = GenericInteriorScene.BuildingIndexMap[buildingIndex]
    if key and GenericInteriorScene.BuildingConfigs[key] then
        return GenericInteriorScene.BuildingConfigs[key], key
    end
    -- 默认 fallback
    return GenericInteriorScene.BuildingConfigs.residential, "residential"
end

-- ====================================================================
-- 判断某个建筑是否应使用通用场景（旧版兼容，新版由 WorldRenderer 注册表驱动）
-- ====================================================================
function GenericInteriorScene.ShouldHandle(buildingIndex)
    return true  -- 新版由注册表 handler 字段决定，此函数仅兼容保留
end

-- ====================================================================
-- 进入
-- ====================================================================
function GenericInteriorScene.Enter(gs, buildingIndex, exitCallback, interiorKey)
    active = true
    gameState = gs
    currentBuildingIdx = buildingIndex
    currentConfig = GenericInteriorScene.GetConfig(buildingIndex, interiorKey)
    onExitCallback = exitCallback

    playerX = 130
    facingRight = true
    nearbyZone = nil
    dialogOpen = false
    rummagePopup = false
    rummageText = ""
    rummageTimer = 0
    rummagePhase = "idle"
    rummageResultText = ""
    rummageDecoIdx = nil
    hoveredBtn = nil
    pressedBtn = nil

    -- 充电宝（按概率生成）
    hasPowerbank = math.random() < (currentConfig.powerbankChance or 0.3)
    stationId = "pb_generic_" .. buildingIndex

    -- 注册充电宝
    if hasPowerbank then
        local PowerbankSystem = require("PowerbankSystem")
        local existing = PowerbankSystem.GetById(stationId)
        if not existing then
            PowerbankSystem.Register(stationId, buildingIndex, powerbankX, currentConfig.name .. "内")
        end
        PowerbankSystem.SetCurrentScene(buildingIndex)
    end

    -- 生成装饰物（随机分布在场景中间区域）
    decorItems = {}
    local decos = currentConfig.decorations or {}
    local decorStartX = 200
    local decorSpacing = 140
    for i, deco in ipairs(decos) do
        local dx = decorStartX + (i - 1) * decorSpacing + math.random(-20, 20)
        table.insert(decorItems, {
            x = dx,
            w = deco.w,
            h = deco.h,
            label = deco.label,
            color = deco.color,
            searched = false,
            searchResult = nil,  -- 翻完后记录结果
        })
    end

    -- 构建交互区域
    interactZones = {}
    -- 门
    table.insert(interactZones, {
        x = DOOR_X, w = 60, type = "door", label = "离开",
        priority = 10,
    })
    -- NPC
    table.insert(interactZones, {
        x = NPC_X, w = 60, type = "npc", label = currentConfig.npcName,
        priority = 8,
    })
    -- 充电宝柜
    if hasPowerbank then
        table.insert(interactZones, {
            x = powerbankX, w = 50, type = "powerbank", label = "充电宝柜",
            priority = 9,
        })
    end
    -- 装饰物（优先级最低）
    for i, deco in ipairs(decorItems) do
        table.insert(interactZones, {
            x = deco.x, w = deco.w, type = "decoration",
            label = deco.label, decoIdx = i,
            priority = 1,  -- 最低优先级
        })
    end

    print("[GenericInterior] 进入 " .. currentConfig.name .. " (building=" .. buildingIndex .. ", powerbank=" .. tostring(hasPowerbank) .. ")")
end

-- ====================================================================
-- 退出
-- ====================================================================
function GenericInteriorScene.Exit()
    active = false
    nearbyZone = nil
    if hasPowerbank then
        local PowerbankSystem = require("PowerbankSystem")
        PowerbankSystem.SetCurrentScene(nil)
    end
    if onExitCallback then
        onExitCallback()
    end
    print("[GenericInterior] 离开 " .. (currentConfig and currentConfig.name or "?"))
end

function GenericInteriorScene.IsActive()
    return active
end

function GenericInteriorScene.IsDialogOpen()
    return dialogOpen or rummagePopup
end

-- ====================================================================
-- 更新
-- ====================================================================
function GenericInteriorScene.Update(dt)
    if not active then return end

    -- 弹窗打开时不允许移动
    if dialogOpen or rummagePopup then
        if rummagePopup then
            rummageTimer = rummageTimer - dt
            if rummageTimer <= 0 then
                if rummagePhase == "searching" then
                    -- 读条完成 → 进入结果阶段
                    rummagePhase = "result"
                    rummageText = rummageResultText
                    rummageTimer = 1.5
                    -- 此时发放奖励
                    if rummageDecoIdx then
                        local deco = decorItems[rummageDecoIdx]
                        if deco and deco.searchResult and deco.searchResult > 0 then
                            gameState.money = gameState.money + deco.searchResult
                        end
                    end
                else
                    -- 结果阶段结束 → 关闭弹窗
                    rummagePopup = false
                    rummagePhase = "idle"
                    rummageDecoIdx = nil
                end
            end
        end
        return
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
    playerX = math.max(20, math.min(playerX, SCENE_WIDTH - 20))

    -- 检测附近交互区（带优先级：高优先级覆盖低优先级）
    nearbyZone = nil
    local bestPriority = -1
    for _, zone in ipairs(interactZones) do
        local zoneCenter = zone.x + zone.w / 2
        if math.abs(playerX - zoneCenter) < zone.w / 2 + 25 then
            if zone.priority > bestPriority then
                nearbyZone = zone
                bestPriority = zone.priority
            end
        end
    end
end

-- ====================================================================
-- 交互（按F）
-- ====================================================================
function GenericInteriorScene.OnInteract()
    if not active then return false end
    if not nearbyZone then return false end

    if nearbyZone.type == "door" then
        GenericInteriorScene.Exit()
        return true

    elseif nearbyZone.type == "npc" then
        GenericInteriorScene.OpenNPCDialog()
        return true

    elseif nearbyZone.type == "powerbank" then
        GenericInteriorScene.OpenPowerbankDialog()
        return true

    elseif nearbyZone.type == "decoration" then
        GenericInteriorScene.RummageDecoration(nearbyZone.decoIdx)
        return true
    end

    return false
end

-- ====================================================================
-- 乱翻装饰物
-- ====================================================================
function GenericInteriorScene.RummageDecoration(idx)
    local deco = decorItems[idx]
    if not deco then return end

    if deco.searched then
        -- 已经翻过了
        rummagePopup = true
        rummagePhase = "result"
        rummageText = "「" .. deco.label .. "」已经翻过了，什么也没有。"
        rummageTimer = 1.5
        rummageDecoIdx = nil
        return
    end

    -- 标记已翻
    deco.searched = true
    AudioManager.Interact()

    -- 概率：15%=5元，5%=10元，80%=空
    local roll = math.random()
    if roll < 0.05 then
        deco.searchResult = 10
        rummageResultText = "翻了翻「" .. deco.label .. "」...\n找到了 ¥10！运气不错！"
        print("[GenericInterior] 乱翻 " .. deco.label .. " → ¥10")
    elseif roll < 0.20 then
        deco.searchResult = 5
        rummageResultText = "翻了翻「" .. deco.label .. "」...\n捡到了 ¥5。"
        print("[GenericInterior] 乱翻 " .. deco.label .. " → ¥5")
    else
        deco.searchResult = 0
        rummageResultText = "翻了翻「" .. deco.label .. "」...\n什么也没找到。"
        print("[GenericInterior] 乱翻 " .. deco.label .. " → 空")
    end

    -- 阶段1：正在乱翻中（读条）
    rummagePopup = true
    rummagePhase = "searching"
    rummageText = "正在乱翻「" .. deco.label .. "」..."
    rummageTimer = 1.5
    rummageDecoIdx = idx
end

-- ====================================================================
-- NPC 对话
-- ====================================================================
function GenericInteriorScene.OpenNPCDialog()
    dialogOpen = true
    dialogSelectedIdx = 1
    -- 随机选一句台词
    local dialogues = currentConfig.npcDialogues or { "......" }
    dialogText = dialogues[math.random(1, #dialogues)]
    dialogOptions = {
        { text = "好吧", action = "close" },
    }
end

function GenericInteriorScene.CloseDialog()
    dialogOpen = false
end

function GenericInteriorScene.DialogNavigate(direction)
    if not dialogOpen or #dialogOptions == 0 then return end
    dialogSelectedIdx = dialogSelectedIdx + direction
    if dialogSelectedIdx < 1 then dialogSelectedIdx = #dialogOptions end
    if dialogSelectedIdx > #dialogOptions then dialogSelectedIdx = 1 end
end

function GenericInteriorScene.DialogConfirm()
    if not dialogOpen then return end
    local opt = dialogOptions[dialogSelectedIdx]
    if opt and opt.action == "close" then
        GenericInteriorScene.CloseDialog()
    elseif opt and opt.action == "phone" then
        GenericInteriorScene.CloseDialog()
        -- 外部处理打开手机
    end
end

-- ====================================================================
-- 充电宝对话
-- ====================================================================
function GenericInteriorScene.OpenPowerbankDialog()
    local PowerbankSystem = require("PowerbankSystem")
    dialogOpen = true
    dialogSelectedIdx = 1

    if PowerbankSystem.CanUse(stationId) then
        dialogText = "充电宝柜状态正常，扫码即可借用。\n打开手机-扫码App操作。"
        dialogOptions = {
            { text = "打开手机", action = "phone" },
            { text = "算了", action = "close" },
        }
    else
        local station = PowerbankSystem.GetById(stationId)
        local stateLabel = station and PowerbankSystem.GetStateLabel(station.state) or "不可用"
        dialogText = "充电宝柜当前：" .. stateLabel .. "\n无法借用，试试其他地方吧。"
        dialogOptions = {
            { text = "知道了", action = "close" },
        }
    end
end

-- ====================================================================
-- 鼠标支持
-- ====================================================================
function GenericInteriorScene.SetHoverState(hovered, pressed)
    hoveredBtn = hovered
    pressedBtn = pressed
end

function GenericInteriorScene.GetButtonAtPosition(mx, my)
    -- 对话面板按钮
    if dialogOpen and #dialogOptions > 0 then
        local panelW = 340
        local panelH = 180
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        local optStartY = panelY + panelH - 20 - #dialogOptions * 30
        for i = 1, #dialogOptions do
            local oy = optStartY + (i - 1) * 30
            if mx >= panelX + 20 and mx <= panelX + panelW - 20
                and my >= oy and my <= oy + 26 then
                return "generic_dialog_" .. i
            end
        end
        return nil
    end
    return nil
end

function GenericInteriorScene.ExecuteButtonClick(btnId)
    if not btnId then return false end
    if btnId:sub(1, 15) == "generic_dialog_" then
        local idx = tonumber(btnId:sub(16))
        if idx and idx >= 1 and idx <= #dialogOptions then
            dialogSelectedIdx = idx
            GenericInteriorScene.DialogConfirm()
        end
        return true
    end
    return false
end

-- ====================================================================
-- 渲染
-- ====================================================================
function GenericInteriorScene.Render(nvgCtx, sw, sh)
    if not active then return end
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100

    local cfg = currentConfig

    -- 背景墙壁
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    local wc = cfg.wallColor
    nvgFillColor(nvgCtx, nvgRGBA(wc[1], wc[2], wc[3], 255))
    nvgFill(nvgCtx)

    -- 地板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, FLOOR_Y, screenW, screenH - FLOOR_Y)
    local fc = cfg.floorColor
    nvgFillColor(nvgCtx, nvgRGBA(fc[1], fc[2], fc[3], 255))
    nvgFill(nvgCtx)

    -- 地板纹理线
    nvgStrokeColor(nvgCtx, nvgRGBA(fc[1] - 20, fc[2] - 20, fc[3] - 20, 80))
    nvgStrokeWidth(nvgCtx, 1)
    for i = 0, math.ceil(screenW / 60) do
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, i * 60, FLOOR_Y)
        nvgLineTo(nvgCtx, i * 60, screenH)
        nvgStroke(nvgCtx)
    end

    -- 天花板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, CEILING_H)
    nvgFillColor(nvgCtx, nvgRGBA(50, 48, 45, 255))
    nvgFill(nvgCtx)

    -- 日光灯
    for i = 1, 2 do
        local lx = screenW * i / 3
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, lx - 35, CEILING_H - 7, 70, 5)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 240, 220))
        nvgFill(nvgCtx)
    end

    -- 后墙装饰线
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, CEILING_H, screenW, 2)
    nvgFillColor(nvgCtx, nvgRGBA(100, 80, 60, 180))
    nvgFill(nvgCtx)

    -- 门
    RenderGenericDoor(nvgCtx)

    -- 充电宝柜
    if hasPowerbank then
        RenderGenericPowerbank(nvgCtx)
    end

    -- 装饰物
    for i, deco in ipairs(decorItems) do
        RenderDecoration(nvgCtx, deco, i)
    end

    -- NPC
    RenderGenericNPC(nvgCtx)

    -- 玩家
    RenderGenericPlayer(nvgCtx)

    -- 交互提示
    if nearbyZone and not dialogOpen and not rummagePopup then
        RenderGenericPrompt(nvgCtx)
    end

    -- 对话面板
    if dialogOpen then
        RenderDialogPanel(nvgCtx)
    end

    -- 乱翻结果弹窗
    if rummagePopup then
        RenderRummagePopup(nvgCtx)
    end
end

-- ====================================================================
-- 子渲染函数
-- ====================================================================

function RenderGenericDoor(nvgCtx)
    local dx = DOOR_X
    local dw = 50
    local dh = 90
    local dy = FLOOR_Y - dh
    -- 门框
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx - 3, dy - 3, dw + 6, dh + 3)
    nvgFillColor(nvgCtx, nvgRGBA(70, 55, 40, 255))
    nvgFill(nvgCtx)
    -- 门板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx, dy, dw, dh)
    nvgFillColor(nvgCtx, nvgRGBA(130, 95, 55, 255))
    nvgFill(nvgCtx)
    -- 门把手
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, dx + dw - 10, dy + dh / 2, 4)
    nvgFillColor(nvgCtx, nvgRGBA(200, 180, 50, 255))
    nvgFill(nvgCtx)
    -- EXIT标记
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(0, 200, 0, 255))
    nvgText(nvgCtx, dx + dw / 2, dy - 12, "EXIT")
end

function RenderGenericPowerbank(nvgCtx)
    local bx = powerbankX
    local bw = 40
    local bh = 75
    local by = FLOOR_Y - bh

    -- 柜体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, bx, by, bw, bh, 4)
    nvgFillColor(nvgCtx, nvgRGBA(40, 120, 60, 255))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(20, 80, 40, 255))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 品牌条
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, bx + 3, by + 4, bw - 6, 10)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 220))
    nvgFill(nvgCtx)
    nvgFontSize(nvgCtx, 7)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(40, 120, 60, 255))
    nvgText(nvgCtx, bx + bw / 2, by + 9, "充电宝")

    -- 槽位
    for i = 1, 3 do
        local sy = by + 18 + (i - 1) * 13
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, bx + 5, sy, bw - 10, 9, 2)
        nvgFillColor(nvgCtx, nvgRGBA(30, 30, 40, 200))
        nvgFill(nvgCtx)
        if i <= 2 then
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, bx + 6, sy + 1, bw - 12, 7, 2)
            nvgFillColor(nvgCtx, nvgRGBA(200, 200, 210, 220))
            nvgFill(nvgCtx)
        end
    end

    -- LED
    local PowerbankSystem = require("PowerbankSystem")
    local station = PowerbankSystem.GetById(stationId)
    local lr, lg, lb = 0, 255, 80
    if station and station.state == PowerbankSystem.State.EMPTY then
        lr, lg, lb = 255, 200, 0
    elseif station and station.state == PowerbankSystem.State.OFFLINE then
        lr, lg, lb = 255, 50, 50
    end
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, bx + bw / 2, by + bh - 10, 3)
    nvgFillColor(nvgCtx, nvgRGBA(lr, lg, lb, 255))
    nvgFill(nvgCtx)
end

function RenderDecoration(nvgCtx, deco, idx)
    local dx = deco.x
    local dw = deco.w
    local dh = deco.h
    local dy = FLOOR_Y - dh
    local c = deco.color

    -- 物体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, dx, dy, dw, dh, 3)
    if deco.searched then
        -- 翻过的变暗
        nvgFillColor(nvgCtx, nvgRGBA(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 200))
    else
        nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 240))
    end
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 200))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 标签
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(80, 70, 60, 200))
    nvgText(nvgCtx, dx + dw / 2, FLOOR_Y + 4, deco.label)

    -- 翻过标记
    if deco.searched then
        nvgFontSize(nvgCtx, 8)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 180))
        nvgText(nvgCtx, dx + dw / 2, dy + dh / 2, "已翻")
    end
end

function RenderGenericNPC(nvgCtx)
    local nx = NPC_X
    local ny = FLOOR_Y
    local cfg = currentConfig
    local nc = cfg.npcColor

    -- 身体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, nx - 12, ny - 55, 24, 35, 4)
    nvgFillColor(nvgCtx, nvgRGBA(nc[1], nc[2], nc[3], 255))
    nvgFill(nvgCtx)
    -- 头
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, nx, ny - 65, 12)
    nvgFillColor(nvgCtx, nvgRGBA(240, 200, 160, 255))
    nvgFill(nvgCtx)
    -- 腿
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, nx - 7, ny - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 60, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, nx + 2, ny - 20, 5, 20)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 60, 255))
    nvgFill(nvgCtx)

    -- 名牌
    nvgFontSize(nvgCtx, 8)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, nx - 16, ny - 42, 32, 12, 2)
    nvgFillColor(nvgCtx, nvgRGBA(nc[1], nc[2], nc[3], 200))
    nvgFill(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, nx, ny - 36, cfg.npcName)
end

function RenderGenericPlayer(nvgCtx)
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
    local eo = facingRight and 3 or -3
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, px + eo - 2, py - 62, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, px + eo + 2, py - 62, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)
end

function RenderGenericPrompt(nvgCtx)
    if not nearbyZone then return end

    -- 根据类型生成提示文字
    local text
    if nearbyZone.type == "decoration" then
        local deco = decorItems[nearbyZone.decoIdx]
        if deco and deco.searched then
            text = "[F] " .. nearbyZone.label .. "（已翻）"
        else
            text = "[F] 乱翻（" .. nearbyZone.label .. "）"
        end
    elseif nearbyZone.type == "door" then
        text = "[F] 离开"
    elseif nearbyZone.type == "npc" then
        text = "[F] 交谈-" .. nearbyZone.label
    elseif nearbyZone.type == "powerbank" then
        text = "[F] 充电宝柜"
    else
        text = "[F] " .. nearbyZone.label
    end

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
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 200))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(220, 240, 255, 255))
    nvgText(nvgCtx, tx, ty, text)
end

function RenderDialogPanel(nvgCtx)
    -- 遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 120))
    nvgFill(nvgCtx)

    local panelW = 340
    local panelH = 180
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    -- 面板
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvgCtx, nvgRGBA(25, 30, 50, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(80, 120, 180, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- NPC头像
    local cfg = currentConfig
    local nc = cfg.npcColor
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, panelX + 28, panelY + 28, 14)
    nvgFillColor(nvgCtx, nvgRGBA(nc[1], nc[2], nc[3], 255))
    nvgFill(nvgCtx)
    nvgFontSize(nvgCtx, 10)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(180, 200, 255, 255))
    nvgText(nvgCtx, panelX + 48, panelY + 28, cfg.npcName)

    -- 对话文本
    nvgFontSize(nvgCtx, 12)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(220, 220, 240, 255))
    local lines = {}
    for line in dialogText:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    for i, line in ipairs(lines) do
        nvgText(nvgCtx, panelX + 20, panelY + 50 + (i - 1) * 18, line)
    end

    -- 选项
    local optStartY = panelY + panelH - 20 - #dialogOptions * 30
    for i, opt in ipairs(dialogOptions) do
        local oy = optStartY + (i - 1) * 30
        local btnId = "generic_dialog_" .. i
        local isSelected = (i == dialogSelectedIdx)
        local isHovered = (hoveredBtn == btnId)
        if isHovered then dialogSelectedIdx = i; isSelected = true end

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 20, oy, panelW - 40, 26, 5)
        if isSelected or isHovered then
            nvgFillColor(nvgCtx, nvgRGBA(50, 70, 120, 230))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
        else
            nvgFillColor(nvgCtx, nvgRGBA(40, 45, 65, 180))
            nvgFill(nvgCtx)
        end

        nvgFontSize(nvgCtx, 12)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, isSelected and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 180, 200, 255))
        nvgText(nvgCtx, panelX + panelW / 2, oy + 13, opt.text)
    end

    -- 操作提示
    nvgFontSize(nvgCtx, 9)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(120, 120, 160, 180))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH - 8, "[F]确认  [ESC]关闭")
end

function RenderRummagePopup(nvgCtx)
    -- 居中弹窗
    local panelW = 280
    local panelH = 100
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(nvgCtx, nvgRGBA(20, 25, 40, 240))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(150, 150, 200, 180))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 文本
    nvgFontSize(nvgCtx, 12)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(230, 230, 250, 255))
    local lines = {}
    for line in rummageText:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    for i, line in ipairs(lines) do
        nvgText(nvgCtx, panelX + panelW / 2, panelY + 20 + (i - 1) * 20, line)
    end

    -- 进度条（仅 searching 阶段显示）
    if rummagePhase == "searching" then
        local maxTimer = 1.5
        local ratio = math.max(0, 1.0 - rummageTimer / maxTimer)
        local barW = panelW - 40
        -- 背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 20, panelY + panelH - 22, barW, 6, 3)
        nvgFillColor(nvgCtx, nvgRGBA(60, 60, 80, 180))
        nvgFill(nvgCtx)
        -- 进度
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 20, panelY + panelH - 22, barW * ratio, 6, 3)
        nvgFillColor(nvgCtx, nvgRGBA(100, 200, 255, 220))
        nvgFill(nvgCtx)
    end
end

return GenericInteriorScene
