-- ====================================================================
-- AdSystem.lua - 广告系统（多类型 + 随机池 + 误导性设计）
-- ====================================================================
-- 广告类型：
--   popup   = 弹窗广告（居中卡片，关闭按钮极小/延迟出现）
--   banner  = 横幅广告（顶部/底部条状，点击跳转）
--   fullscreen = 全屏广告（带倒计时跳过按钮）
-- ====================================================================

local AdSystem = {}

-- ====================================================================
-- 广告内容池（与事件无关，随机抽取）
-- ====================================================================
local adContentPool = {
    -- 电量/手机相关
    { title = "恭喜！您获得新人礼包", body = "下载「电量守护」App\n首月会员仅¥29.99", dest = "app_download", destName = "电量守护" },
    { title = "低电量焦虑解决方案", body = "量身定制优质解决方案\n只要999，你值得拥有", dest = "product_page", destName = "焦虑解决方案" },
    { title = "免押金充电宝", body = "开通尊贵会员\n即享免押金特权", dest = "app_download", destName = "共享电力Pro" },
    { title = "您的手机在呼唤", body = "检测到电量焦虑\n建议购买「心理按摩Pro」", dest = "app_download", destName = "心理按摩Pro" },
    -- 保险/金融
    { title = "出生保险限时优惠", body = "保护您不被时间线波动消除\n现在投保立减30%", dest = "product_page", destName = "时空保险" },
    { title = "极速放款 3 秒到账", body = "征信花了？不怕！\n「速得贷」借一万日息仅0.05%", dest = "app_download", destName = "速得贷" },
    -- 地图/出行
    { title = "跨纪元租房上客优！", body = "一键接单即可获得\n免费优质客源和低价房源", dest = "map_redirect", destName = "客优" },
    { title = "附近3.2km有空闲充电桩", body = "打开「即刻出行」导航前往\n新人首单免费", dest = "map_redirect", destName = "即刻出行" },
    -- 游戏/娱乐
    { title = "挂机就能赚钱！", body = "「躺平大亨」0氪也能日入百万\n限时领648礼包", dest = "app_download", destName = "躺平大亨" },
    { title = "你的智商超过99%的人", body = "下载「天才测试」\n证明你比AI聪明", dest = "app_download", destName = "天才测试" },
    -- 购物/生活
    { title = "手机壳买一送三", body = "全场9.9包邮\n限今日23:59前下单", dest = "product_page", destName = "拼夕夕" },
    { title = "充电宝 ¥9.9 限时秒杀", body = "20000mAh 大容量\n仅剩3件，手慢无！", dest = "product_page", destName = "闪购商城" },
}

-- 横幅广告专用（短文案）
local bannerTexts = {
    "🔋 电量守护限时免费 → 立即下载",
    "📱 新用户领100元红包 →",
    "🎮 「躺平大亨」日入百万 → 点击领取",
    "🏠 附近有空闲充电桩 → 导航前往",
    "💰 借一万日息仅3毛 → 极速放款",
    "⚡ 检测到手机老化，点击优化 →",
    "🎁 恭喜获得VIP体验券 → 立即使用",
    "📦 您的快递正在派送 → 查看详情",
}

-- 误导性按钮文案
local misleadingAcceptTexts = {
    "立即前往",
    "马上领取",
    "立即下载",
    "抢先体验",
    "一键开通",
    "火速围观",
    "我要变强",
}

local misleadingRejectTexts = {
    "残忍拒绝",
    "放弃优惠",
    "我不需要",
    "狠心离开",
    "再想想",
    "以后再说",
    "我是穷人",
}

-- ====================================================================
-- 广告状态
-- ====================================================================
local currentAd = nil       -- 当前正在展示的广告 {type, content, ...}
local adVisible = false
local bannerVisible = false
local bannerContent = nil
local fullscreenTimer = 0   -- 全屏广告倒计时（秒）
local fullscreenSkipDelay = 3  -- 跳过按钮出现延迟
local closeButtonDelay = 1.5   -- popup关闭按钮延迟出现
local closeButtonTimer = 0

-- ====================================================================
-- API
-- ====================================================================

