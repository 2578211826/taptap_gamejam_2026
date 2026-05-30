-- ====================================================================
-- EventSystem.lua - 事件/弹窗系统
-- ====================================================================

local Config = require("Config")

local EventSystem = {}

-- 广告文案池
local adPool = {
    { title = "恭喜！您获得新人礼包", body = "下载「电量守护」App\n首月会员仅¥29.99" },
    { title = "低电量焦虑解决方案", body = "量身定制优质解决方案\n只要999，你值得拥有" },
    { title = "免押金充电宝", body = "开通尊贵会员\n即享免押金特权" },
    { title = "出生保险限时优惠", body = "保护您不被时间线波动消除\n现在投保立减30%" },
    { title = "跨纪元租房上客优！", body = "一键接单即可获得\n免费优质客源和低价房源" },
    { title = "您的手机在呼唤", body = "检测到电量焦虑\n建议购买「心理按摩Pro」" },
}

-- 充电宝故障文案
local powerBankFailTexts = {
    "充电宝柜显示「网络异常，请稍后再试」",
    "扫码后提示：请先下载「共享电力」App",
    "充电宝弹出......是坏线",
    "显示「可用1个」，但怎么也弹不出来",
    "二维码被一张贴纸盖住了",
    "需要实名认证 + 人脸识别",
}

-- 便利店事件文案
local shopEventTexts = {
    "店员：我们只支持本店App付款",
    "买了Type-C线...但你的手机是Lightning",
    "线太短了，够不到插座",
    "店员推荐了一个138元的套装",
    "收银台提示：请先更新支付安全组件",
}

-- 插座故障文案
local outletFailTexts = {
    "插座没电",
    "这是英标插座，需要转换头",
    "插座被广告屏的线占用了",
    "插上后显示：低功率充电中\n预计17小时充满",
    "插座旁边有人在拍探店视频\n不让你靠近",
}

-- NPC 对话
local npcDialogues = {
    help = {
        "可以啊，给你充一下...（2秒后）不好意思，我老板开始远程监控心率了，得走了。",
        "行吧，不过我也只有3%了...",
    },
    refuse = {
        "不好意思，赶时间",
        "我看起来像充电宝吗？",
        "出生保险断缴了，不方便帮人",
        "（正在直播，完全没听到）",
    },
    steal = {
        "帮你看看什么问题...（拿着手机跑了）",
    },
}

-- 决定是否触发广告
function EventSystem.ShouldShowAd(batteryLevel)
    local stage = EventSystem.GetBatteryStage(batteryLevel)
    if stage then
        return math.random() < stage.adFrequency
    end
    return math.random() < 0.3
end

function EventSystem.GetBatteryStage(batteryLevel)
    for _, stage in ipairs(Config.BatteryStages) do
        if batteryLevel <= stage.threshold then
            return stage
        end
    end
    return nil
end

-- 获取随机广告
function EventSystem.GetRandomAd()
    return adPool[math.random(1, #adPool)]
end

-- 获取充电宝交互结果
function EventSystem.GetPowerBankResult(worldState)
    if worldState.powerBankWorking then
        -- 成功路线，但可能有广告/认证阻碍
        local roll = math.random(1, 3)
        if roll == 1 then
            return "need_scan", "请扫码开启"
        elseif roll == 2 then
            return "need_pay", "押金¥99.99，确认支付？"
        else
            return "success_after_pay", "支付成功，充电宝弹出！"
        end
    else
        local text = powerBankFailTexts[math.random(1, #powerBankFailTexts)]
        return "fail", text
    end
end

-- 获取便利店交互结果
function EventSystem.GetShopResult(worldState)
    if worldState.shopHasCorrectCable then
        local roll = math.random(1, 3)
        if roll == 1 then
            return "buy_cable", "Type-C数据线 ¥25"
        elseif roll == 2 then
            return "buy_cable_and_plug", "数据线+插头套装 ¥45"
        else
            return "need_app_pay", shopEventTexts[1]
        end
    else
        local text = shopEventTexts[math.random(2, #shopEventTexts)]
        return "fail", text
    end
end

-- 获取插座交互结果
function EventSystem.GetOutletResult(worldState, hasCorrectCable)
    if not hasCorrectCable then
        return "no_cable", "你没有数据线，无法充电"
    end
    if worldState.outletWorking then
        return "success", "插上了！手机开始充电..."
    else
        local text = outletFailTexts[math.random(1, #outletFailTexts)]
        return "fail", text
    end
end

-- 获取 NPC 交互结果
function EventSystem.GetNPCResult(worldState)
    if worldState.npcWillSteal then
        -- 被抢（低概率坏结局）
        local text = npcDialogues.steal[1]
        return "steal", text
    elseif worldState.npcWillHelp then
        local text = npcDialogues.help[math.random(1, #npcDialogues.help)]
        return "help", text
    else
        local text = npcDialogues.refuse[math.random(1, #npcDialogues.refuse)]
        return "refuse", text
    end
end

-- 检测是否应该触发卡顿
function EventSystem.ShouldLag(batteryLevel)
    local stage = EventSystem.GetBatteryStage(batteryLevel)
    if stage then
        return math.random() < stage.lagChance
    end
    return false
end

return EventSystem
