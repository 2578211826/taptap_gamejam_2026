-- ====================================================================
-- AssetMap.lua - 素材路径映射与NanoVG图片加载工具
-- ====================================================================
-- 统一管理所有美术资源的路径映射，提供懒加载缓存机制
-- ====================================================================

local AssetMap = {}

-- NanoVG 图片句柄缓存 (path → handle)
local imageCache = {}

-- ====================================================================
-- 商品图标 (64×64 透明背景)
-- ====================================================================
AssetMap.Items = {
    -- 零食饮料
    cola        = "image/items/snacks/商品_可乐_20260530111930.png",
    chips       = "image/items/snacks/商品_薯片_20260530111923.png",
    candy       = "image/items/snacks/商品_糖果_20260530112048.png",
    water       = "image/items/snacks/商品_矿泉水_20260530111924.png",
    coffee      = "image/items/snacks/商品_咖啡_20260530111925.png",
    -- 日用文具
    pen         = "image/items/stationery/商品_圆珠笔_20260530111924.png",
    notebook    = "image/items/stationery/商品_笔记本_20260530111928.png",
    tape        = "image/items/stationery/商品_胶带_20260530111926.png",
    scissors    = "image/items/stationery/商品_剪刀_20260530111927.png",
    glue        = "image/items/stationery/商品_胶水_20260530111928.png",
    -- 电子配件（充电头）
    charger_2pin_usba  = "image/items/electronics/商品_TypeC充电头_20260530112206.png",
    charger_2pin_typec = "image/items/electronics/商品_TypeC充电头_20260530112206.png",
    charger_3pin_usba  = "image/items/electronics/商品_万能充电头_20260530112210.png",
    charger_3pin_typec = "image/items/electronics/商品_万能充电头_20260530112210.png",
    -- 数据线
    cable_usba_typec     = "image/items/electronics/商品_TypeC数据线_20260530112207.png",
    cable_usba_lightning = "image/items/electronics/商品_Lightning数据线_20260530112210.png",
    cable_usba_microusb  = "image/items/electronics/商品_MicroUSB数据线_20260530112248.png",
    cable_typec_typec    = "image/items/electronics/商品_TypeC数据线_20260530112207.png",
    cable_typec_lightning= "image/items/electronics/商品_Lightning数据线_20260530112210.png",
    cable_typec_microusb = "image/items/electronics/商品_MicroUSB数据线_20260530112248.png",
    -- 转接头
    adapter_2to3 = "image/items/electronics/商品_TC转L转接头_20260530112327.png",
    adapter_3to2 = "image/items/electronics/商品_USB转Micro转接头_20260530112335.png",
}

-- ====================================================================
-- 杂货铺室内组件
-- ====================================================================
AssetMap.ShopInterior = {
    -- 背景层（天花板/地板暗色条带 512×217，锯齿边缘 2048×100）
    ceiling_band  = "image/shop_interior/天花板_纯暗色条带_20260531012044.png",
    ceiling_edge  = "image/shop_interior/天花板_锯齿边缘_cropped.png",
    floor_band    = "image/shop_interior/地面_纯暗色条带_20260531011929.png",
    floor_edge    = "image/shop_interior/地面_锯齿边缘_cropped.png",
    -- 物件精灵
    lamp       = "image/shop_interior/杂货铺_日光灯_20260531025209.png",
    door       = "image/shop_interior/杂货铺_出口门_20260530180725.png",
    counter    = "image/shop_interior/杂货铺_收银台_20260530180816.png",   -- 402×300（含收银机）
    wall_ads   = "image/shop_interior/杂货铺_墙面海报_20260531025211.png",
    boxes      = "image/shop_interior/杂货铺_纸箱堆_20260531025225.png",
    -- 分类货架精灵（300×402 竖版）
    shelf_snack       = "image/shop_interior/杂货铺_货架_零食饮料_20260530182429.png",
    shelf_stationery  = "image/shop_interior/杂货铺_货架_日用文具_20260530182431.png",
    shelf_electronics = "image/shop_interior/杂货铺_货架_电子配件_20260530182531.png",
    shelf_charger     = "image/shop_interior/杂货铺_货架_充电设备_20260530182524.png",
}

-- ====================================================================
-- 交互物件 (透明背景)
-- ====================================================================
AssetMap.Interactables = {
    powerbank = "image/interactables/交互_充电宝柜_20260530112416.png",    -- 143×256
    outlet    = "image/interactables/交互_墙壁插座_20260530112416.png",    -- 64×64
    shop      = "image/interactables/交互_商店门面_20260530112417.png",    -- 256×256
}

