-- ====================================================================
-- LoanApp.lua - 贷款功能模块（完整流程）
-- ====================================================================
-- 流程：
--   1. 点击贷款 → 弹广告 → 关掉
--   2. 输入手机号（正确=HUD显示的号码）→ SMS横幅（含验证码）
--   3. 输入验证码 → 再弹广告 → 关掉
--   4. 人脸识别音游（8个节拍，打分，中途弹广告）
--   5. 通过 → 选择贷款金额 → 到账
-- ====================================================================

local DiagLog = require("DiagLog")

local LoanApp = {}

-- ====================================================================
-- 常量
-- ====================================================================
local PHONE_NUMBER = "13812346752"  -- 玩家手机号（完整）
local PHONE_DISPLAY = "138****6752" -- HUD显示（脱敏）
local VERIFY_CODE = "852917"        -- 正确的验证码
local LOAN_LIMIT = 400              -- 贷款额度上限
local LOAN_RATE = "648%"            -- 月利率（荒诞）
local RESEND_COOLDOWN = 59          -- 重新发送冷却（秒）

-- 人脸识别动作
local FACE_ACTIONS = {
    { key = "1", name = "眨眼", icon = "👁" },
    { key = "2", name = "张嘴", icon = "👄" },
    { key = "3", name = "摇头", icon = "↔" },
    { key = "4", name = "点头", icon = "↕" },
}

-- 判定窗口（秒）
local PERFECT_WINDOW = 0.10
local GREAT_WINDOW = 0.20
local GOOD_WINDOW = 0.35

-- 分值
local SCORE_PERFECT = 4
local SCORE_GREAT = 2
local SCORE_GOOD = 1
local SCORE_MISS = 0

-- 通过分数线
local PASS_SCORE = 16

-- ====================================================================
-- 状态机
-- ====================================================================
-- "idle"          未启动
-- "ad_before"     点击贷款后第一个广告
-- "input_phone"   输入手机号
-- "sms_sent"      短信已发送，输入验证码
-- "ad_after_code" 验证码通过后的广告
-- "face_game"     人脸识别音游
-- "face_result"   人脸结果展示
-- "loan_input"    输入贷款金额
-- "loan_done"     贷款完成
-- "failed"        人脸识别失败
local state = "idle"

-- 手机号/验证码输入
local phoneInput = ""
local codeInput = ""
local resendTimer = 0
local canResend = true
local errorMsg = ""
local errorTimer = 0

-- SMS 通知横幅
local smsVisible = false
local smsTimer = 0
local smsSlideY = -80   -- 从上方滑入

-- 人脸识别音游
local faceBeats = {}         -- { {action, timing, result, resultTimer} }
local faceTimer = 0          -- 游戏计时器
local faceDuration = 8.0     -- 时间轴总长（秒）
local faceScore = 0
local faceCombo = 0
local faceMaxCombo = 0
local facePhase = "ready"    -- "ready" / "playing" / "paused_ad" / "done"
local faceLastJudge = nil    -- 最近一次判定 "Perfect"/"Great"/"Good"/"未识别"
local faceLastJudgeTimer = 0
local faceAdShown = 0        -- 已弹出的广告次数
local faceAdTimes = {}       -- 预设的广告弹出时刻
local faceAdPending = false  -- 广告正在展示中（暂停游戏）

-- 贷款金额输入
local loanInput = ""
local loanSuccess = false

-- 广告模拟定时器（自包含，不依赖外部UI系统）
local adTimer = 0            -- 广告剩余时间（秒）
local adDismissable = false  -- 是否可关闭
local AD_SHOW_DURATION = 2.5 -- 广告强制观看时间（秒）
local AD_DISMISS_HINT = 1.5  -- 经过多久后显示关闭提示

-- 回调
local onLoanComplete = nil   -- function(amount) 贷款到账
local onShowAd = nil         -- function() 广告需要显示时调用（通知 PhoneUI 显示广告）
local onHideAd = nil         -- function() 广告结束时调用

-- ====================================================================
-- 初始化
-- ====================================================================

--- @param callbacks table {onLoanComplete, onShowAd, onHideAd}
function LoanApp.Init(callbacks)
    if callbacks then
        onLoanComplete = callbacks.onLoanComplete
        onShowAd = callbacks.onShowAd
        onHideAd = callbacks.onHideAd
    end
