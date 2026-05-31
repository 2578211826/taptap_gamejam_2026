-- ====================================================================
-- PowerbankSystem.lua - 充电宝柜全局管理模块
-- ====================================================================
-- 管理全部充电宝柜的状态（可用/空柜/离线），
-- 每30秒进行状态刷新，保证至少2个可用。
-- ====================================================================

local PowerbankSystem = {}

-- 充电宝柜状态枚举
PowerbankSystem.State = {
    AVAILABLE = "available",   -- 有充电宝可借
    EMPTY     = "empty",       -- 柜内无充电宝
    OFFLINE   = "offline",     -- 设备离线/故障
}

-- 所有充电宝柜数据
local stations = {}          -- { id, buildingIndex, x, state, location }
local tickTimer = 0          -- 30秒计时器
local TICK_INTERVAL = 30     -- 秒
local MIN_AVAILABLE = 2      -- 最少可用数量
local CHANGE_CHANCE = 0.5    -- 每次 tick 每个柜子 50% 概率变化

-- 当前场景中玩家所在的 buildingIndex（在室内时跳过该柜子的 tick）
local currentSceneBuilding = nil

-- ====================================================================
-- 初始化 - 根据建筑数据生成充电宝柜
-- ====================================================================

--- 初始化充电宝系统
---@param buildingCount number 总建筑数量
function PowerbankSystem.Init(buildingCount)
    stations = {}
    tickTimer = 0
    currentSceneBuilding = nil
end

--- 注册一个充电宝柜
---@param id string 唯一标识
---@param buildingIndex number 所属建筑索引
---@param x number 世界坐标X
---@param location string 位置描述（如 "街道" / "杂货铺内" / "网吧内"）
function PowerbankSystem.Register(id, buildingIndex, x, location)
    local station = {
        id = id,
        buildingIndex = buildingIndex,
        x = x,
        state = PowerbankSystem.State.AVAILABLE,  -- 初始默认可用
        location = location or "街道",
    }
    table.insert(stations, station)
end

--- 批量生成初始状态（保证至少 MIN_AVAILABLE 个可用）
function PowerbankSystem.RandomizeStates()
    local count = #stations
    if count == 0 then return end

    -- 先全部随机分配
    local states = { PowerbankSystem.State.AVAILABLE, PowerbankSystem.State.EMPTY, PowerbankSystem.State.OFFLINE }
    for _, s in ipairs(stations) do
        s.state = states[math.random(1, 3)]
    end

    -- 保证最少可用数
    PowerbankSystem._ensureMinAvailable()

    print("[PowerbankSystem] 初始化 " .. count .. " 个充电宝柜, 可用: " .. PowerbankSystem.GetAvailableCount())
end

-- ====================================================================
-- 更新 - 每30秒 tick
-- ====================================================================

--- 每帧更新（由 main.lua HandleUpdate 调用）
---@param dt number 帧间隔
function PowerbankSystem.Update(dt)
    if #stations == 0 then return end

    tickTimer = tickTimer + dt
    if tickTimer >= TICK_INTERVAL then
        tickTimer = tickTimer - TICK_INTERVAL
        PowerbankSystem._tick()
    end
end

