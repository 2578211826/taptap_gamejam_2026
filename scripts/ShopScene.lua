-- ====================================================================
-- ShopScene.lua - 杂货铺室内场景
-- ====================================================================
-- 板块①：基础场景渲染 + 玩家移动 + 进出
-- ====================================================================

local Config = require("Config")
local ItemData = require("ItemData")
local AudioManager = require("AudioManager")
local AssetMap = require("AssetMap")

local ShopScene = {}

-- 场景状态
local active = false
local nvg = nil
local screenW, screenH = 0, 0
local gameState = nil  -- 游戏状态引用

-- 货架浮窗状态
local shelfOpen = false        -- 是否打开了货架面板
local shelfCategory = nil      -- 当前查看的货架分类
local shelfItems = {}          -- 当前货架上的商品列表
local shelfSelectedIdx = 1     -- 当前选中商品索引
local shelfMessage = nil       -- 操作反馈消息
local shelfMessageTimer = 0    -- 消息显示计时

-- 携带栏状态
local inventorySelectedIdx = 0   -- 0=不选中, 1~5=选中第几个
local inventoryMode = false      -- 是否进入携带栏操作模式(Tab切换)

-- 柜台对话状态
local counterOpen = false        -- 是否打开柜台对话面板
local counterDialogue = ""       -- 当前对话文本
local counterOptions = {}        -- 选项列表 { {text, action}, ... }
local counterSelectedIdx = 1     -- 当前选中选项
local paidItems = {}             -- 已付款物品列表（带出门不触发追击）



-- 室内布局常量
local SHOP_WIDTH = 900     -- 商店内部总宽度
local FLOOR_Y = 0          -- 地面Y（运行时计算）
local CEILING_H = 60       -- 天花板高度
local WALL_MARGIN = 30     -- 墙壁厚度

-- 商店内物件位置
local DOOR_X = 50          -- 门的位置（左侧）
local COUNTER_X = 750      -- 柜台位置（右侧）

-- 门口警告状态
local doorWarningOpen = false    -- 是否显示离店警告面板
local doorWarningChoice = 1      -- 1=回去付款, 2=硬闯

-- 鼠标 hover/pressed 状态（由 main.lua 驱动）
local shopHoveredBtn = nil       -- 当前 hover 的按钮id
local shopPressedBtn = nil       -- 当前按下的按钮id

-- 货架定义（x位置, 宽度, 类别标签）
local shelves = {
    { x = 180, w = 100, label = "零食饮料", category = "snack" },
    { x = 320, w = 100, label = "日用文具", category = "stationery" },
    { x = 460, w = 100, label = "电子配件", category = "electronics" },
    { x = 600, w = 100, label = "充电设备", category = "charger" },
}

-- 玩家室内状态
local playerX = 80
local playerSpeed = 200
local facingRight = true

-- 可交互区域
local interactZones = {}  -- 运行时计算
local nearbyZone = nil    -- 当前附近的交互区

-- 回调
local onExitCallback = nil

-- ====================================================================
-- 初始化
-- ====================================================================
function ShopScene.Init(nvgCtx, sw, sh)
    nvg = nvgCtx
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100
end

-- ====================================================================
-- 进入/离开商店
-- ====================================================================
function ShopScene.Enter(gs, exitCallback)
    active = true
    gameState = gs
    playerX = 80  -- 从门口开始
    facingRight = true
    onExitCallback = exitCallback
    nearbyZone = nil
    shelfOpen = false
    shelfCategory = nil
    shelfItems = {}
    shelfSelectedIdx = 1
    shelfMessage = nil
    shelfMessageTimer = 0
    inventorySelectedIdx = 0
    inventoryMode = false
    counterOpen = false
    counterDialogue = ""
    counterOptions = {}
    counterSelectedIdx = 1
    paidItems = {}
    doorWarningOpen = false
    doorWarningChoice = 1

    -- 构建交互区域
    interactZones = {
        { x = DOOR_X, w = 60, type = "door", label = "离开商店" },
    }
    -- 货架交互区
    for _, shelf in ipairs(shelves) do
        table.insert(interactZones, {
            x = shelf.x, w = shelf.w,
            type = "shelf", label = shelf.label,
            category = shelf.category,
        })
    end
    -- 柜台交互区
    table.insert(interactZones, {
        x = COUNTER_X, w = 100, type = "counter", label = "柜台-店员",
    })

    print("[ShopScene] 进入商店")
end

function ShopScene.Exit()
    active = false
    nearbyZone = nil
    -- 检查是否有未付款物品
    local unpaid = ShopScene.GetUnpaidItems()
    local hasUnpaid = #unpaid > 0
    if hasUnpaid then
        print("[ShopScene] 警告：携带未付款物品离开！触发追击")
    end
    if onExitCallback then
        onExitCallback(hasUnpaid)
    end
    print("[ShopScene] 离开商店")
end

function ShopScene.IsActive()
    return active
end

