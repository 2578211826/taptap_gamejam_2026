-- ====================================================================
-- ItemData.lua - 商品数据与兼容链系统
-- ====================================================================
-- 充电兼容链：插座(2孔/3孔) → 插头(2脚/3脚) → 充电器输出(USB-A/TypeC)
--            → 数据线A端 → 数据线B端 → 手机端口(TypeC/Lightning/MicroUSB)
-- ====================================================================

local ItemData = {}

-- ====================================================================
-- 端口/接口类型枚举
-- ====================================================================
ItemData.PhonePort = {
    TYPE_C = "typec",
    LIGHTNING = "lightning",
    MICRO_USB = "microusb",
}

ItemData.OutletType = {
    TWO_HOLE = "2hole",    -- 两孔插座
    THREE_HOLE = "3hole",  -- 三孔插座
}

ItemData.PlugType = {
    TWO_PIN = "2pin",      -- 两脚插头
    THREE_PIN = "3pin",    -- 三脚插头
}

ItemData.ChargerOutput = {
    USB_A = "usb_a",
    TYPE_C = "typec",
}

ItemData.CableEndA = {      -- 插充电器那头
    USB_A = "usb_a",
    TYPE_C = "typec",
}

ItemData.CableEndB = {      -- 插手机那头
    TYPE_C = "typec",
    LIGHTNING = "lightning",
    MICRO_USB = "microusb",
}

-- ====================================================================
-- 商品定义
-- ====================================================================
-- 每个商品: { id, name, price, category, desc, [兼容属性] }
-- category: "snack", "stationery", "electronics", "charger"
-- ====================================================================

ItemData.AllItems = {
    -- ===== 零食饮料 =====
    { id = "cola",      name = "可乐",       price = 3,   category = "snack",   desc = "冰凉提神，但不能充电" },
    { id = "chips",     name = "薯片",       price = 5,   category = "snack",   desc = "嘎嘣脆，也不能充电" },
    { id = "candy",     name = "棒棒糖",     price = 2,   category = "snack",   desc = "甜的，然而手机还是没电" },
    { id = "water",     name = "矿泉水",     price = 2,   category = "snack",   desc = "水是生命之源，不是电源" },
    { id = "coffee",    name = "罐装咖啡",   price = 6,   category = "snack",   desc = "你清醒了，手机没有" },

    -- ===== 日用文具 =====
    { id = "pen",       name = "圆珠笔",     price = 3,   category = "stationery", desc = "能写遗书，但充不了电" },
    { id = "notebook",  name = "笔记本",     price = 8,   category = "stationery", desc = "记录一下你找充电宝的惨痛经历" },
    { id = "tape",      name = "透明胶带",   price = 4,   category = "stationery", desc = "粘不住流逝的电量" },
    { id = "scissors",  name = "剪刀",       price = 6,   category = "stationery", desc = "剪不断理还乱的充电线" },
    { id = "glue",      name = "502胶水",    price = 5,   category = "stationery", desc = "别想着粘充电口" },

    -- ===== 电子配件 =====
    { id = "charger_2pin_usba",  name = "双脚充电头(USB-A)", price = 25, category = "electronics",
      desc = "2脚插头，USB-A输出口", plugType = "2pin", chargerOutput = "usb_a" },
    { id = "charger_2pin_typec", name = "双脚充电头(Type-C)", price = 30, category = "electronics",
      desc = "2脚插头，Type-C输出口", plugType = "2pin", chargerOutput = "typec" },
    { id = "charger_3pin_usba",  name = "三脚充电头(USB-A)", price = 28, category = "electronics",
      desc = "3脚插头，USB-A输出口", plugType = "3pin", chargerOutput = "usb_a" },
    { id = "charger_3pin_typec", name = "三脚充电头(Type-C)", price = 35, category = "electronics",
      desc = "3脚插头，Type-C输出口", plugType = "3pin", chargerOutput = "typec" },

    -- ===== 充电设备（数据线） =====
    { id = "cable_usba_typec",      name = "数据线(A转C)",       price = 15, category = "charger",
      desc = "USB-A → Type-C", cableEndA = "usb_a", cableEndB = "typec" },
    { id = "cable_usba_lightning",   name = "数据线(A转Lightning)", price = 20, category = "charger",
      desc = "USB-A → Lightning", cableEndA = "usb_a", cableEndB = "lightning" },
    { id = "cable_usba_microusb",    name = "数据线(A转Micro)",   price = 10, category = "charger",
      desc = "USB-A → Micro USB", cableEndA = "usb_a", cableEndB = "microusb" },
    { id = "cable_typec_typec",      name = "数据线(C转C)",       price = 20, category = "charger",
      desc = "Type-C → Type-C", cableEndA = "typec", cableEndB = "typec" },
    { id = "cable_typec_lightning",  name = "数据线(C转Lightning)", price = 25, category = "charger",
      desc = "Type-C → Lightning", cableEndA = "typec", cableEndB = "lightning" },
    { id = "cable_typec_microusb",   name = "数据线(C转Micro)",   price = 12, category = "charger",
      desc = "Type-C → Micro USB", cableEndA = "typec", cableEndB = "microusb" },

    -- ===== 转接头 =====
    { id = "adapter_2to3",  name = "两转三转接头", price = 8, category = "electronics",
      desc = "让2脚插头能插3孔插座", adapterFrom = "2pin", adapterTo = "3pin" },
    { id = "adapter_3to2",  name = "三转两转接头", price = 8, category = "electronics",
      desc = "让3脚插头能插2孔插座", adapterFrom = "3pin", adapterTo = "2pin" },
}

