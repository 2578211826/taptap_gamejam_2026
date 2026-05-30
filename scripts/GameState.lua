-- ====================================================================
-- GameState.lua - 游戏全局状态管理
-- ====================================================================

local Config = require("Config")

local GameState = {}

function GameState.New()
    local state = {
        -- 游戏阶段
        phase = Config.State.MENU,

        -- 电量（百分比 0-5）
        battery = Config.Battery.Initial,
        batteryDrainRate = Config.Battery.DrainBase,

        -- 手机状态
        phoneOpen = false,
        currentApp = nil, -- "map", "scan", "pay", nil

        -- 玩家
        playerX = 200,
        playerY = 0,
        playerVelY = 0,
        playerOnGround = true,
        facingRight = true,

        -- 相机
        cameraX = 0,

        -- 交互
        nearbyInteractable = nil,

        -- 物品（携带栏，最多5个）
        inventory = {},
        inventoryMax = 5,
        money = 50.00,

        -- 本局随机属性
        phonePort = "typec",       -- 手机端口（每局随机）
        outletType = "2hole",      -- 城市插座类型（每局随机）
        shopStock = nil,           -- 商店货架库存（每局随机生成）

        -- 统计
        stats = {
            phoneOpenCount = 0,
            adWatchCount = 0,
            adMisclickCount = 0,
            payCount = 0,
            rejectCount = 0,
            timeElapsed = 0,
            moneySpent = 0,
        },

        -- 事件队列
        eventQueue = {},
        currentEvent = nil,

        -- 充电进度
        chargeProgress = {
            scannedPowerBank = false,
            paidDeposit = false,
            boughtCable = false,
            cableType = nil, -- "typec", "lightning"
            foundOutlet = false,
            charging = false,
        },

        -- 结局
        ending = nil,
        endingReason = "",

        -- 世界状态（随机生成）
        world = {
            powerBankWorking = false,  -- 将在游戏开始时随机
            outletWorking = false,
            shopHasCorrectCable = false,
            npcWillHelp = false,
            npcWillSteal = false,
        },

        -- 时间
        totalTime = 0,
        lagTimer = 0,
        isLagging = false,
    }
    return state
end

function GameState.Reset(state)
    local newState = GameState.New()
    for k, v in pairs(newState) do
        state[k] = v
    end
end

function GameState.RandomizeWorld(state)
    math.randomseed(os.time())

    -- 随机手机端口
    local ports = { "typec", "lightning", "microusb" }
    state.phonePort = ports[math.random(1, #ports)]

    -- 随机城市插座类型
    local outlets = { "2hole", "3hole" }
    state.outletType = outlets[math.random(1, #outlets)]

    print("[GameState] 本局手机端口: " .. state.phonePort .. ", 插座类型: " .. state.outletType)

    -- 至少一条路线可通关
    local route = math.random(1, 2)
    if route == 1 then
        -- 充电宝路线可行
        state.world.powerBankWorking = true
        state.world.outletWorking = math.random() > 0.5
        state.world.shopHasCorrectCable = math.random() > 0.4
    else
        -- 买线路线可行
        state.world.outletWorking = true
        state.world.shopHasCorrectCable = true
        state.world.powerBankWorking = math.random() > 0.5
    end
    -- NPC 行为
    state.world.npcWillHelp = math.random() > 0.4
    state.world.npcWillSteal = math.random() > 0.85

    -- 生成商店货架库存
    local ItemData = require("ItemData")
    state.shopStock = ItemData.GenerateShopStock(state.phonePort, state.outletType)
end

return GameState