-- ====================================================================
-- 更新
-- ====================================================================
function ShopScene.Update(dt)
    if not active then return end

    -- 面板打开时不允许移动
    if shelfOpen or counterOpen or doorWarningOpen then
        -- 消息计时
        if shelfMessage and shelfMessageTimer > 0 then
            shelfMessageTimer = shelfMessageTimer - dt
            if shelfMessageTimer <= 0 then
                shelfMessage = nil
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

    -- 边界限制
    playerX = math.max(40, math.min(playerX, SHOP_WIDTH - 40))

    -- 检测附近交互区
    nearbyZone = nil
    for _, zone in ipairs(interactZones) do
        local zoneCenter = zone.x + zone.w / 2
        if math.abs(playerX - zoneCenter) < zone.w / 2 + 25 then
            nearbyZone = zone
            break
        end
    end
end

-- ====================================================================
-- 按F交互
-- ====================================================================
function ShopScene.OnInteract()
    if not active then return false end

    if not nearbyZone then return false end

    if nearbyZone.type == "door" then
        -- 检查是否有未付款物品
        local unpaid = ShopScene.GetUnpaidItems()
        if #unpaid > 0 then
            -- 弹出警告面板
            doorWarningOpen = true
            doorWarningChoice = 1  -- 默认选"回去付款"
        else
            ShopScene.Exit()
        end
        return true
    elseif nearbyZone.type == "shelf" then
        -- 打开货架面板
        ShopScene.OpenShelf(nearbyZone.category)
        return true
    elseif nearbyZone.type == "counter" then
        ShopScene.OpenCounter()
        return true
    end

    return false
end

