-- ====================================================================
-- Config.lua - 游戏全局配置
-- ====================================================================

local Config = {}

-- 游戏标题
Config.Title = "完蛋了，手机没电了"

-- 电量系统
Config.Battery = {
    Initial = 5.0,         -- 初始电量百分比
    DrainBase = 0.08,      -- 每秒基础耗电（手机关闭时）
    DrainScreenOn = 0.25,  -- 手机屏幕打开时额外耗电
    DrainApp = 0.15,       -- 使用 App 时额外耗电
    DrainAd = 0.3,         -- 播放广告时额外耗电
    CostOpenPhone = 0.05,  -- 打开手机消耗
    CostOpenApp = 0.08,    -- 打开 App 消耗
}

-- 电量阶段效果
Config.BatteryStages = {
    { threshold = 4.0, lagChance = 0.0,  adFrequency = 0.3 },
    { threshold = 3.0, lagChance = 0.15, adFrequency = 0.5 },
    { threshold = 2.0, lagChance = 0.3,  adFrequency = 0.7 },
    { threshold = 1.0, lagChance = 0.5,  adFrequency = 0.9 },
}

-- 角色
Config.Player = {
    Speed = 250,
    JumpStrength = 500,
    Width = 30,
    Height = 50,
    GroundY = 0, -- 将在运行时根据屏幕设置
}

-- 城市场景
Config.World = {
    TileSize = 80,
    GroundHeight = 100,
    BuildingMinHeight = 150,
    BuildingMaxHeight = 350,
}

-- 交互距离
Config.InteractDistance = 60

-- 充电路线
Config.ChargeRoutes = {
    PowerBank = "powerbank",  -- 共享充电宝
    BuyLine = "buyline",      -- 买线插座
}

-- 游戏状态枚举
Config.State = {
    MENU = "menu",
    PLAYING = "playing",
    PHONE = "phone",
    SCANNING = "scanning",  -- 扫码小游戏进行中
    SHOP = "shop",          -- 商店室内场景
    CHASE = "chase",        -- 店主追击中
    EVENT = "event",        -- 广告/弹窗事件
    ENDING = "ending",
    GAMEOVER = "gameover",
}

-- 追击系统
Config.Chase = {
    ShopkeeperSpeed = 220,   -- 店主速度（略慢于玩家）
    PlayerSpeedBoost = 280,  -- 追击时玩家加速
    GiveUpDistance = 5,      -- 跑过几栋楼后放弃（用建筑数衡量）
    CatchDistance = 30,      -- 被抓住的距离
}

-- 结局类型
Config.Ending = {
    WIN = "win",
    NO_BATTERY = "no_battery",
    STOLEN = "stolen",
    DEAD = "dead",
    ARRESTED = "arrested",
}

return Config
