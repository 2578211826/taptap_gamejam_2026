-- ====================================================================
-- WorldRenderer.lua - 城市场景渲染（贴图版）
-- ====================================================================

local Config = require("Config")
local AssetMap = require("AssetMap")

local WorldRenderer = {}

-- 建筑数据（在 Init 中生成）
local buildings = {}
local interactables = {}
local props = {}       -- 街道装饰道具
local lamps = {}       -- 路灯位置
local worldWidth = 0
local groundY = 0

-- 远景建筑层（三层视差）
local bgLayers = {
    far     = {},  -- 最远，最慢，最暗
    midFar  = {},  -- 中远
    mid     = {},  -- 中景，较快，较亮
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

-- 道具池（用于随机放置）
local propPool = {
    { key = "trashcan", w = 35, h = 64 },
    { key = "vending",  w = 50, h = 90 },
    { key = "hydrant",  w = 30, h = 55 },
    { key = "pole",     w = 30, h = 100 },
}

function WorldRenderer.Init(screenW, screenH)
    groundY = screenH - Config.World.GroundHeight
    Config.Player.GroundY = groundY
    buildings = {}
    interactables = {}
    props = {}
    lamps = {}

    -- ===== 生成三层远景建筑 =====
    local bgAssets = AssetMap.Environment.bg_buildings
    local numBgTextures = #bgAssets
    local bgLayerConfigs = {
        { key = "far",    count = 16, scaleMin = 0.28, scaleMax = 0.42, yOffsetMin = 60, yOffsetMax = 130, gap = 80 },
        { key = "midFar", count = 12, scaleMin = 0.4, scaleMax = 0.58,  yOffsetMin = 20, yOffsetMax = 70,  gap = 100 },
        { key = "mid",    count = 10, scaleMin = 0.5, scaleMax = 0.72,  yOffsetMin = 0,  yOffsetMax = 30,  gap = 130 },
    }
    -- 使用固定种子保证每次 Init 生成一致的远景
    math.randomseed(42)
    for _, cfg in ipairs(bgLayerConfigs) do
        bgLayers[cfg.key] = {}
        local x = math.random(0, 40)
        for i = 1, cfg.count do
            local texIdx = math.random(1, numBgTextures)
            local asset = bgAssets[texIdx]
            local scale = cfg.scaleMin + math.random() * (cfg.scaleMax - cfg.scaleMin)
            local yOffset = cfg.yOffsetMin + math.random() * (cfg.yOffsetMax - cfg.yOffsetMin)
            table.insert(bgLayers[cfg.key], {
                x = x,
                yOffset = yOffset,
                texPath = asset.path,
                w = asset.w * scale,
                h = asset.h * scale,
            })
            -- 下一簇的位置：当前簇宽度 + 随机间隔（密集排列）
            x = x + asset.w * scale + math.random(10, cfg.gap)
        end
    end
    -- 恢复随机种子
    math.randomseed(os.time())

    -- 生成城市建筑
    local x = 0
    local buildingIndex = 0
    worldWidth = screenW * 4 -- 4 屏幕宽的地图
    local numBuildingTextures = #AssetMap.Buildings

    while x < worldWidth do
        buildingIndex = buildingIndex + 1
        local w = math.random(100, 200)
        local h = math.random(Config.World.BuildingMinHeight, Config.World.BuildingMaxHeight)

        -- 分配建筑贴图（循环使用）
        local texIdx = ((buildingIndex - 1) % numBuildingTextures) + 1

        -- 预生成窗户亮灭状态（贴图建筑上叠加的发光窗户效果）
        local winCols = math.floor((w - 20) / (12 + 8))
        local winRows = math.floor((h - 30) / (16 + 8 + 4))
        local windowLit = {}
        for r = 1, math.min(winRows, 8) do
            windowLit[r] = {}
            for c = 1, math.min(winCols, 5) do
                windowLit[r][c] = math.random() > 0.4
            end
        end

        local texInfo = AssetMap.Buildings[texIdx]
        local building = {
            x = x,
            y = groundY - h,
            w = w,
            h = h,
            texPath = texInfo.path,
            texW = texInfo.w,
            texH = texInfo.h,
            color = WorldRenderer.RandomBuildingColor(),
            windows = math.random(2, 5),
            windowLit = windowLit,
        }
        table.insert(buildings, building)

        -- 添加可交互物品
        if buildingIndex == 2 then
            table.insert(interactables, {
                type = "powerbank",
                x = x + w / 2,
                y = groundY,
                label = "共享充电宝",
                icon = "battery",
            })
        elseif buildingIndex == 4 then
            table.insert(interactables, {
                type = "shop",
                x = x + w / 2,
                y = groundY,
                label = "杂货铺",
                icon = "shop",
            })
        elseif buildingIndex == 6 then
            table.insert(interactables, {
                type = "outlet",
                x = x + w / 2,
                y = groundY,
                label = "墙壁插座",
                icon = "plug",
            })
        elseif buildingIndex == 3 or buildingIndex == 5 then
            table.insert(interactables, {
                type = "npc",
                x = x + w / 2 + 30,
                y = groundY,
                label = "路人",
                icon = "person",
                npcIdx = (buildingIndex == 3) and 1 or 2,  -- 路人甲/乙
            })
        end

        -- 在建筑间隙放置街道道具和路灯
        local gapStart = x + w
        local gapW = math.random(40, 80)

        -- 路灯（每隔2~3栋建筑放一个）
        if buildingIndex % 2 == 0 then
            table.insert(lamps, { x = gapStart + gapW / 2 })
        end

        -- 随机道具（30%概率）
        if math.random() > 0.7 and gapW > 50 then
            local propDef = propPool[math.random(1, #propPool)]
            table.insert(props, {
                x = gapStart + math.random(10, math.max(11, gapW - 30)),
                key = propDef.key,
                w = propDef.w,
                h = propDef.h,
            })
        end

        x = gapStart + gapW
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
    -- ===== 背景天空 =====
    -- 尝试使用贴图（cover模式：保持比例填满区域），失败时回退程序化渲染
    local skyHandle = AssetMap.GetImage(nvg, AssetMap.Environment.sky)
    if skyHandle > 0 then
        -- 天空纹理 1024×572，用 cover 方式：保持比例覆盖整个天空区域
        local skyAreaW = screenW
        local skyAreaH = groundY
        -- 原始比例 1024:572 ≈ 1.79:1
        local texAspect = 1.79
        local areaAspect = skyAreaW / skyAreaH
        local paintW, paintH
        if areaAspect > texAspect then
            -- 区域更宽，以宽度为准
            paintW = skyAreaW
            paintH = skyAreaW / texAspect
        else
            -- 区域更高，以高度为准
            paintH = skyAreaH
            paintW = skyAreaH * texAspect
        end
        -- 居中偏移（略偏移实现视差）
        local paintX = (skyAreaW - paintW) / 2 - cameraX * 0.1
        local paintY = (skyAreaH - paintH) / 2
        local paint = nvgImagePattern(nvg, paintX, paintY, paintW, paintH, 0, skyHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, skyAreaW, skyAreaH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    else
        local skyGrad = nvgLinearGradient(nvg, 0, 0, 0, screenH,
            nvgRGBA(15, 10, 35, 255), nvgRGBA(40, 25, 60, 255))
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, screenW, screenH)
        nvgFillPaint(nvg, skyGrad)
        nvgFill(nvg)
    end

    -- ===== 三层远景建筑簇（不同视差速度） =====
    local layerRenderConfigs = {
        { key = "far",    parallax = 0.1,  alpha = 0.35 },
        { key = "midFar", parallax = 0.25, alpha = 0.55 },
        { key = "mid",    parallax = 0.45, alpha = 0.75 },
    }
    for _, lrc in ipairs(layerRenderConfigs) do
        local layer = bgLayers[lrc.key]
        local pOffset = cameraX * lrc.parallax
        for _, b in ipairs(layer) do
            local sx = b.x - pOffset
            if sx > -b.w and sx < screenW + b.w then
                local by = groundY - b.h  -- 底部严格贴地面
                AssetMap.DrawImage(nvg, b.texPath, sx, by, b.w, b.h, lrc.alpha)
            end
        end
    end

    -- ===== 主建筑（贴图） =====
    for _, b in ipairs(buildings) do
        local sx = b.x - cameraX
        if sx > -b.w - 50 and sx < screenW + 50 then
            -- 绘制建筑贴图：保持各贴图自身宽高比，底部严格对齐地面
            local texAspect = b.texW / b.texH  -- 每张贴图各自的宽高比
            local drawW = b.w
            local drawH = drawW / texAspect  -- 按宽度计算保持比例的高度
            local drawY = groundY - drawH    -- 底部贴齐地面
            local drawn = AssetMap.DrawImage(nvg, b.texPath, sx, drawY, drawW, drawH)
            if not drawn then
                -- 贴图失败时回退为程序化色块
                nvgBeginPath(nvg)
                nvgRect(nvg, sx, b.y, b.w, b.h)
                nvgFillColor(nvg, nvgRGBA(b.color[1], b.color[2], b.color[3], 255))
                nvgFill(nvg)

                -- 窗户
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
            end
        end
    end

    -- ===== 街道道具贴图 =====
    for _, prop in ipairs(props) do
        local sx = prop.x - cameraX
        if sx > -prop.w and sx < screenW + prop.w then
            local path = AssetMap.Props[prop.key]
            if path then
                AssetMap.DrawImageBottom(nvg, path, sx, groundY, prop.w, prop.h)
            end
        end
    end

    -- ===== 路灯贴图 =====
    for _, lamp in ipairs(lamps) do
        local sx = lamp.x - cameraX
        if sx > -50 and sx < screenW + 50 then
            AssetMap.DrawImageBottom(nvg, AssetMap.Environment.lamp, sx, groundY, 40, 100)
        end
    end

    -- ===== 地面（平铺纹理，保持比例） =====
    local groundH = Config.World.GroundHeight
    local groundHandle = AssetMap.GetImage(nvg, AssetMap.Environment.ground)
    if groundHandle > 0 then
        local tileH = groundH
        local tileW = tileH * 1.79 -- 保持原始宽高比 (1024/572 ≈ 1.79)
        local offsetX = -(cameraX % tileW)
        local paint = nvgImagePattern(nvg, offsetX, groundY, tileW, tileH, 0, groundHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, groundY, screenW, groundH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    else
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, groundY, screenW, groundH)
        nvgFillColor(nvg, nvgRGBA(35, 35, 45, 255))
        nvgFill(nvg)
    end

    -- 地面分界线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, 0, groundY)
    nvgLineTo(nvg, screenW, groundY)
    nvgStrokeColor(nvg, nvgRGBA(80, 80, 100, 200))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    -- ===== 可交互物品 =====
    WorldRenderer.RenderInteractables(nvg, cameraX, screenW)
end

function WorldRenderer.RenderInteractables(nvg, cameraX, screenW)
    for _, item in ipairs(interactables) do
        local sx = item.x - cameraX
        if sx > -80 and sx < screenW + 80 then
            local iy = item.y
            local drawn = false

            if item.type == "powerbank" then
                -- 充电宝柜贴图 (143×256 → 缩放到 50×90)
                drawn = AssetMap.DrawImageBottom(nvg, AssetMap.Interactables.powerbank,
                    sx, iy, 50, 90)
                if not drawn then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, sx - 25, iy - 70, 50, 70, 4)
                    nvgFillColor(nvg, nvgRGBA(60, 180, 60, 255))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - 18, iy - 60, 36, 25)
                    nvgFillColor(nvg, nvgRGBA(200, 255, 200, 200))
                    nvgFill(nvg)
                end
                -- 标签
                nvgFontSize(nvg, 9)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
                nvgText(nvg, sx, iy - 95, "充电宝")

            elseif item.type == "shop" then
                -- 便利店门面贴图 (256×256 → 缩放到 100×100)
                drawn = AssetMap.DrawImageBottom(nvg, AssetMap.Interactables.shop,
                    sx, iy, 100, 100)
                if not drawn then
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - 40, iy - 80, 80, 80)
                    nvgFillColor(nvg, nvgRGBA(200, 150, 50, 255))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - 40, iy - 95, 80, 18)
                    nvgFillColor(nvg, nvgRGBA(255, 80, 80, 255))
                    nvgFill(nvg)
                end
                nvgFontSize(nvg, 11)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
                nvgText(nvg, sx, iy - 106, "杂货铺")

            elseif item.type == "outlet" then
                -- 墙壁插座贴图 (64×64 → 缩放到 28×28)
                drawn = AssetMap.DrawImageBottom(nvg, AssetMap.Interactables.outlet,
                    sx, iy - 15, 28, 28)
                if not drawn then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, sx - 12, iy - 45, 24, 30, 3)
                    nvgFillColor(nvg, nvgRGBA(220, 220, 220, 255))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx - 4, iy - 32, 3)
                    nvgCircle(nvg, sx + 4, iy - 32, 3)
                    nvgFillColor(nvg, nvgRGBA(40, 40, 40, 255))
                    nvgFill(nvg)
                end

            elseif item.type == "npc" then
                -- NPC贴图 (143×256 → 缩放到 40×72)
                local npcPath
                if item.npcIdx == 1 then
                    npcPath = AssetMap.NPC.passerby_a
                else
                    npcPath = AssetMap.NPC.passerby_b
                end
                drawn = AssetMap.DrawImageBottom(nvg, npcPath, sx, iy, 40, 72)
                if not drawn then
                    -- 回退：简笔画小人
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, iy - 55, 10)
                    nvgFillColor(nvg, nvgRGBA(200, 170, 140, 255))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, sx - 10, iy - 42, 20, 30, 4)
                    local npcColors = {
                        { 100, 150, 200 }, { 200, 100, 100 }, { 150, 200, 100 }, { 200, 150, 50 }
                    }
                    local nc = npcColors[(math.floor(item.x) % #npcColors) + 1]
                    nvgFillColor(nvg, nvgRGBA(nc[1], nc[2], nc[3], 255))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx + 5, iy - 38, 8, 12)
                    nvgFillColor(nvg, nvgRGBA(30, 30, 40, 255))
                    nvgFill(nvg)
                end
            end
        end
    end
end

function WorldRenderer.RenderPlayer(nvg, px, py, facingRight, phoneOpen)
    -- 角色（简笔画风格，保持原样）
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
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px + dir * 14, py - 50, 12, 20, 2)
        nvgFillColor(nvg, nvgRGBA(20, 20, 30, 255))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgRect(nvg, px + dir * 15, py - 48, 10, 16)
        nvgFillColor(nvg, nvgRGBA(150, 200, 255, 200))
        nvgFill(nvg)
    else
        nvgBeginPath(nvg)
        nvgRect(nvg, px + dir * 10, py - 40, 6, 18)
        nvgFillColor(nvg, nvgRGBA(220, 185, 155, 255))
        nvgFill(nvg)
    end
end

return WorldRenderer