-- ====================================================================
-- 货架面板操作
-- ====================================================================
function ShopScene.OpenShelf(category)
    if not gameState or not gameState.shopStock then return end

    shelfCategory = category
    shelfItems = gameState.shopStock[category] or {}
    shelfSelectedIdx = 1
    shelfOpen = true
    shelfMessage = nil
    print("[ShopScene] 打开货架: " .. category .. " (" .. #shelfItems .. "件商品)")
end

function ShopScene.CloseShelf()
    shelfOpen = false
    shelfCategory = nil
    shelfMessage = nil
end

function ShopScene.PickUpItem()
    if not shelfOpen or #shelfItems == 0 then return end

    local item = shelfItems[shelfSelectedIdx]
    if not item then return end

    -- 检查携带栏是否满了
    if #gameState.inventory >= gameState.inventoryMax then
        shelfMessage = "携带栏已满！(最多" .. gameState.inventoryMax .. "件)"
        shelfMessageTimer = 2.0
        return
    end

    -- 拿取物品（注：此时还未付款，拿走就是"偷"直到去柜台结账）
    AudioManager.ItemPickup()
    table.insert(gameState.inventory, item)

    -- 从货架移除
    table.remove(shelfItems, shelfSelectedIdx)
    -- 同步到 shopStock
    if gameState.shopStock[shelfCategory] then
        gameState.shopStock[shelfCategory] = shelfItems
    end

    -- 调整选中索引
    if shelfSelectedIdx > #shelfItems then
        shelfSelectedIdx = math.max(1, #shelfItems)
    end

    shelfMessage = "拿取了: " .. item.name
    shelfMessageTimer = 1.5
    print("[ShopScene] 拿取: " .. item.name)

    -- 如果货架空了，自动关闭
    if #shelfItems == 0 then
        shelfMessage = "货架已空"
        shelfMessageTimer = 1.0
        -- 延迟关闭让消息显示一下（Update里会处理）
    end
end

-- 方向键选择
function ShopScene.ShelfNavigate(direction)
    if not shelfOpen or #shelfItems == 0 then return end
    shelfSelectedIdx = shelfSelectedIdx + direction
    if shelfSelectedIdx < 1 then shelfSelectedIdx = #shelfItems end
    if shelfSelectedIdx > #shelfItems then shelfSelectedIdx = 1 end
end

-- 鼠标点击货架面板中的商品直接拿取
function ShopScene.HandleShelfClick(mx, my)
    if not shelfOpen or #shelfItems == 0 then return false end

    -- 计算面板区域（与 RenderShelfPanel 一致）
    local panelW = 320
    local panelH = 280
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2
    local startY = panelY + 42
    local itemH = 40
    local maxVisible = 5

    -- 检查点击是否在某个商品行内
    for i = 1, math.min(#shelfItems, maxVisible) do
        local iy = startY + (i - 1) * itemH
        local rowLeft = panelX + 10
        local rowRight = panelX + panelW - 10
        local rowTop = iy
        local rowBottom = iy + itemH - 4

        if mx >= rowLeft and mx <= rowRight and my >= rowTop and my <= rowBottom then
            -- 点击了第 i 个商品，选中并拿取
            shelfSelectedIdx = i
            ShopScene.PickUpItem()
            return true
        end
    end

    -- 点击在面板外 → 关闭货架
    if mx < panelX or mx > panelX + panelW or my < panelY or my > panelY + panelH then
        ShopScene.CloseShelf()
        return true
    end

    return false
end

-- ====================================================================
-- 携带栏操作
-- ====================================================================
function ShopScene.ToggleInventoryMode()
    if shelfOpen then return end  -- 货架面板打开时不切换
    inventoryMode = not inventoryMode
    if inventoryMode then
        if gameState and #gameState.inventory > 0 then
            inventorySelectedIdx = 1
        else
            inventoryMode = false  -- 没有物品不进入
        end
    else
        inventorySelectedIdx = 0
    end
end

function ShopScene.IsInventoryMode()
    return inventoryMode
end

function ShopScene.InventoryNavigate(direction)
    if not inventoryMode or not gameState then return end
    local count = #gameState.inventory
    if count == 0 then return end
    inventorySelectedIdx = inventorySelectedIdx + direction
    if inventorySelectedIdx < 1 then inventorySelectedIdx = count end
    if inventorySelectedIdx > count then inventorySelectedIdx = 1 end
end

function ShopScene.DiscardItem()
    if not inventoryMode or not gameState then return end
    if inventorySelectedIdx < 1 or inventorySelectedIdx > #gameState.inventory then return end

    local item = gameState.inventory[inventorySelectedIdx]
    table.remove(gameState.inventory, inventorySelectedIdx)
    print("[ShopScene] 丢弃: " .. item.name)

    -- 把物品放回对应货架
    if gameState.shopStock and gameState.shopStock[item.category] then
        table.insert(gameState.shopStock[item.category], item)
    end

    -- 调整选中索引
    if #gameState.inventory == 0 then
        inventoryMode = false
        inventorySelectedIdx = 0
    elseif inventorySelectedIdx > #gameState.inventory then
        inventorySelectedIdx = #gameState.inventory
    end

    shelfMessage = "放回了: " .. item.name
    shelfMessageTimer = 1.5
end

-- ====================================================================
-- 柜台对话系统
-- ====================================================================
function ShopScene.OpenCounter()
    if not gameState then return end

    -- 计算未付款物品
    local unpaidItems = {}
    for _, item in ipairs(gameState.inventory) do
        local isPaid = false
        for _, paid in ipairs(paidItems) do
            if paid == item then isPaid = true; break end
        end
        if not isPaid then
            table.insert(unpaidItems, item)
        end
    end

    counterOpen = true
    counterSelectedIdx = 1

    if #gameState.inventory == 0 then
        -- 没有物品
        counterDialogue = "欢迎光临！先去货架看看吧，\n有需要随时来找我。"
        counterOptions = {
            { text = "好的", action = "close" },
        }
    elseif #unpaidItems == 0 then
        -- 所有物品都已付过款
        counterDialogue = "你的东西都结过账了，\n还需要别的吗？"
        counterOptions = {
            { text = "不用了", action = "close" },
        }
    else
        -- 有未付款物品，显示结账
        local total = 0
        for _, item in ipairs(unpaidItems) do
            total = total + item.price
        end
        counterDialogue = string.format(
            "结账吗？你拿了 %d 件商品，\n合计 ¥%.2f",
            #unpaidItems, total
        )
        counterOptions = {
            { text = string.format("付款 ¥%.2f", total), action = "pay", total = total, items = unpaidItems },
            { text = "我再看看", action = "close" },
        }
    end

    print("[ShopScene] 柜台对话打开")
end

function ShopScene.CloseCounter()
    counterOpen = false
    counterDialogue = ""
    counterOptions = {}
end

function ShopScene.IsCounterOpen()
    return counterOpen
end

function ShopScene.CounterNavigate(direction)
    if not counterOpen or #counterOptions == 0 then return end
    counterSelectedIdx = counterSelectedIdx + direction
    if counterSelectedIdx < 1 then counterSelectedIdx = #counterOptions end
    if counterSelectedIdx > #counterOptions then counterSelectedIdx = 1 end
end

function ShopScene.CounterConfirm()
    if not counterOpen or #counterOptions == 0 then return end

    local option = counterOptions[counterSelectedIdx]
    if not option then return end

    if option.action == "close" then
        ShopScene.CloseCounter()
    elseif option.action == "pay" then
        -- 尝试付款
        if gameState.money >= option.total then
            -- 付款成功
            AudioManager.ItemPay()
            gameState.money = gameState.money - option.total
            gameState.stats.moneySpent = gameState.stats.moneySpent + option.total
            gameState.stats.payCount = (gameState.stats.payCount or 0) + 1

            -- 标记为已付款
            for _, item in ipairs(option.items) do
                table.insert(paidItems, item)
            end

            counterDialogue = string.format(
                "付款成功！收您 ¥%.2f。\n余额: ¥%.2f\n东西可以带走了~",
                option.total, gameState.money
            )
            counterOptions = {
                { text = "谢谢", action = "close" },
            }
            counterSelectedIdx = 1

            print("[ShopScene] 付款成功: ¥" .. option.total)
        else
            -- 余额不足
            counterDialogue = string.format(
                "余额不足！需要 ¥%.2f\n你只有 ¥%.2f ...\n要不放回去点东西？",
                option.total, gameState.money
            )
            counterOptions = {
                { text = "我去放回去", action = "close" },
            }
            counterSelectedIdx = 1

            print("[ShopScene] 余额不足")
        end
    end
end

-- 检查退出时是否有未付款物品（供追击系统使用）
function ShopScene.GetUnpaidItems()
    if not gameState then return {} end
    local unpaid = {}
    for _, item in ipairs(gameState.inventory) do
        local isPaid = false
        for _, paid in ipairs(paidItems) do
            if paid == item then isPaid = true; break end
        end
        if not isPaid then
            table.insert(unpaid, item)
        end
    end
    return unpaid
end



-- ====================================================================
-- 获取当前附近交互区（供外部显示提示）
-- ====================================================================
function ShopScene.GetNearbyZone()
    return nearbyZone
end

function ShopScene.IsShelfOpen()
    return shelfOpen
end

-- ====================================================================
-- 门口警告面板
-- ====================================================================
function ShopScene.ShowDoorWarning()
    doorWarningOpen = true
    doorWarningChoice = 1
end

function ShopScene.IsDoorWarningOpen()
    return doorWarningOpen
end

function ShopScene.DoorWarningNavigate(direction)
    doorWarningChoice = doorWarningChoice + direction
    if doorWarningChoice < 1 then doorWarningChoice = 2 end
    if doorWarningChoice > 2 then doorWarningChoice = 1 end
end

function ShopScene.DoorWarningConfirm()
    doorWarningOpen = false
    if doorWarningChoice == 1 then
        -- "回去付款" → 关闭警告，留在商店
        print("[ShopScene] 玩家选择回去付款")
    else
        -- "硬闯" → 强制离开，触发追击
        print("[ShopScene] 玩家选择硬闯！")
        ShopScene.Exit()
    end
end

function ShopScene.CloseDoorWarning()
    doorWarningOpen = false
end

-- ====================================================================
-- 鼠标点击支持（由 main.lua 调用）
-- ====================================================================

--- 设置 hover/pressed 状态（每帧由 main.lua 驱动）
function ShopScene.SetHoverState(hovered, pressed)
    shopHoveredBtn = hovered
    shopPressedBtn = pressed
end

--- 判断逻辑坐标(mx,my)处有什么按钮，返回按钮id或nil
function ShopScene.GetButtonAtPosition(mx, my)
    -- 门口警告面板按钮
    if doorWarningOpen then
        local panelW = 320
        local panelH = 180
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        local optStartY = panelY + 100
        for i = 1, 2 do
            local oy = optStartY + (i - 1) * 32
            local btnLeft = panelX + 30
            local btnRight = panelX + panelW - 30
            if mx >= btnLeft and mx <= btnRight and my >= oy and my <= oy + 28 then
                return "shop_warning_" .. i
            end
        end
        return nil  -- 面板打开时，其他按钮不可触达
    end

    -- 柜台对话面板按钮
    if counterOpen and #counterOptions > 0 then
        local panelW = 340
        local panelH = 200
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2
        local optStartY = panelY + panelH - 20 - #counterOptions * 30
        for i = 1, #counterOptions do
            local oy = optStartY + (i - 1) * 30
            local btnLeft = panelX + 20
            local btnRight = panelX + panelW - 20
            if mx >= btnLeft and mx <= btnRight and my >= oy and my <= oy + 26 then
                return "shop_counter_" .. i
            end
        end
        return nil  -- 面板打开时，其他按钮不可触达
    end

    return nil
end

--- 执行按钮点击
function ShopScene.ExecuteButtonClick(btnId)
    if not btnId then return false end

    -- 门口警告按钮
    if btnId:sub(1, 13) == "shop_warning_" then
        local idx = tonumber(btnId:sub(14))
        if idx then
            doorWarningChoice = idx
            ShopScene.DoorWarningConfirm()
        end
        return true
    end

    -- 柜台对话按钮
    if btnId:sub(1, 13) == "shop_counter_" then
        local idx = tonumber(btnId:sub(14))
        if idx and idx >= 1 and idx <= #counterOptions then
            counterSelectedIdx = idx
            ShopScene.CounterConfirm()
        end
        return true
    end

    return false
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================
function ShopScene.Render(nvgCtx, sw, sh)
    if not active then return end
    screenW = sw
    screenH = sh
    FLOOR_Y = screenH - 100

    -- 背景（室内墙壁）
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(240, 235, 225, 255))
    nvgFill(nvgCtx)

    -- 地板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, FLOOR_Y, screenW, screenH - FLOOR_Y)
    nvgFillColor(nvgCtx, nvgRGBA(180, 140, 100, 255))
    nvgFill(nvgCtx)

    -- 地板格子纹
    nvgStrokeColor(nvgCtx, nvgRGBA(160, 120, 80, 100))
    nvgStrokeWidth(nvgCtx, 1)
    for i = 0, math.ceil(screenW / 50) do
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, i * 50, FLOOR_Y)
        nvgLineTo(nvgCtx, i * 50, screenH)
        nvgStroke(nvgCtx)
    end

    -- 天花板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, CEILING_H)
    nvgFillColor(nvgCtx, nvgRGBA(60, 55, 50, 255))
    nvgFill(nvgCtx)

    -- 日光灯
    for i = 1, 3 do
        local lx = screenW * i / 4
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, lx - 40, CEILING_H - 8, 80, 6)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 240, 230))
        nvgFill(nvgCtx)
        -- 灯光光晕
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, lx - 50, CEILING_H, 100, 15)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 200, 30))
        nvgFill(nvgCtx)
    end

    -- 后墙装饰线
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, CEILING_H, screenW, 3)
    nvgFillColor(nvgCtx, nvgRGBA(120, 100, 80, 200))
    nvgFill(nvgCtx)

    -- 门（左侧）
    RenderDoor(nvgCtx)

    -- 货架
    for _, shelf in ipairs(shelves) do
        RenderShelf(nvgCtx, shelf)
    end

    -- 柜台 + 店员
    RenderCounter(nvgCtx)

    -- 玩家
    RenderShopPlayer(nvgCtx)

    -- 交互提示（货架面板没开时才显示）
    if nearbyZone and not shelfOpen then
        RenderInteractPrompt(nvgCtx)
    end

    -- 携带栏（始终显示在底部）
    RenderInventoryBar(nvgCtx)

    -- 货架面板浮窗（覆盖在上层）
    if shelfOpen then
        RenderShelfPanel(nvgCtx)
    end

    -- 柜台对话面板
    if counterOpen then
        RenderCounterPanel(nvgCtx)
    end

    -- 门口警告面板
    if doorWarningOpen then
        RenderDoorWarningPanel(nvgCtx)
    end