-- ====================================================================
-- 按分类获取商品列表
-- ====================================================================
function ItemData.GetByCategory(category)
    local result = {}
    for _, item in ipairs(ItemData.AllItems) do
        if item.category == category then
            table.insert(result, item)
        end
    end
    return result
end

-- ====================================================================
-- 根据ID查找商品
-- ====================================================================
function ItemData.GetById(id)
    for _, item in ipairs(ItemData.AllItems) do
        if item.id == id then
            return item
        end
    end
    return nil
end

-- ====================================================================
-- 随机生成本局货架库存（每个分类随机选3-4个商品）
-- ====================================================================
function ItemData.GenerateShopStock(phonePort, outletType)
    local stock = {}

    -- 确保至少有一条可通关的物品路线
    -- 根据手机端口和插座类型，保证有正确的线和充电头

    for _, cat in ipairs({ "snack", "stationery", "electronics", "charger" }) do
        local pool = ItemData.GetByCategory(cat)
        local selected = {}

        if cat == "electronics" or cat == "charger" then
            -- 电子配件和充电设备：确保有正确搭配的选项在货架上
            -- 先随机打乱
            local shuffled = {}
            for _, item in ipairs(pool) do
                table.insert(shuffled, item)
            end
            for i = #shuffled, 2, -1 do
                local j = math.random(1, i)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end
            -- 取前4个（保证品类有足够可选）
            for i = 1, math.min(4, #shuffled) do
                table.insert(selected, shuffled[i])
            end
        else
            -- 零食/文具：随机选3个
            local shuffled = {}
            for _, item in ipairs(pool) do
                table.insert(shuffled, item)
            end
            for i = #shuffled, 2, -1 do
                local j = math.random(1, i)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end
            for i = 1, math.min(3, #shuffled) do
                table.insert(selected, shuffled[i])
            end
        end

        stock[cat] = selected
    end

    return stock
end

-- ====================================================================
-- 验证兼容链是否完整
-- ====================================================================
-- 参数：inventory（玩家物品列表）、phonePort、outletType
-- 返回：success, reason
function ItemData.CheckChargingChain(inventory, phonePort, outletType)
    -- 1. 找充电头
    local charger = nil
    for _, item in ipairs(inventory) do
        if item.plugType and item.chargerOutput then
            charger = item
            break
        end
    end
    if not charger then
        return false, "缺少充电头"
    end

    -- 2. 检查插头与插座兼容
    local plugFits = false
    if outletType == "2hole" and charger.plugType == "2pin" then
        plugFits = true
    elseif outletType == "3hole" and charger.plugType == "3pin" then
        plugFits = true
    end

    -- 检查是否有转接头
    if not plugFits then
        for _, item in ipairs(inventory) do
            if item.adapterFrom == charger.plugType and item.adapterTo then
                -- 转接后检查
                local newPlug = item.adapterTo
                if (outletType == "2hole" and newPlug == "2pin") or
                   (outletType == "3hole" and newPlug == "3pin") then
                    plugFits = true
                    break
                end
            end
        end
    end

    if not plugFits then
        return false, "插头和插座不匹配（需要" ..
            (outletType == "2hole" and "两脚" or "三脚") .. "插头）"
    end

    -- 3. 找数据线
    local cable = nil
    for _, item in ipairs(inventory) do
        if item.cableEndA and item.cableEndB then
            -- A端需匹配充电器输出
            if item.cableEndA == charger.chargerOutput then
                cable = item
                break
            end
        end
    end
    if not cable then
        return false, "缺少数据线（或数据线A端与充电头不匹配，需要" .. charger.chargerOutput .. "接口）"
    end

    -- 4. 检查线B端与手机端口
    if cable.cableEndB ~= phonePort then
        return false, "数据线接口与手机不匹配（你的手机是" .. phonePort .. "口）"
    end

    return true, "兼容链完整！可以充电！"
end

return ItemData