-- ====================================================================
-- NPC (143×256 透明背景)
-- ====================================================================
AssetMap.NPC = {
    -- 玩家角色（Q版纸片人）
    player = {
        idle = "image/human/玩家/idle.png",
        talk = "image/human/玩家/talk.png",
        walk = "image/human/玩家/walk.png",
    },

    -- 新版多动作角色（Q版纸片人）
    clerk = {
        idle  = "image/human/店员/idle.png",
        talk  = "image/human/店员/talk.png",
        chase = "image/human/店员/chase.png",
    },
    merchant = {
        idle = "image/human/奸商/idle.png",
        talk = "image/human/奸商/talk.png",
        walk = "image/human/奸商/walk.png",
    },
    office_worker = {
        idle = "image/human/上班族/idle.png",
        talk = "image/human/上班族/talk.png",
        walk = "image/human/上班族/walk.png",
    },
}

-- NPC随机池（大地图路人使用，每次随机选一个）
AssetMap.NPCPool = {
    AssetMap.NPC.merchant.walk,
    AssetMap.NPC.office_worker.walk,
    AssetMap.NPC.clerk.idle,
}

-- ====================================================================
-- 街道道具 (透明背景)
-- ====================================================================
AssetMap.Props = {
    trashcan   = "image/props/道具_垃圾桶_20260530112506.png",        -- 71×128
    vending    = "image/props/道具_自贩机_20260530112555.png",        -- 143×256
    billboard_a= "image/props/道具_广告牌A_20260530112508.png",       -- 143×256
    billboard_b= "image/props/道具_广告牌B_20260530112508.png",       -- 143×256
    hydrant    = "image/props/道具_消防栓_20260530112504.png",        -- 71×128
    pole       = "image/props/道具_电线杆_20260530112507.png",        -- 143×256
}

-- ====================================================================
-- 建筑贴图原始列表（仅供注册表引用）
-- ====================================================================
AssetMap.Buildings = {
    { path = "image/buildings/建筑_便利店_20260530110909.png", w = 286, h = 354 },
    { path = "image/buildings/建筑_网吧_20260530110917.png",   w = 286, h = 373 },
    { path = "image/buildings/建筑_居民楼A_20260530110910.png", w = 286, h = 433 },
    { path = "image/buildings/建筑_药房_20260530110913.png",   w = 286, h = 315 },
    { path = "image/buildings/建筑_废弃店面_20260530111029.png", w = 286, h = 457 },
    { path = "image/buildings/建筑_拉面店_20260530111106.png", w = 286, h = 254 },
    { path = "image/buildings/建筑_写字楼_20260530111109.png", w = 286, h = 453 },
    { path = "image/buildings/建筑_KTV_20260530111111.png",   w = 286, h = 383 },
}

-- ====================================================================
-- 🏢 统一建筑注册表（贴图 + 名称 + 场景处理器 + 室内配置 全部绑定）
-- ====================================================================
-- handler: "shop" = 杂货铺(ShopScene), "cafe" = 网吧(InternetCafeScene), "generic" = 通用室内
-- interiorKey: 对应 GenericInteriorScene.BuildingConfigs 的 key（仅 handler="generic" 时使用）
-- ====================================================================
AssetMap.BuildingRegistry = {
    shop = {
        texIdx = 1,  -- 便利店贴图
        name = "杂货铺",
        icon = "shop",
        handler = "shop",        -- ShopScene 专属
        interiorKey = nil,
    },
    cafe = {
        texIdx = 2,  -- 网吧贴图
        name = "网吧",
        icon = "cafe",
        handler = "cafe",        -- InternetCafeScene 专属
        interiorKey = nil,
    },
    residential = {
        texIdx = 3,  -- 居民楼A贴图
        name = "居民楼门厅",
        icon = "building",
        handler = "generic",
        interiorKey = "residential",
    },
    pharmacy = {
        texIdx = 4,  -- 药房贴图
        name = "药房",
        icon = "building",
        handler = "generic",
        interiorKey = "pharmacy",
    },
    abandoned = {
        texIdx = 5,  -- 废弃店面贴图
        name = "废弃店面",
        icon = "building",
        handler = "generic",
        interiorKey = "abandoned",
    },
    ramen = {
        texIdx = 6,  -- 拉面店贴图
        name = "拉面店",
        icon = "building",
        handler = "generic",
        interiorKey = "ramen",
    },
    office = {
        texIdx = 7,  -- 写字楼贴图
        name = "写字楼大厅",
        icon = "building",
        handler = "generic",
        interiorKey = "office",
    },
    ktv = {
        texIdx = 8,  -- KTV贴图
        name = "KTV",
        icon = "building",
        handler = "generic",
        interiorKey = "ktv",
    },
}