--- 30秒 tick：每个柜子有50%概率状态变化
function PowerbankSystem._tick()
    local states = { PowerbankSystem.State.AVAILABLE, PowerbankSystem.State.EMPTY, PowerbankSystem.State.OFFLINE }

    for _, s in ipairs(stations) do
        -- 跳过当前玩家所在建筑的柜子（防止正在交互时突然变化）
        if currentSceneBuilding and s.buildingIndex == currentSceneBuilding then
            goto continue
        end

        -- 50% 概率变化
        if math.random() < CHANGE_CHANCE then
            -- 随机切换到另一个状态（排除当前状态）
            local newStates = {}
            for _, st in ipairs(states) do
                if st ~= s.state then
                    table.insert(newStates, st)
                end
            end
            s.state = newStates[math.random(1, #newStates)]
        end

        ::continue::
    end

    -- 保底：保证至少 MIN_AVAILABLE 个可用
    PowerbankSystem._ensureMinAvailable()

    print("[PowerbankSystem] Tick完成, 可用: " .. PowerbankSystem.GetAvailableCount() .. "/" .. #stations)
end

--- 保证至少 MIN_AVAILABLE 个柜子可用
function PowerbankSystem._ensureMinAvailable()
    local available = PowerbankSystem.GetAvailableCount()
    if available >= MIN_AVAILABLE then return end

    -- 从不可用的柜子中随机选择补充
    local unavailable = {}
    for _, s in ipairs(stations) do
        if s.state ~= PowerbankSystem.State.AVAILABLE then
            table.insert(unavailable, s)
        end
    end

    -- 打乱顺序
    for i = #unavailable, 2, -1 do
        local j = math.random(1, i)
        unavailable[i], unavailable[j] = unavailable[j], unavailable[i]
    end

    local needed = MIN_AVAILABLE - available
    for i = 1, math.min(needed, #unavailable) do
        unavailable[i].state = PowerbankSystem.State.AVAILABLE
    end
end

-- ====================================================================
-- 查询 API
-- ====================================================================

--- 获取所有充电宝柜数据（供地图等使用）
---@return table[] stations
function PowerbankSystem.GetAll()
    return stations
end

--- 获取可用柜子数量
---@return number
function PowerbankSystem.GetAvailableCount()
    local count = 0
    for _, s in ipairs(stations) do
        if s.state == PowerbankSystem.State.AVAILABLE then
            count = count + 1
        end
    end
    return count
end

--- 根据 buildingIndex 查找柜子
---@param buildingIndex number
---@return table|nil station
function PowerbankSystem.GetByBuilding(buildingIndex)
    for _, s in ipairs(stations) do
        if s.buildingIndex == buildingIndex then
            return s
        end
    end
    return nil
end

--- 根据 id 查找柜子
---@param id string
---@return table|nil station
function PowerbankSystem.GetById(id)
    for _, s in ipairs(stations) do
        if s.id == id then
            return s
        end
    end
    return nil
end

--- 查找最近的可用柜子（世界坐标）
---@param playerX number 玩家当前X
---@return table|nil station, number|nil distance
function PowerbankSystem.FindNearestAvailable(playerX)
    local nearest = nil
    local minDist = math.huge
    for _, s in ipairs(stations) do
        if s.state == PowerbankSystem.State.AVAILABLE then
            local dist = math.abs(s.x - playerX)
            if dist < minDist then
                minDist = dist
                nearest = s
            end
        end
    end
    return nearest, nearest and minDist or nil
end

--- 获取柜子状态的中文描述
---@param state string
---@return string label, table color {r,g,b}
function PowerbankSystem.GetStateLabel(state)
    if state == PowerbankSystem.State.AVAILABLE then
        return "有电", { 50, 255, 100 }
    elseif state == PowerbankSystem.State.EMPTY then
        return "空柜", { 255, 200, 50 }
    else
        return "离线", { 150, 150, 150 }
    end
end

-- ====================================================================
-- 交互 API
-- ====================================================================

--- 设置当前玩家所在的建筑（进入室内时调用，防止 tick 影响正在交互的柜子）
---@param buildingIndex number|nil nil=离开室内
function PowerbankSystem.SetCurrentScene(buildingIndex)
    currentSceneBuilding = buildingIndex
end

--- 尝试借用充电宝（扫码成功后调用）
---@param stationId string
---@return boolean success
---@return string message
function PowerbankSystem.TryBorrow(stationId)
    local station = PowerbankSystem.GetById(stationId)
    if not station then
        return false, "找不到该充电宝柜"
    end

    if station.state == PowerbankSystem.State.AVAILABLE then
        -- 借出后柜子变为空柜
        station.state = PowerbankSystem.State.EMPTY
        return true, "借出成功"
    elseif station.state == PowerbankSystem.State.EMPTY then
        return false, "充电宝已被借光，试试其他柜子吧"
    else
        return false, "设备离线，无法使用"
    end
end

--- 检查指定柜子是否可用（扫码前先检查）
---@param stationId string
---@return boolean canUse
---@return string message
function PowerbankSystem.CanUse(stationId)
    local station = PowerbankSystem.GetById(stationId)
    if not station then
        return false, "找不到该充电宝柜"
    end

    if station.state == PowerbankSystem.State.AVAILABLE then
        return true, "可以使用"
    elseif station.state == PowerbankSystem.State.EMPTY then
        return false, "这个柜子里的充电宝已经被借完了\n试试其他地方的充电宝柜吧"
    else
        return false, "设备离线中，无法使用\n请寻找其他充电宝柜"
    end
end

return PowerbankSystem