end

-- ====================================================================
-- 子渲染函数
-- ====================================================================
function RenderDoor(nvgCtx)
    local dx = DOOR_X
    local dw = 50
    local dh = 90
    local dy = FLOOR_Y - dh

    -- 门框
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx - 3, dy - 3, dw + 6, dh + 3)
    nvgFillColor(nvgCtx, nvgRGBA(80, 60, 40, 255))
    nvgFill(nvgCtx)

    -- 门板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx, dy, dw, dh)
    nvgFillColor(nvgCtx, nvgRGBA(140, 100, 60, 255))
    nvgFill(nvgCtx)

    -- 门把手
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, dx + dw - 10, dy + dh / 2, 4)
    nvgFillColor(nvgCtx, nvgRGBA(200, 180, 50, 255))
    nvgFill(nvgCtx)

    -- 门上方"出口"标志
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(0, 200, 0, 255))
    nvgText(nvgCtx, dx + dw / 2, dy - 12, "EXIT")
end

function RenderShelf(nvgCtx, shelf)
    local sx = shelf.x
    local sw = shelf.w
    local sh = 140  -- 货架高度
    local sy = FLOOR_Y - sh

    -- 货架背板
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, sx, sy, sw, sh)
    nvgFillColor(nvgCtx, nvgRGBA(200, 180, 150, 255))
    nvgFill(nvgCtx)

    -- 货架边框
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, sx, sy, sw, sh)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 100, 70, 255))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 隔板（3层）
    for row = 1, 3 do
        local ly = sy + row * (sh / 4)
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, sx + 2, ly, sw - 4, 3)
        nvgFillColor(nvgCtx, nvgRGBA(150, 130, 100, 255))
        nvgFill(nvgCtx)

        -- 每层放一些彩色方块代表商品
        local itemCount = 3
        local itemW = (sw - 20) / itemCount
        for col = 1, itemCount do
            local ix = sx + 8 + (col - 1) * (itemW + 2)
            local iy = ly - (sh / 4) + 8
            local iw = itemW - 2
            local ih = (sh / 4) - 12

            -- 商品颜色根据分类不同
            local colors = {
                snack = { { 255, 80, 80 }, { 255, 200, 50 }, { 100, 200, 100 } },
                stationery = { { 50, 100, 200 }, { 200, 100, 200 }, { 100, 200, 200 } },
                electronics = { { 40, 40, 50 }, { 60, 60, 70 }, { 30, 30, 40 } },
                charger = { { 255, 255, 255 }, { 40, 40, 40 }, { 50, 150, 255 } },
            }
            local cList = colors[shelf.category] or colors.snack
            local c = cList[((row - 1) * itemCount + col - 1) % #cList + 1]

            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, ix, iy, iw, ih, 2)
            nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 220))
            nvgFill(nvgCtx)
        end
    end

    -- 货架标签
    nvgFontSize(nvgCtx, 10)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(80, 60, 40, 255))
    nvgText(nvgCtx, sx + sw / 2, FLOOR_Y + 5, shelf.label)