--- 随机选一条广告内容
function AdSystem.GetRandomContent()
    return adContentPool[math.random(1, #adContentPool)]
end

--- 随机选一种广告类型（基于电量影响概率）
--- 电量越低，全屏广告概率越高
function AdSystem.GetRandomType(battery)
    local roll = math.random()
    if battery <= 1.5 then
        -- 极低电量：全屏60% 弹窗30% 横幅10%
        if roll < 0.6 then return "fullscreen"
        elseif roll < 0.9 then return "popup"
        else return "banner" end
    elseif battery <= 3.0 then
        -- 中低电量：全屏30% 弹窗40% 横幅30%
        if roll < 0.3 then return "fullscreen"
        elseif roll < 0.7 then return "popup"
        else return "banner" end
    else
        -- 正常：全屏10% 弹窗40% 横幅50%
        if roll < 0.1 then return "fullscreen"
        elseif roll < 0.5 then return "popup"
        else return "banner" end
    end
end

--- 获取误导性"接受"按钮文案
function AdSystem.GetAcceptText()
    return misleadingAcceptTexts[math.random(1, #misleadingAcceptTexts)]
end

--- 获取误导性"拒绝"按钮文案
function AdSystem.GetRejectText()
    return misleadingRejectTexts[math.random(1, #misleadingRejectTexts)]
end

--- 获取随机横幅文案
function AdSystem.GetRandomBanner()
    return bannerTexts[math.random(1, #bannerTexts)]
end

--- 触发一次广告（根据电量决定类型）
--- @param battery number 当前电量
--- @return table|nil 广告数据 {type, content, acceptText, rejectText}
function AdSystem.TriggerAd(battery)
    local adType = AdSystem.GetRandomType(battery)
    local content = AdSystem.GetRandomContent()
    local ad = {
        type = adType,
        content = content,
        acceptText = AdSystem.GetAcceptText(),
        rejectText = AdSystem.GetRejectText(),
        bannerText = AdSystem.GetRandomBanner(),
    }
    currentAd = ad
    adVisible = true
    closeButtonTimer = 0
    fullscreenTimer = 5  -- 全屏广告5秒

    return ad
end

--- 关闭当前广告
function AdSystem.DismissAd()
    adVisible = false
    currentAd = nil
end

--- 关闭横幅
function AdSystem.DismissBanner()
    bannerVisible = false
    bannerContent = nil
end

--- 显示横幅广告
function AdSystem.ShowBanner()
    bannerVisible = true
    bannerContent = AdSystem.GetRandomBanner()
end

--- 获取当前广告数据
function AdSystem.GetCurrentAd()
    return currentAd
end

--- 广告是否可见
function AdSystem.IsVisible()
    return adVisible
end

--- 横幅是否可见
function AdSystem.IsBannerVisible()
    return bannerVisible
end

function AdSystem.GetBannerContent()
    return bannerContent
end

--- 更新广告计时器（每帧调用）
--- @return string|nil 事件 "skip_available" / "auto_close" / nil
function AdSystem.Update(dt)
    if not adVisible or not currentAd then return nil end

    -- popup：关闭按钮延迟出现
    if currentAd.type == "popup" then
        closeButtonTimer = closeButtonTimer + dt
    end

    -- fullscreen：倒计时
    if currentAd.type == "fullscreen" then
        closeButtonTimer = closeButtonTimer + dt
        fullscreenTimer = fullscreenTimer - dt
        if fullscreenTimer <= 0 then
            -- 全屏广告自动结束（但不自动关闭，强制看完后显示关闭按钮）
            fullscreenTimer = 0
        end
    end

    return nil
end

--- popup关闭按钮是否可见（延迟出现）
function AdSystem.IsCloseButtonVisible()
    if not currentAd then return false end
    if currentAd.type == "popup" then
        return closeButtonTimer >= closeButtonDelay
    end
    return true
end

--- fullscreen跳过按钮是否可见
function AdSystem.IsSkipButtonVisible()
    if not currentAd or currentAd.type ~= "fullscreen" then return false end
    return closeButtonTimer >= fullscreenSkipDelay
end

--- 获取全屏广告剩余秒数
function AdSystem.GetFullscreenRemaining()
    return math.max(0, math.ceil(fullscreenTimer))
end

--- 获取跳过按钮出现倒计时
function AdSystem.GetSkipButtonCountdown()
    local remaining = fullscreenSkipDelay - closeButtonTimer
    return math.max(0, math.ceil(remaining))
end

--- 决定是否触发广告（基于电量阶段）
function AdSystem.ShouldTrigger(battery)
    local freq = 0.3
    if battery <= 1.0 then freq = 0.9
    elseif battery <= 2.0 then freq = 0.7
    elseif battery <= 3.0 then freq = 0.5
    elseif battery <= 4.0 then freq = 0.3
    end
    return math.random() < freq
end

return AdSystem