-- 通用建筑池（随机抽取用，不含 shop/cafe 这两种固定建筑）
AssetMap.GenericBuildingPool = { "residential", "pharmacy", "abandoned", "ramen", "office", "ktv" }

-- ====================================================================
-- 环境
-- ====================================================================
AssetMap.Environment = {
    sky    = "image/environment/环境_夜空背景_20260530111105.png",     -- 1024×572
    ground = "image/environment/环境_地面纹理_20260530111112.png",     -- 1024×572
    lamp   = "image/environment/环境_路灯_20260530111144.png",         -- 286×512
    -- 远景建筑簇（透明底，2-4栋紧挨的建筑组合）
    bg_buildings = {
        { path = "image/远景建筑簇_写字楼组A_20260530165618.png", w = 429, h = 259 },
        { path = "image/远景建筑簇_居民楼组B_20260530165619.png", w = 450, h = 275 },
        { path = "image/远景建筑簇_工业组C_20260530165624.png",   w = 320, h = 348 },
        { path = "image/远景建筑簇_高楼组D_20260530165620.png",   w = 350, h = 446 },
        { path = "image/远景建筑簇_混合组E_20260530165617.png",   w = 429, h = 278 },
        { path = "image/远景建筑簇_塔楼组F_20260530165618.png",   w = 287, h = 364 },
    },
}

-- ====================================================================
-- 结局插画 (512×512 不透明)
-- ====================================================================
AssetMap.Endings = {
    win        = "image/endings/结局_胜利充满电_20260530112906.png",
    no_battery = "image/endings/结局_电量耗尽_20260530112856.png",
    stolen     = "image/endings/结局_手机被偷_20260530112854.png",
    dead       = "image/endings/结局_死亡_20260530112857.png",
    arrested   = "image/endings/结局_被捕_20260530112859.png",
}

-- ====================================================================
-- NanoVG 图片加载工具（带缓存）
-- ====================================================================

--- 加载图片并缓存 NanoVG handle。首次调用时创建，后续返回缓存。
---@param nvg NVGContextWrapper
---@param path string 资源路径
---@return integer handle (0 表示失败)
function AssetMap.GetImage(nvg, path)
    if not path then return 0 end
    if imageCache[path] then return imageCache[path] end

    local handle = nvgCreateImage(nvg, path, 0)
    if handle and handle > 0 then
        imageCache[path] = handle
    else
        print("[AssetMap] Failed to load: " .. path)
        imageCache[path] = 0
        return 0
    end
    return handle
end

--- 绘制图片到指定矩形区域
---@param nvg NVGContextWrapper
---@param path string 资源路径
---@param x number 左上角X
---@param y number 左上角Y
---@param w number 宽度
---@param h number 高度
---@param alpha? number 透明度 0~1 (默认1)
function AssetMap.DrawImage(nvg, path, x, y, w, h, alpha)
    local handle = AssetMap.GetImage(nvg, path)
    if handle == 0 then return false end

    local paint = nvgImagePattern(nvg, x, y, w, h, 0, handle, alpha or 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    return true
end

--- 绘制图片（居中锚点）
---@param nvg NVGContextWrapper
---@param path string 资源路径
---@param cx number 中心X
---@param cy number 中心Y (底部对齐时传 bottom - h/2)
---@param w number 宽度
---@param h number 高度
---@param alpha? number
function AssetMap.DrawImageCentered(nvg, path, cx, cy, w, h, alpha)
    return AssetMap.DrawImage(nvg, path, cx - w / 2, cy - h / 2, w, h, alpha)
end

--- 绘制图片（底部居中锚点，适合站在地面的角色/物体）
---@param nvg NVGContextWrapper
---@param path string 资源路径
---@param cx number 中心X
---@param bottomY number 底部Y（地面位置）
---@param w number 宽度
---@param h number 高度
---@param alpha? number
function AssetMap.DrawImageBottom(nvg, path, cx, bottomY, w, h, alpha)
    return AssetMap.DrawImage(nvg, path, cx - w / 2, bottomY - h, w, h, alpha)
end

--- 清除所有缓存的图片句柄（场景切换时调用）
---@param nvg NVGContextWrapper
function AssetMap.ClearCache(nvg)
    for path, handle in pairs(imageCache) do
        if handle > 0 then
            nvgDeleteImage(nvg, handle)
        end
    end
    imageCache = {}
end

return AssetMap