end

function RenderCounter(nvgCtx)
    local cx = COUNTER_X
    local cw = 100
    local ch = 60
    local cy = FLOOR_Y - ch

    -- 柜台
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, cx, cy, cw, ch, 4)
    nvgFillColor(nvgCtx, nvgRGBA(100, 70, 40, 255))
    nvgFill(nvgCtx)

    -- 柜台面
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, cx - 5, cy, cw + 10, 6)
    nvgFillColor(nvgCtx, nvgRGBA(140, 110, 70, 255))
    nvgFill(nvgCtx)

    -- 收银机
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, cx + 30, cy - 25, 35, 25, 3)
    nvgFillColor(nvgCtx, nvgRGBA(50, 50, 60, 255))
    nvgFill(nvgCtx)
    -- 屏幕
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, cx + 33, cy - 22, 29, 15)
    nvgFillColor(nvgCtx, nvgRGBA(100, 200, 100, 200))
    nvgFill(nvgCtx)

    -- 店员（站在柜台后面）
    local npcX = cx + cw / 2
    local npcY = FLOOR_Y

    -- 身体
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, npcX - 12, npcY - 55, 24, 35, 4)
    nvgFillColor(nvgCtx, nvgRGBA(30, 100, 180, 255)) -- 蓝色制服
    nvgFill(nvgCtx)

    -- 头
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, npcX, npcY - 65, 12)
    nvgFillColor(nvgCtx, nvgRGBA(240, 200, 160, 255))
    nvgFill(nvgCtx)

    -- 表情（微笑）
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, npcX - 4, npcY - 67, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, npcX + 4, npcY - 67, 2)
    nvgFillColor(nvgCtx, nvgRGBA(40, 40, 40, 255))
    nvgFill(nvgCtx)

    -- 名牌
    nvgFontSize(nvgCtx, 8)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, npcX, npcY - 40, "店员")