end

--- 获取手机号（HUD脱敏显示）
function LoanApp.GetPhoneDisplay()
    return PHONE_DISPLAY
end

--- 获取完整手机号（验证用）
function LoanApp.GetFullPhone()
    return PHONE_NUMBER
end

-- ====================================================================
-- 流程控制
-- ====================================================================

--- 启动贷款流程
function LoanApp.Start()
    DiagLog.Log("贷款", "[触发] LoanApp.Start() 被调用")
    state = "ad_before"
    phoneInput = ""
    codeInput = ""
    resendTimer = 0
    canResend = true
    errorMsg = ""
    errorTimer = 0
    smsVisible = false
    loanInput = ""
    loanSuccess = false
    faceScore = 0
    faceCombo = 0
    faceMaxCombo = 0
    faceAdShown = 0
    faceAdPending = false
    -- 启动内置广告定时器
    adTimer = AD_SHOW_DURATION
    adDismissable = false
    -- 通知外部显示广告
    if onShowAd then onShowAd() end
    DiagLog.Log("贷款", "[完成] Start → state=ad_before, adTimer=" .. AD_SHOW_DURATION)
end

function LoanApp.GetState()
    return state
end

function LoanApp.IsActive()
    return state ~= "idle"
end

function LoanApp.Close()
    DiagLog.Log("贷款", "[触发] LoanApp.Close() 被调用, 原state=" .. state)
    local wasAd = (state == "ad_before" or state == "ad_after_code" or faceAdPending)
    state = "idle"
    smsVisible = false
    faceAdPending = false
    adTimer = 0
    adDismissable = false
    -- 如果正在显示广告，通知隐藏
    if wasAd and onHideAd then onHideAd() end
    DiagLog.Log("贷款", "[完成] Close → state=idle")
end

--- 关闭当前广告（PhoneUI ad_closed 回调触发）
function LoanApp.DismissAd()
    DiagLog.Log("贷款", "[触发] DismissAd() state=" .. state .. " adDismissable=" .. tostring(adDismissable) .. " faceAdPending=" .. tostring(faceAdPending))
    -- 注意：adDismissable 不再用来拦截（PhoneUI 的关闭按钮已经做了延迟显示）
    adTimer = 0
    adDismissable = false
    if onHideAd then onHideAd() end
    if state == "ad_before" then
        state = "input_phone"
        DiagLog.Log("贷款", "[完成] DismissAd → state=input_phone")
    elseif state == "ad_after_code" then
        state = "face_game"
        LoanApp.InitFaceGame()
        DiagLog.Log("贷款", "[完成] DismissAd → state=face_game, 初始化音游")
    elseif faceAdPending then
        LoanApp.ResumeFaceGame()
        DiagLog.Log("贷款", "[完成] DismissAd → 恢复人脸音游")
    end
    return true
end

--- 广告是否正在显示（用于渲染判断）
function LoanApp.IsAdShowing()
    return (state == "ad_before" or state == "ad_after_code" or faceAdPending) and adTimer > 0
end

--- 广告是否可关闭
function LoanApp.IsAdDismissable()
    return adDismissable
end

--- 获取广告剩余时间
function LoanApp.GetAdTimer()
    return adTimer
end

-- ====================================================================
-- 输入处理
-- ====================================================================

--- 处理数字键输入
function LoanApp.OnDigitInput(digit)
    if state == "input_phone" then
        if #phoneInput < 11 then
            phoneInput = phoneInput .. digit
        end
    elseif state == "sms_sent" then
        if #codeInput < 6 then
            codeInput = codeInput .. digit
        end
    elseif state == "face_game" and facePhase == "playing" then
        LoanApp.JudgeFaceInput(digit)
    elseif state == "loan_input" then
        if #loanInput < 3 then  -- 最多3位数（最大400）
            loanInput = loanInput .. digit
        end
    end
end

