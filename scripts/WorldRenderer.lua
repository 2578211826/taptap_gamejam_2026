-- ====================================================================
-- WorldRenderer.lua - 城市场景渲染
-- ====================================================================

local Config = require("Config")

local WorldRenderer = {}

-- 建筑数据（在 Init 中生成）
local buildings = {}
local signs = {}
local interactables = {}
local worldWidth = 0
local groundY = 0

-- 广告文案池
local adTexts = {
    "出生保险\n断缴者禁入",
    "低电量焦虑\n解决方案999",
    "跨纪元通勤\n补贴已取消",
    "扫码租伞\n首单免费",
    "时间移民\n低首付",
    "充电宝月卡\n仅99.9/月",
    "恢复税\n分期免息",
    "AI推荐\n量身焦虑",
    "买房送\n出生保险",
    "免押充电\n扫码下载APP",
}

-- 店铺名
local shopNames = {
    "7-24便利店",
    "快充杂货铺",
    "赛博大排档",
    "时代青旅",
    "网红奶茶",
    "跨纪元快递",
}

function WorldRenderer.Init(screenW, screenH)
    groundY = screenH - Config.World.GroundHeight
    Config.Player.GroundY = groundY
    buildings = {}
    signs = {}
    interactables = {}

    -- 生成城市建筑
    local x = 0
    local buildingIndex = 0
    worldWidth = screenW * 4 -- 4 屏幕宽的地图

    while x < worldWidth do
        buildingIndex = buildingIndex + 1
        local w = math.random(100, 200)
        local h = math.random(Config.World.BuildingMinHeight, Config.World.BuildingMaxHeight)
        -- 预生成窗户亮灭状态（避免每帧随机导致闪烁）
        local winCols = math.floor((w - 20) / (12 + 8))
        local winRows = math.floor((h - 30) / (16 + 8 + 4))
        local windowLit = {}
        for r = 1, math.min(winRows, 8) do
            windowLit[r] = {}
            for c = 1, math.min(winCols, 5) do
                windowLit[r][c] = math.random() > 0.4
            end
        end

        local glowPalette = {
            { 255, 50, 100 }, { 50, 200, 255 }, { 255, 200, 0 }, { 0, 255, 150 }
        }

        local building = {
            x = x,
            y = groundY - h,
            w = w,
            h = h,
            color = WorldRenderer.RandomBuildingColor(),
            windows = math.random(2, 5),
            windowLit = windowLit,  -- 预生成窗户状态
            hasSign = math.random() > 0.4,
            signText = adTexts[math.random(1, #adTexts)],
            signColor = glowPalette[math.random(1, #glowPalette)],  -- 预生成广告牌颜色
        }
        table.insert(buildings, building)

        -- 添加可交互物品
        if buildingIndex == 2 then
            -- 共享充电宝柜（第2栋建筑前）
            table.insert(interactables, {
                type = "powerbank",
                x = x + w / 2,
                y = groundY,
                label = "共享充电宝",
                icon = "battery",
            })
        elseif buildingIndex == 4 then
            -- 便利店（第4栋建筑）
            table.insert(interactables, {
                type = "shop",
                x = x + w / 2,
                y = groundY,
                label = "杂货铺",
                icon = "shop",
            })
        elseif buildingIndex == 6 then
            -- 插座（第6栋建筑）
            table.insert(interactables, {
                type = "outlet",
                x = x + w / 2,
                y = groundY,
                label = "墙壁插座",
                icon = "plug",
            })
        elseif buildingIndex == 3 or buildingIndex == 5 then
            -- NPC
            table.insert(interactables, {
                type = "npc",
                x = x + w / 2 + 30,
                y = groundY,
                label = "路人",
                icon = "person",
            })
        end

        x = x + w + math.random(40, 80)
    end
end

function WorldRenderer.GetInteractables()
    return interactables
end

function WorldRenderer.GetWorldWidth()
    return worldWidth
end

function WorldRenderer.GetGroundY()
    return groundY
end

function WorldRenderer.RandomBuildingColor()
    local palettes = {
        { 60, 65, 80 },
        { 50, 55, 70 },
        { 70, 60, 80 },
        { 45, 50, 65 },
        { 55, 60, 75 },
        { 65, 55, 70 },
    }
    return palettes[math.random(1, #palettes)]
end

function WorldRenderer.Render(nvg, cameraX, screenW, screenH)
    -- 背景天空（深蓝渐变 - 夜晚城市）
    local skyGrad = nvgLinearGradient(nvg, 0, 0, 0, screenH,
        nvgRGBA(15, 10, 35, 255), nvgRGBA(40, 25, 60, 255))
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, screenW, screenH)
    nvgFillPaint(nvg, skyGrad)
    nvgFill(nvg)

    -- 远景建筑剪影
    nvgBeginPath(nvg)
    local farOffset = cameraX * 0.3
    for i = 0, 20 do
        local bx = i * 120 - (farOffset % 120)
        local bh = 80 + math.sin(i * 1.7) * 40
        nvgRect(nvg, bx, groundY - bh - 50, 100, bh + 50)
    end
    nvgFillColor(nvg, nvgRGBA(20, 15, 40, 200))
    nvgFill(nvg)

    -- 主建筑
    for _, b in ipairs(buildings) do
        local sx = b.x - cameraX
        if sx > -b.w and sx < screenW + 50 then
            -- 建筑体
            nvgBeginPath(nvg)
            nvgRect(nvg, sx, b.y, b.w, b.h)
            nvgFillColor(nvg, nvgRGBA(b.color[1], b.color[2], b.color[3], 255))
            nvgFill(nvg)

            -- 窗户（使用预生成的亮灭状态）
            local winW = 12
            local winH = 16
            local winGap = 8
            local cols = math.floor((b.w - 20) / (winW + winGap))
            local rows = math.floor((b.h - 30) / (winH + winGap + 4))
            for row = 1, math.min(rows, 8) do
                for col = 1, math.min(cols, 5) do
                    local wx = sx + 10 + (col - 1) * (winW + winGap)
                    local wy = b.y + 15 + (row - 1) * (winH + winGap + 4)
                    local lit = b.windowLit[row] and b.windowLit[row][col]
                    nvgBeginPath(nvg)
                    nvgRect(nvg, wx, wy, winW, winH)
                    if lit then
                        nvgFillColor(nvg, nvgRGBA(255, 220, 100, 160))
                    else
                        nvgFillColor(nvg, nvgRGBA(20, 20, 30, 200))
                    end
                    nvgFill(nvg)
                end
            end

            -- 广告牌
            if b.hasSign then
                local signW = math.min(b.w - 10, 90)
                local signH = 35
                local signX = sx + (b.w - signW) / 2
                local signY = b.y - signH - 5
                -- 发光背景
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, signX - 2, signY - 2, signW + 4, signH + 4, 3)
                local gc = b.signColor
                nvgFillColor(nvg, nvgRGBA(gc[1], gc[2], gc[3], 150))
                nvgFill(nvg)
                -- 文字
                nvgFontSize(nvg, 10)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
                nvgText(nvg, signX + signW / 2, signY + signH / 2, b.signText)
            end
        end
    end

    -- 地面
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, groundY, screenW, Config.World.GroundHeight)
    nvgFillColor(nvg, nvgRGBA(35, 35, 45, 255))
    nvgFill(nvg)

    -- 地面纹理线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, 0, groundY)
    nvgLineTo(nvg, screenW, groundY)
    nvgStrokeColor(nvg, nvgRGBA(80, 80, 100, 200))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- 人行道标记
    local markOffset = cameraX % 60
    for i = 0, math.ceil(screenW / 60) + 1 do
        local mx = i * 60 - markOffset
        nvgBeginPath(nvg)
        nvgRect(nvg, mx, groundY + 10, 30, 4)
        nvgFillColor(nvg, nvgRGBA(80, 80, 90, 150))
        nvgFill(nvg)
    end

    -- 可交互物品
    WorldRenderer.RenderInteractables(nvg, cameraX, screenW)
end

function WorldRenderer.RenderInteractables(nvg, cameraX, screenW)
    for _, item in ipairs(interactables) do
        local sx = item.x - cameraX
        if sx > -50 and sx < screenW + 50 then
            local iy = item.y

            if item.type == "powerbank" then
                -- 充电宝柜
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, sx - 25, iy - 70, 50, 70, 4)
                nvgFillColor(nvg, nvgRGBA(60, 180, 60, 255))
                nvgFill(nvg)
                -- 屏幕
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - 18, iy - 60, 36, 25)
                nvgFillColor(nvg, nvgRGBA(200, 255, 200, 200))
                nvgFill(nvg)
                -- 标签
                nvgFontSize(nvg, 9)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
                nvgText(nvg, sx, iy - 75, "充电宝")

            elseif item.type == "shop" then
                -- 便利店门面
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - 40, iy - 80, 80, 80)
                nvgFillColor(nvg, nvgRGBA(200, 150, 50, 255))
                nvgFill(nvg)
                -- 招牌
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - 40, iy - 95, 80, 18)
                nvgFillColor(nvg, nvgRGBA(255, 80, 80, 255))
                nvgFill(nvg)
                nvgFontSize(nvg, 11)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
                nvgText(nvg, sx, iy - 86, "杂货铺")

            elseif item.type == "outlet" then
                -- 墙壁插座
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, sx - 12, iy - 45, 24, 30, 3)
                nvgFillColor(nvg, nvgRGBA(220, 220, 220, 255))
                nvgFill(nvg)
                -- 插孔
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx - 4, iy - 32, 3)
                nvgCircle(nvg, sx + 4, iy - 32, 3)
                nvgFillColor(nvg, nvgRGBA(40, 40, 40, 255))
                nvgFill(nvg)

            elseif item.type == "npc" then
                -- 路人（简笔画小人）
                -- 头
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, iy - 55, 10)
                nvgFillColor(nvg, nvgRGBA(200, 170, 140, 255))
                nvgFill(nvg)
                -- 身体
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, sx - 10, iy - 42, 20, 30, 4)
                local npcColors = {
                    { 100, 150, 200 }, { 200, 100, 100 }, { 150, 200, 100 }, { 200, 150, 50 }
                }
                local nc = npcColors[(math.floor(item.x) % #npcColors) + 1]
                nvgFillColor(nvg, nvgRGBA(nc[1], nc[2], nc[3], 255))
                nvgFill(nvg)
                -- 看手机的姿态（一条手臂弯曲）
                nvgBeginPath(nvg)
                nvgRect(nvg, sx + 5, iy - 38, 8, 12)
                nvgFillColor(nvg, nvgRGBA(30, 30, 40, 255))
                nvgFill(nvg)
            end
        end
    end
end

function WorldRenderer.RenderPlayer(nvg, px, py, facingRight, phoneOpen)
    -- 角色（简笔画风格）
    local dir = facingRight and 1 or -1

    -- 身体
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px - 12, py - 45, 24, 33, 5)
    nvgFillColor(nvg, nvgRGBA(80, 80, 120, 255))
    nvgFill(nvg)

    -- 头
    nvgBeginPath(nvg)
    nvgCircle(nvg, px, py - 55, 12)
    nvgFillColor(nvg, nvgRGBA(220, 185, 155, 255))
    nvgFill(nvg)

    -- 头发
    nvgBeginPath(nvg)
    nvgArc(nvg, px, py - 58, 12, -3.14, 0, 1)
    nvgFillColor(nvg, nvgRGBA(40, 30, 20, 255))
    nvgFill(nvg)

    -- 腿
    nvgBeginPath(nvg)
    nvgRect(nvg, px - 8, py - 12, 7, 12)
    nvgRect(nvg, px + 1, py - 12, 7, 12)
    nvgFillColor(nvg, nvgRGBA(50, 50, 70, 255))
    nvgFill(nvg)

    -- 手和手机
    if phoneOpen then
        -- 举着手机
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px + dir * 14, py - 50, 12, 20, 2)
        nvgFillColor(nvg, nvgRGBA(20, 20, 30, 255))
        nvgFill(nvg)
        -- 手机屏幕光
        nvgBeginPath(nvg)
        nvgRect(nvg, px + dir * 15, py - 48, 10, 16)
        nvgFillColor(nvg, nvgRGBA(150, 200, 255, 200))
        nvgFill(nvg)
    else
        -- 手臂放下
        nvgBeginPath(nvg)
        nvgRect(nvg, px + dir * 10, py - 40, 6, 18)
        nvgFillColor(nvg, nvgRGBA(220, 185, 155, 255))
        nvgFill(nvg)
    end
end

return WorldRenderer