end

function RenderShopPlayer(nvgCtx)
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

    -- 眼睛（朝向）
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

function RenderInteractPrompt(nvgCtx)
    if not nearbyZone then return end

    local text = "[F] " .. nearbyZone.label
    local tx = playerX
    local ty = FLOOR_Y - 85

    nvgFontSize(nvgCtx, 12)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 背景
    local tw = nvgTextBounds(nvgCtx, 0, 0, text)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, tx - tw / 2 - 8, ty - 10, tw + 16, 20, 6)
    nvgFillColor(nvgCtx, nvgRGBA(20, 20, 40, 220))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 200))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 文字
    nvgFillColor(nvgCtx, nvgRGBA(220, 240, 255, 255))
    nvgText(nvgCtx, tx, ty, text)
end

-- ====================================================================
-- 携带栏渲染
-- ====================================================================
function RenderInventoryBar(nvgCtx)
    if not gameState then return end

    local barH = 50
    local barY = screenH - barH
    local slotSize = 38
    local slotGap = 6
    local maxSlots = gameState.inventoryMax
    local totalW = maxSlots * slotSize + (maxSlots - 1) * slotGap
    local startX = (screenW - totalW) / 2

    -- 背景条
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, startX - 12, barY + 2, totalW + 24, barH - 4, 8)
    nvgFillColor(nvgCtx, nvgRGBA(20, 18, 35, 220))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(60, 60, 100, 180))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 渲染每个槽位
    for i = 1, maxSlots do
        local sx = startX + (i - 1) * (slotSize + slotGap)
        local sy = barY + 6
        local hasItem = (i <= #gameState.inventory)
        local isSelected = (inventoryMode and i == inventorySelectedIdx)

        -- 槽位背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, sx, sy, slotSize, slotSize, 5)
        if isSelected then
            nvgFillColor(nvgCtx, nvgRGBA(60, 80, 140, 230))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(100, 200, 255, 255))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)
        elseif hasItem then
            nvgFillColor(nvgCtx, nvgRGBA(40, 40, 60, 200))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(80, 80, 120, 200))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
        else
            nvgFillColor(nvgCtx, nvgRGBA(30, 30, 45, 150))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(50, 50, 70, 150))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
        end

        -- 物品图标（简化为彩色方块+首字）
        if hasItem then
            local item = gameState.inventory[i]
            -- 分类颜色
            local catColors = {
                snack = { 255, 120, 80 },
                stationery = { 80, 150, 255 },
                electronics = { 180, 180, 200 },
                charger = { 80, 255, 150 },
            }
            local cc = catColors[item.category] or { 200, 200, 200 }

            -- 物品小方块
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, sx + 6, sy + 4, slotSize - 12, slotSize - 16, 3)
            nvgFillColor(nvgCtx, nvgRGBA(cc[1], cc[2], cc[3], 200))
            nvgFill(nvgCtx)

            -- 物品名首字
            local firstChar = string.sub(item.name, 1, 3)  -- UTF-8一个中文字3字节
            nvgFontSize(nvgCtx, 9)
            nvgFontFace(nvgCtx, "sans")
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 230))
            nvgText(nvgCtx, sx + slotSize / 2, sy + slotSize - 13, firstChar)
        end
    end

    -- 操作提示
    nvgFontSize(nvgCtx, 9)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(120, 120, 160, 200))
    if inventoryMode then
        nvgText(nvgCtx, screenW / 2, barY - 6, "[A/D]选择  [Q]放回  [Tab]退出携带栏")
    else
        local invCount = #gameState.inventory
        if invCount > 0 then
            nvgText(nvgCtx, screenW / 2, barY - 6, "[Tab]查看携带栏 (" .. invCount .. "/" .. maxSlots .. ")")
        end
    end

    -- 选中物品详情（携带栏模式时）
    if inventoryMode and inventorySelectedIdx > 0 and inventorySelectedIdx <= #gameState.inventory then
        local item = gameState.inventory[inventorySelectedIdx]
        nvgFontSize(nvgCtx, 11)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(220, 220, 255, 255))
        nvgText(nvgCtx, screenW / 2, barY - 20, item.name .. " - ¥" .. item.price)
    end