--- 退格
function LoanApp.OnBackspace()
    if state == "input_phone" then
        phoneInput = string.sub(phoneInput, 1, math.max(0, #phoneInput - 1))
    elseif state == "sms_sent" then
        codeInput = string.sub(codeInput, 1, math.max(0, #codeInput - 1))
    elseif state == "loan_input" then
        loanInput = string.sub(loanInput, 1, math.max(0, #loanInput - 1))
    end
end

--- 确认（Enter）
function LoanApp.OnConfirm()
    DiagLog.Log("贷款", "[触发] OnConfirm() state=" .. state .. " facePhase=" .. tostring(facePhase))
    if state == "input_phone" then
        LoanApp.SubmitPhone()
    elseif state == "sms_sent" then
        LoanApp.SubmitCode()
    elseif state == "loan_input" then
        LoanApp.SubmitLoan()
    elseif state == "face_game" and facePhase == "ready" then
        LoanApp.BeginFaceGame()
        DiagLog.Log("贷款", "[完成] OnConfirm → 开始人脸音游")
    elseif state == "face_result" then
        -- 验证通过 → 输入贷款金额
        state = "loan_input"
        loanInput = ""
        errorMsg = ""
        DiagLog.Log("贷款", "[完成] OnConfirm → state=loan_input")
    elseif state == "failed" then
        -- 失败后按Enter重试
        LoanApp.RetryFace()
        DiagLog.Log("贷款", "[完成] OnConfirm → 重试人脸识别")
    elseif state == "loan_done" then
        -- 完成后关闭
        LoanApp.Close()
    else
        DiagLog.Log("贷款", "[忽略] OnConfirm 无匹配分支 state=" .. state)
    end
end

-- ====================================================================
-- 手机号验证
-- ====================================================================

function LoanApp.SubmitPhone()
    DiagLog.Log("贷款", "[触发] SubmitPhone() 输入=" .. phoneInput .. " 长度=" .. #phoneInput)
    if #phoneInput ~= 11 then
        errorMsg = "请输入11位手机号"
        errorTimer = 2.5
        DiagLog.Log("贷款", "[拦截] 手机号位数不足")
        return
    end
    -- 判断是否正确（匹配完整号码）
    if phoneInput == PHONE_NUMBER then
        state = "sms_sent"
        resendTimer = RESEND_COOLDOWN
        canResend = false
        codeInput = ""
        errorMsg = ""
        -- 触发SMS通知横幅
        smsVisible = true
        smsTimer = 5.0
        smsSlideY = -80
        DiagLog.Log("贷款", "[完成] SubmitPhone → state=sms_sent, SMS横幅已触发")
    else
        errorMsg = "手机号不存在"
        errorTimer = 2.5
        DiagLog.Log("贷款", "[失败] 手机号不匹配")
    end
end

function LoanApp.ResendCode()
    if canResend then
        resendTimer = RESEND_COOLDOWN
        canResend = false
        smsVisible = true
        smsTimer = 5.0
        smsSlideY = -80
    end
end

-- ====================================================================
-- 验证码
-- ====================================================================

function LoanApp.SubmitCode()
    DiagLog.Log("贷款", "[触发] SubmitCode() 输入=" .. codeInput .. " 长度=" .. #codeInput)
    if #codeInput ~= 6 then
        errorMsg = "请输入6位验证码"
        errorTimer = 2.5
        DiagLog.Log("贷款", "[拦截] 验证码位数不足")
        return
    end
    if codeInput == VERIFY_CODE then
        -- 正确 → 弹内置广告 → 人脸识别
        state = "ad_after_code"
        errorMsg = ""
        adTimer = AD_SHOW_DURATION
        adDismissable = false
        if onShowAd then onShowAd() end
        DiagLog.Log("贷款", "[完成] SubmitCode → state=ad_after_code, adTimer=" .. AD_SHOW_DURATION)
    else
        errorMsg = "验证码错误"
        errorTimer = 2.5
        codeInput = ""
        DiagLog.Log("贷款", "[失败] 验证码不匹配")
    end
end

-- ====================================================================
-- 人脸识别音游
-- ====================================================================

function LoanApp.InitFaceGame()
    facePhase = "ready"
    faceTimer = 0
    faceScore = 0
    faceCombo = 0
    faceMaxCombo = 0
    faceLastJudge = nil
    faceLastJudgeTimer = 0
    faceAdShown = 0
    faceAdPending = false

    -- 生成8个节拍（均匀分布在时间轴上）
    faceBeats = {}
    local spacing = faceDuration / 9  -- 9个间隔，8个点
    for i = 1, 8 do
        local action = FACE_ACTIONS[math.random(1, #FACE_ACTIONS)]
        table.insert(faceBeats, {
            action = action,
            timing = spacing * i,
            result = nil,       -- "Perfect"/"Great"/"Good"/"未识别"
            resultTimer = 0,
            judged = false,
        })
    end

    -- 预设广告弹出时刻（在第3和第6个节拍之间）
    faceAdTimes = {}
    if math.random() < 0.8 then
        table.insert(faceAdTimes, spacing * 2.5)  -- 第一次广告
    end
    if math.random() < 0.6 then
        table.insert(faceAdTimes, spacing * 5.5)  -- 第二次广告
    end
end

function LoanApp.BeginFaceGame()
    facePhase = "playing"
    faceTimer = 0
end

--- 人脸识别中途广告关闭后恢复
function LoanApp.ResumeFaceGame()
    faceAdPending = false
    facePhase = "playing"
end

--- 音游按键判定
function LoanApp.JudgeFaceInput(digit)
    if facePhase ~= "playing" or faceAdPending then return end

    -- 找最近的未判定节拍，且按键匹配
    local bestIdx = nil
    local bestDist = GOOD_WINDOW + 0.01  -- 超出good窗口就不算

    for i, beat in ipairs(faceBeats) do
        if not beat.judged and beat.action.key == digit then
            local dist = math.abs(faceTimer - beat.timing)
            if dist < bestDist then
                bestDist = dist
                bestIdx = i
            end
        end
    end

    if bestIdx then
        local beat = faceBeats[bestIdx]
        beat.judged = true
        local dist = math.abs(faceTimer - beat.timing)

        if dist <= PERFECT_WINDOW then
            beat.result = "Perfect"
            faceScore = faceScore + SCORE_PERFECT
            faceCombo = faceCombo + 1
        elseif dist <= GREAT_WINDOW then
            beat.result = "Great"
            faceScore = faceScore + SCORE_GREAT
            faceCombo = faceCombo + 1
        elseif dist <= GOOD_WINDOW then
            beat.result = "Good"
            faceScore = faceScore + SCORE_GOOD
            faceCombo = faceCombo + 1
        end

        beat.resultTimer = 1.0
        faceLastJudge = beat.result
        faceLastJudgeTimer = 1.0
        if faceCombo > faceMaxCombo then faceMaxCombo = faceCombo end
    else
        -- 按错键（没有匹配的节拍）→ 断combo
        faceCombo = 0
        faceLastJudge = "Miss"
        faceLastJudgeTimer = 0.8
    end
end

function LoanApp.RetryFace()
    state = "face_game"
    LoanApp.InitFaceGame()
end

-- ====================================================================
-- 贷款金额输入
-- ====================================================================

function LoanApp.SubmitLoan()
    DiagLog.Log("贷款", "[触发] SubmitLoan() 输入=" .. loanInput)
    local amount = tonumber(loanInput)
    if not amount or amount <= 0 then
        errorMsg = "请输入有效金额"
        errorTimer = 2.0
        DiagLog.Log("贷款", "[拦截] 金额无效")
        return
    end
    if amount > LOAN_LIMIT then
        errorMsg = "超出额度上限(¥" .. LOAN_LIMIT .. ")"
        errorTimer = 2.5
        DiagLog.Log("贷款", "[拦截] 超出额度 " .. amount .. ">" .. LOAN_LIMIT)
        return
    end
    -- 贷款成功！
    loanSuccess = true
    state = "loan_done"
    DiagLog.Log("贷款", "[完成] SubmitLoan → state=loan_done, 金额=" .. amount)
    if onLoanComplete then
        onLoanComplete(amount)
    end
end

-- ====================================================================
-- 每帧更新
-- ====================================================================

function LoanApp.Update(dt)
    -- 广告定时器（自包含广告逻辑）
    if (state == "ad_before" or state == "ad_after_code" or faceAdPending) and adTimer > 0 then
        local wasDismissable = adDismissable
        adTimer = adTimer - dt
        if adTimer <= AD_SHOW_DURATION - AD_DISMISS_HINT then
            adDismissable = true
        end
        if adDismissable and not wasDismissable then
            DiagLog.Log("贷款", "[运行] 广告可关闭了 state=" .. state .. " 剩余=" .. string.format("%.1f", adTimer) .. "s")
        end
    end

    -- 错误提示计时
    if errorTimer > 0 then
        errorTimer = errorTimer - dt
        if errorTimer <= 0 then errorMsg = "" end
    end

    -- 重新发送倒计时
    if state == "sms_sent" and resendTimer > 0 then
        resendTimer = resendTimer - dt
        if resendTimer <= 0 then
            resendTimer = 0
            canResend = true
        end
    end

    -- SMS横幅动画
    if smsVisible then
        smsSlideY = smsSlideY + dt * 300
        if smsSlideY > 4 then smsSlideY = 4 end
        smsTimer = smsTimer - dt
        if smsTimer <= 0 then smsVisible = false end
    end

    -- 判定结果显示计时
    if faceLastJudgeTimer > 0 then
        faceLastJudgeTimer = faceLastJudgeTimer - dt
        if faceLastJudgeTimer <= 0 then faceLastJudge = nil end
    end
    for _, beat in ipairs(faceBeats) do
        if beat.resultTimer > 0 then
            beat.resultTimer = beat.resultTimer - dt
        end
    end

    -- 人脸识别音游更新
    if state == "face_game" and facePhase == "playing" and not faceAdPending then
        faceTimer = faceTimer + dt

        -- 检查是否该弹广告
        for _, adTime in ipairs(faceAdTimes) do
            if faceAdShown < #faceAdTimes and faceTimer >= adTime and not faceAdPending then
                -- 只在还没弹过的时间点弹
                local alreadyShown = false
                for j = 1, faceAdShown do
                    if math.abs(faceAdTimes[j] - adTime) < 0.1 then
                        alreadyShown = true
                        break
                    end
                end
                if not alreadyShown then
                    faceAdShown = faceAdShown + 1
                    faceAdPending = true
                    facePhase = "paused_ad"
                    adTimer = AD_SHOW_DURATION
                    adDismissable = false
                    if onShowAd then onShowAd() end
                    break
                end
            end
        end

        -- 检查漏掉的节拍（超过判定窗口就标记为未识别）
        for _, beat in ipairs(faceBeats) do
            if not beat.judged and faceTimer > beat.timing + GOOD_WINDOW then
                beat.judged = true
                beat.result = "未识别"
                beat.resultTimer = 1.0
                faceCombo = 0
                faceLastJudge = "未识别"
                faceLastJudgeTimer = 0.8
            end
        end

        -- 游戏结束
        if faceTimer >= faceDuration then
            facePhase = "done"
            if faceScore >= PASS_SCORE then
                state = "face_result"
            else
                state = "failed"
            end
        end
    end
end

-- ====================================================================
-- 数据接口（渲染用）
-- ====================================================================

function LoanApp.GetPhoneInput() return phoneInput end
function LoanApp.GetCodeInput() return codeInput end
function LoanApp.GetErrorMsg() return errorMsg end
function LoanApp.GetResendTimer() return math.ceil(math.max(0, resendTimer)) end
function LoanApp.CanResend() return canResend end
function LoanApp.GetVerifyCode() return VERIFY_CODE end
function LoanApp.GetLoanLimit() return LOAN_LIMIT end
function LoanApp.GetLoanRate() return LOAN_RATE end
function LoanApp.GetLoanInput() return loanInput end
function LoanApp.IsLoanSuccess() return loanSuccess end

-- SMS横幅
function LoanApp.IsSmsVisible() return smsVisible end
function LoanApp.GetSmsSlideY() return smsSlideY end

-- 人脸音游
function LoanApp.GetFacePhase() return facePhase end
function LoanApp.GetFaceBeats() return faceBeats end
function LoanApp.GetFaceTimer() return faceTimer end
function LoanApp.GetFaceDuration() return faceDuration end
function LoanApp.GetFaceScore() return faceScore end
function LoanApp.GetFaceCombo() return faceCombo end
function LoanApp.GetFaceMaxCombo() return faceMaxCombo end
function LoanApp.GetFaceLastJudge() return faceLastJudge end
function LoanApp.GetFaceLastJudgeTimer() return faceLastJudgeTimer end
function LoanApp.IsAdPending() return faceAdPending end
function LoanApp.GetPassScore() return PASS_SCORE end

return LoanApp