end

-- ====================================================================
-- 货架面板渲染
-- ====================================================================
function RenderShelfPanel(nvgCtx)
    -- 半透明背景遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 120))
    nvgFill(nvgCtx)

    -- 面板
    local panelW = 320
    local panelH = 280
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    -- 面板背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(nvgCtx, nvgRGBA(30, 28, 45, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(80, 80, 140, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    local catNames = {
        snack = "零食饮料",
        stationery = "日用文具",
        electronics = "电子配件",
        charger = "充电设备",
    }
    local title = catNames[shelfCategory] or "货架"
    nvgFontSize(nvgCtx, 15)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 255))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + 20, title)

    -- 商品列表
    if #shelfItems == 0 then
        nvgFontSize(nvgCtx, 12)
        nvgFillColor(nvgCtx, nvgRGBA(150, 150, 170, 255))
        nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH / 2, "货架空空如也")
    else
        local startY = panelY + 42
        local itemH = 40
        local maxVisible = 5

        -- 获取鼠标位置做 hover 高亮（转换为逻辑坐标）
        local mousePos = input:GetMousePosition()
        local dpr = graphics:GetDPR()
        local mx, my = mousePos.x / dpr, mousePos.y / dpr

        for i = 1, math.min(#shelfItems, maxVisible) do
            local item = shelfItems[i]
            local iy = startY + (i - 1) * itemH
            local rowLeft = panelX + 10
            local rowRight = panelX + panelW - 10
            local rowTop = iy
            local rowBottom = iy + itemH - 4
            local isHover = (mx >= rowLeft and mx <= rowRight and my >= rowTop and my <= rowBottom)

            -- 悬停高亮
            if isHover then
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, rowLeft, rowTop, panelW - 20, itemH - 4, 6)
                nvgFillColor(nvgCtx, nvgRGBA(50, 60, 100, 200))
                nvgFill(nvgCtx)
                nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 200))
                nvgStrokeWidth(nvgCtx, 1)
                nvgStroke(nvgCtx)
            end

            -- 商品图标 (28×28)
            local iconPath = AssetMap.Items[item.id]
            if iconPath then
                AssetMap.DrawImage(nvgCtx, iconPath, rowLeft + 4, rowTop + 2, 28, 28)
            end

            -- 商品名（图标后偏移）
            local textOffsetX = iconPath and 38 or 10
            nvgFontSize(nvgCtx, 12)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, isHover and nvgRGBA(255, 255, 255, 255) or nvgRGBA(200, 200, 220, 255))
            nvgText(nvgCtx, panelX + textOffsetX, iy + 12, item.name)

            -- 价格
            nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(255, 200, 50, 255))
            nvgText(nvgCtx, panelX + panelW - 20, iy + 12, "¥" .. item.price)

            -- 描述（悬停时显示）
            if isHover and item.desc then
                nvgFontSize(nvgCtx, 9)
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvgCtx, nvgRGBA(160, 160, 200, 220))
                nvgText(nvgCtx, panelX + 20, iy + 28, item.desc)
            end
        end
    end

    -- 底部操作提示
    local bottomY = panelY + panelH - 22
    nvgFontSize(nvgCtx, 10)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(140, 140, 180, 255))
    nvgText(nvgCtx, panelX + panelW / 2, bottomY,
        "点击商品拿取  [ESC]关闭")

    -- 携带栏状态
    if gameState then
        nvgFontSize(nvgCtx, 9)
        nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(120, 120, 160, 255))
        nvgText(nvgCtx, panelX + panelW - 15, panelY + panelH - 38,
            "携带: " .. #gameState.inventory .. "/" .. gameState.inventoryMax)
    end

    -- 操作反馈消息
    if shelfMessage then
        nvgFontSize(nvgCtx, 12)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 150, 255))
        nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH - 50, shelfMessage)
    end
end

-- ====================================================================
-- 柜台对话面板渲染
-- ====================================================================
function RenderCounterPanel(nvgCtx)
    -- 半透明遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 130))
    nvgFill(nvgCtx)

    -- 对话面板
    local panelW = 340
    local panelH = 200
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    -- 面板背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvgCtx, nvgRGBA(25, 30, 50, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(80, 120, 180, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 店员头像区域（左上角小图标）
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, panelX + 28, panelY + 30, 16)
    nvgFillColor(nvgCtx, nvgRGBA(30, 100, 180, 255))
    nvgFill(nvgCtx)
    nvgFontSize(nvgCtx, 10)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
    nvgText(nvgCtx, panelX + 28, panelY + 30, "店")

    -- 店员名字
    nvgFontSize(nvgCtx, 11)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(180, 200, 255, 255))
    nvgText(nvgCtx, panelX + 50, panelY + 26, "店员")

    -- 对话文本（支持多行）
    nvgFontSize(nvgCtx, 12)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(220, 220, 240, 255))

    -- 分行渲染对话
    local lines = {}
    for line in counterDialogue:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    for i, line in ipairs(lines) do
        nvgText(nvgCtx, panelX + 20, panelY + 52 + (i - 1) * 18, line)
    end

    -- 选项列表（支持鼠标 hover/pressed 三态）
    local optStartY = panelY + panelH - 20 - #counterOptions * 30
    for i, opt in ipairs(counterOptions) do
        local oy = optStartY + (i - 1) * 30
        local btnId = "shop_counter_" .. i
        local isSelected = (i == counterSelectedIdx)
        local isHovered = (shopHoveredBtn == btnId)
        local isPressed = (shopPressedBtn == btnId) and isHovered

        -- 鼠标 hover 时自动更新键盘选中索引
        if isHovered then
            counterSelectedIdx = i
            isSelected = true
        end

        -- 选项背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 20, oy, panelW - 40, 26, 5)
        if isPressed then
            nvgFillColor(nvgCtx, nvgRGBA(70, 100, 160, 250))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(130, 200, 255, 255))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)
        elseif isSelected or isHovered then
            nvgFillColor(nvgCtx, nvgRGBA(50, 70, 120, 230))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
        else
            nvgFillColor(nvgCtx, nvgRGBA(40, 45, 65, 180))
            nvgFill(nvgCtx)
        end

        -- 选项文字
        nvgFontSize(nvgCtx, 12)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, (isSelected or isHovered) and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 180, 200, 255))
        nvgText(nvgCtx, panelX + panelW / 2, oy + 13, opt.text)
    end

    -- 底部操作提示
    nvgFontSize(nvgCtx, 9)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(120, 120, 160, 180))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH - 8, "[W/S]选择  [F]确认  [ESC]离开")
end

-- (老虎机已移至NPC对话系统，见main.lua)

-- ====================================================================
-- 门口警告面板渲染
-- ====================================================================
function RenderDoorWarningPanel(nvgCtx)
    -- 遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, screenW, screenH)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 150))
    nvgFill(nvgCtx)

    -- 面板
    local panelW = 320
    local panelH = 180
    local panelX = (screenW - panelW) / 2
    local panelY = (screenH - panelH) / 2

    -- 面板背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvgCtx, nvgRGBA(40, 20, 20, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 80, 80, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 警告图标
    nvgFontSize(nvgCtx, 20)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 80, 50, 255))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + 24, "⚠ 警告")

    -- 警告文本
    nvgFontSize(nvgCtx, 12)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 200, 255))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + 52, "你还有物品没有付款！")
    nvgFontSize(nvgCtx, 11)
    nvgFillColor(nvgCtx, nvgRGBA(200, 180, 160, 220))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + 72, "直接离开的话店员会追出来哦")

    -- 两个选项（支持鼠标 hover/pressed 三态）
    local options = { "回去付款", "硬闯（会被追）" }
    local optStartY = panelY + 100
    for i = 1, 2 do
        local oy = optStartY + (i - 1) * 32
        local btnId = "shop_warning_" .. i
        local isSelected = (i == doorWarningChoice)
        local isHovered = (shopHoveredBtn == btnId)
        local isPressed = (shopPressedBtn == btnId) and isHovered

        -- 鼠标 hover 时自动更新键盘选中索引
        if isHovered then
            doorWarningChoice = i
            isSelected = true
        end

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + 30, oy, panelW - 60, 28, 6)
        if isPressed then
            -- 按下态：更深背景 + 亮边框
            nvgFillColor(nvgCtx, nvgRGBA(120, 50, 50, 250))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(255, 160, 100, 255))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)
        elseif isSelected or isHovered then
            nvgFillColor(nvgCtx, nvgRGBA(80, 40, 40, 230))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(255, 120, 80, 220))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
        else
            nvgFillColor(nvgCtx, nvgRGBA(50, 30, 30, 180))
            nvgFill(nvgCtx)
        end

        nvgFontSize(nvgCtx, 12)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, (isSelected or isHovered) and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 160, 160, 255))
        nvgText(nvgCtx, panelX + panelW / 2, oy + 14, options[i])
    end

    -- 操作提示
    nvgFontSize(nvgCtx, 9)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(120, 100, 100, 180))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + panelH - 12, "[W/S]选择  [F]确认  [ESC]取消")
end

return ShopScene
