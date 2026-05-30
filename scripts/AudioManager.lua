-- ====================================================================
-- AudioManager.lua - 音频管理模块
-- ====================================================================
-- 负责 BGM crossfade、SFX cooldown、电量联动
-- ====================================================================

local Config = require("Config")

local AudioManager = {}

-- ====================================================================
-- 内部状态
-- ====================================================================
local scene_ = nil

-- BGM 状态
local bgmNode = nil
local bgmSource = nil         -- 当前 BGM SoundSource
local bgmFadeNode = nil
local bgmFadeSource = nil     -- 淡出中的旧 BGM
local bgmCurrent = nil        -- 当前 BGM 文件名
local bgmFadeTimer = 0
local bgmFadeDuration = 0.5
local bgmFading = false
local bgmTargetGain = 0.35
local bgmStopped = false      -- 是否已手动停止（结局时）

-- BGM 电量联动
local bgmBasePitch = 1.0
local bgmBaseGain = 1.0

-- SFX cooldown 记录
local sfxCooldowns = {}  -- { [filename] = lastPlayTime }

-- 一次性音效标记
local sfxOnceFlags = {}  -- { [filename] = true }

-- 场景节点池（SFX 使用 AutoRemove）
local sfxNodes = {}

-- ====================================================================
-- BGM 配置
-- ====================================================================
local BGM_MAP = {
    [Config.State.MENU]    = { file = "audio/music/bgm_city.ogg",  gain = 0.35, fade = 0.5 },
    [Config.State.PLAYING] = { file = "audio/music/bgm_city.ogg",  gain = 0.35, fade = 0.5 },
    [Config.State.PHONE]   = { file = "audio/music/bgm_phone.ogg", gain = 0.25, fade = 0.5 },
    [Config.State.SHOP]    = { file = "audio/music/bgm_shop.ogg",  gain = 0.30, fade = 0.5 },
    [Config.State.CHASE]   = { file = "audio/music/bgm_chase.ogg", gain = 0.45, fade = 0.0 },  -- 立即切换
    [Config.State.EVENT]   = { file = "audio/music/bgm_slot.ogg",  gain = 0.40, fade = 0.5 },
    -- SCANNING: 保持当前 BGM 不切换
    -- ENDING: 停止 BGM
}

-- ====================================================================
-- 初始化
-- ====================================================================
function AudioManager.Init()
    -- 创建专用音频 Scene（此游戏没有 3D 场景，但 SoundSource 需要 Node）
    scene_ = Scene()
    scene_:CreateComponent("Octree")  -- 最小化组件

    -- BGM 节点
    bgmNode = scene_:CreateChild("BGM")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain = 0

    -- 淡出用的第二个节点
    bgmFadeNode = scene_:CreateChild("BGMFade")
    bgmFadeSource = bgmFadeNode:CreateComponent("SoundSource")
    bgmFadeSource.soundType = "Music"
    bgmFadeSource.gain = 0

    bgmCurrent = nil
    bgmStopped = false
    sfxCooldowns = {}
    sfxOnceFlags = {}
end

-- ====================================================================
-- BGM 控制
-- ====================================================================

--- 根据游戏状态切换 BGM
---@param state string Config.State.*
---@param forceSlot boolean|nil 是否强制使用 slot BGM（EVENT 状态下老虎机）
function AudioManager.SetBGMForState(state, forceSlot)
    if bgmStopped then return end

    -- SCANNING 不切换
    if state == Config.State.SCANNING then return end

    -- ENDING/GAMEOVER 停止
    if state == Config.State.ENDING or state == Config.State.GAMEOVER then
        AudioManager.StopBGM()
        return
    end

    -- EVENT 状态：只有老虎机用 bgm_slot，其他保持
    if state == Config.State.EVENT and not forceSlot then
        return
    end

    local bgmInfo = BGM_MAP[state]
    if not bgmInfo then return end

    -- 已经在播放同一首，不重复切换
    if bgmCurrent == bgmInfo.file then return end

    local newSound = cache:GetResource("Sound", bgmInfo.file)
    if not newSound then
        print("[AudioManager] BGM not found: " .. bgmInfo.file)
        return
    end
    newSound.looped = true

    bgmTargetGain = bgmInfo.gain

    if bgmInfo.fade > 0 and bgmSource:IsPlaying() then
        -- Crossfade: 旧的转到 fadeSource 淡出
        bgmFadeSource:Stop()
        -- 复制当前播放状态到 fade 节点
        if bgmSource:GetSound() then
            bgmFadeSource:Play(bgmSource:GetSound(), bgmSource.frequency, bgmSource.gain)
            bgmFadeSource:Seek(bgmSource.timePosition)
        end
        bgmFading = true
        bgmFadeDuration = bgmInfo.fade
        bgmFadeTimer = 0

        -- 新 BGM 从 0 音量开始
        bgmSource:Play(newSound)
        bgmSource.gain = 0
    else
        -- 立即切换
        bgmSource:Play(newSound)
        bgmSource.gain = bgmTargetGain
        bgmFading = false
    end

    bgmCurrent = bgmInfo.file
end

--- 停止所有 BGM
function AudioManager.StopBGM()
    bgmStopped = true
    if bgmSource then bgmSource:Stop() end
    if bgmFadeSource then bgmFadeSource:Stop() end
    bgmFading = false
    bgmCurrent = nil
end

--- 恢复 BGM 播放能力（新游戏开始时）
function AudioManager.ResetBGM()
    bgmStopped = false
    bgmCurrent = nil
    sfxOnceFlags = {}
end

-- ====================================================================
-- BGM 电量联动
-- ====================================================================

--- 根据电量更新 BGM 的 pitch 和 gain
---@param battery number 当前电量 (0-5)
function AudioManager.UpdateBatteryEffect(battery)
    if bgmStopped or not bgmSource then return end

    local pitch = 1.0
    local gainMult = 1.0

    if battery > 3.0 then
        pitch = 1.0
        gainMult = 1.0
    elseif battery > 2.0 then
        pitch = 1.10
        gainMult = 1.0
    elseif battery > 1.0 then
        pitch = 1.15
        gainMult = 0.5
    elseif battery > 0 then
        pitch = 1.20
        gainMult = 0.15
    else
        AudioManager.StopBGM()
        return
    end

    bgmBasePitch = pitch
    bgmBaseGain = gainMult

    if bgmSource:IsPlaying() then
        bgmSource.frequency = bgmSource:GetSound():GetFrequency() * pitch
        -- gain 在 Update 中会被 crossfade 逻辑覆盖，这里设基础
    end
end

-- ====================================================================
-- SFX 播放
-- ====================================================================

--- 播放音效
---@param file string 音效文件路径 (如 "audio/sfx/sfx_phone_open.ogg")
---@param gain number|nil 音量 (默认 0.7)
---@param cooldown number|nil 最小间隔秒数 (防重叠)
---@param once boolean|nil 是否单局只触发一次
---@return boolean 是否成功播放
function AudioManager.PlaySFX(file, gain, cooldown, once)
    if not scene_ then return false end

    -- 一次性检查
    if once and sfxOnceFlags[file] then
        return false
    end

    -- cooldown 检查
    if cooldown and cooldown > 0 then
        local now = os.clock()
        local lastTime = sfxCooldowns[file] or 0
        if now - lastTime < cooldown then
            return false
        end
        sfxCooldowns[file] = now
    end

    -- 加载音效
    local sound = cache:GetResource("Sound", file)
    if not sound then
        print("[AudioManager] SFX not found: " .. file)
        return false
    end

    -- 创建临时节点播放
    local node = scene_:CreateChild("SFX")
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.autoRemoveMode = REMOVE_NODE
    source.gain = gain or 0.7
    source:Play(sound)

    -- 标记一次性
    if once then
        sfxOnceFlags[file] = true
    end

    return true
end

--- 播放循环音效（返回 SoundSource 供外部停止）
---@param file string
---@param gain number|nil
---@return SoundSource|nil
function AudioManager.PlaySFXLoop(file, gain)
    if not scene_ then return nil end

    local sound = cache:GetResource("Sound", file)
    if not sound then
        print("[AudioManager] SFX loop not found: " .. file)
        return nil
    end
    sound.looped = true

    local node = scene_:CreateChild("SFXLoop")
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = gain or 0.6
    source:Play(sound)

    return source
end

--- 停止循环音效
---@param source SoundSource|nil
function AudioManager.StopSFXLoop(source)
    if source then
        source:Stop()
        -- 节点清理（手动移除）
        if source:GetNode() then
            source:GetNode():Remove()
        end
    end
end

--- 停止所有音效（结局关机时）
function AudioManager.StopAllSFX()
    if not scene_ then return end
    local audio = GetAudio()
    if audio then
        audio:PauseSoundType("Effect")
    end
end

--- 恢复音效
function AudioManager.ResumeAllSFX()
    local audio = GetAudio()
    if audio then
        audio:ResumeSoundType("Effect")
    end
end

-- ====================================================================
-- 每帧更新（crossfade）
-- ====================================================================
function AudioManager.Update(dt)
    if not bgmSource then return end

    -- Crossfade 处理
    if bgmFading then
        bgmFadeTimer = bgmFadeTimer + dt
        local t = math.min(bgmFadeTimer / bgmFadeDuration, 1.0)

        -- 新 BGM 淡入
        bgmSource.gain = bgmTargetGain * bgmBaseGain * t
        -- 旧 BGM 淡出
        if bgmFadeSource then
            bgmFadeSource.gain = bgmTargetGain * (1.0 - t)
        end

        if t >= 1.0 then
            bgmFading = false
            if bgmFadeSource then
                bgmFadeSource:Stop()
            end
        end
    else
        -- 非淡入淡出时，直接应用电量增益
        if not bgmStopped and bgmSource:IsPlaying() then
            bgmSource.gain = bgmTargetGain * bgmBaseGain
        end
    end
end

-- ====================================================================
-- 便捷方法（按文档分类）
-- ====================================================================

-- 手机系统
function AudioManager.PhoneOpen()
    AudioManager.PlaySFX("audio/sfx/sfx_phone_open.ogg", 0.7)
end

function AudioManager.PhoneClose()
    AudioManager.PlaySFX("audio/sfx/sfx_phone_close.ogg", 0.6)
end

function AudioManager.AppTap()
    AudioManager.PlaySFX("audio/sfx/sfx_app_tap.ogg", 0.7)
end

function AudioManager.BtnClick()
    AudioManager.PlaySFX("audio/sfx/sfx_btn_click.ogg", 0.6)
end

function AudioManager.BtnHover()
    AudioManager.PlaySFX("audio/sfx/sfx_btn_hover.ogg", 0.2, 0.1)
end

function AudioManager.AdPopup()
    AudioManager.PlaySFX("audio/sfx/sfx_ad_popup.ogg", 0.8)
end

function AudioManager.AdClose()
    AudioManager.PlaySFX("audio/sfx/sfx_ad_close.ogg", 0.5)
end

function AudioManager.AdMisclick()
    AudioManager.PlaySFX("audio/sfx/sfx_ad_misclick.ogg", 0.7)
end

function AudioManager.BatteryWarning()
    AudioManager.PlaySFX("audio/sfx/sfx_battery_warning.ogg", 1.0, nil, true)
end

function AudioManager.BatteryCritical()
    AudioManager.PlaySFX("audio/sfx/sfx_battery_critical.ogg", 1.0, nil, true)
end

function AudioManager.PhoneShutdown()
    AudioManager.StopBGM()
    AudioManager.StopAllSFX()
    AudioManager.ResumeAllSFX()  -- 恢复以便播放关机音效
    AudioManager.PlaySFX("audio/sfx/sfx_phone_shutdown.ogg", 1.0)
end

function AudioManager.Notification()
    AudioManager.PlaySFX("audio/sfx/sfx_notification.ogg", 0.8)
end

function AudioManager.Typing()
    AudioManager.PlaySFX("audio/sfx/sfx_typing.ogg", 0.5, 0.1)
end

function AudioManager.InputConfirm()
    AudioManager.PlaySFX("audio/sfx/sfx_input_confirm.ogg", 0.7)
end

function AudioManager.LoanApproved()
    AudioManager.PlaySFX("audio/sfx/sfx_loan_approved.ogg", 0.8)
end

function AudioManager.DownloadTick()
    AudioManager.PlaySFX("audio/sfx/sfx_download_tick.ogg", 0.3, 0.3)
end

-- 游戏世界
function AudioManager.Footstep()
    AudioManager.PlaySFX("audio/sfx/sfx_footstep.ogg", 0.4, 0.15)
end

function AudioManager.Jump()
    AudioManager.PlaySFX("audio/sfx/sfx_jump.ogg", 0.6)
end

function AudioManager.Land()
    AudioManager.PlaySFX("audio/sfx/sfx_land.ogg", 0.5)
end

function AudioManager.Interact()
    AudioManager.PlaySFX("audio/sfx/sfx_interact.ogg", 0.6)
end

function AudioManager.DoorEnter()
    AudioManager.PlaySFX("audio/sfx/sfx_door_enter.ogg", 0.7)
end

function AudioManager.DoorExit()
    AudioManager.PlaySFX("audio/sfx/sfx_door_exit.ogg", 0.5)
end

function AudioManager.ItemPickup()
    AudioManager.PlaySFX("audio/sfx/sfx_item_pickup.ogg", 0.6)
end

function AudioManager.ItemPay()
    AudioManager.PlaySFX("audio/sfx/sfx_item_pay.ogg", 0.7)
end

function AudioManager.ChaseAlert()
    AudioManager.PlaySFX("audio/sfx/sfx_chase_alert.ogg", 0.9)
end

function AudioManager.ChaseEscape()
    AudioManager.PlaySFX("audio/sfx/sfx_chase_escape.ogg", 0.7)
end

function AudioManager.ChaseCaught()
    AudioManager.PlaySFX("audio/sfx/sfx_chase_caught.ogg", 0.7)
end

function AudioManager.NpcTalk()
    AudioManager.PlaySFX("audio/sfx/sfx_npc_talk.ogg", 0.5)
end

-- QR 扫描
function AudioManager.ScanFocus()
    AudioManager.PlaySFX("audio/sfx/sfx_scan_focus.ogg", 0.6)
end

function AudioManager.ScanSuccess()
    AudioManager.PlaySFX("audio/sfx/sfx_scan_success.ogg", 0.8)
end

function AudioManager.ScanFail()
    AudioManager.PlaySFX("audio/sfx/sfx_scan_fail.ogg", 0.6)
end

-- 老虎机
function AudioManager.SlotSpin()
    return AudioManager.PlaySFXLoop("audio/sfx/sfx_slot_spin.ogg", 0.6)
end

function AudioManager.SlotStop()
    AudioManager.PlaySFX("audio/sfx/sfx_slot_stop.ogg", 0.7)
end

function AudioManager.SlotWin()
    AudioManager.PlaySFX("audio/sfx/sfx_slot_win.ogg", 0.9)
end

function AudioManager.SlotLose()
    AudioManager.PlaySFX("audio/sfx/sfx_slot_lose.ogg", 0.8)
end

-- 节奏游戏
function AudioManager.RhythmPerfect()
    AudioManager.PlaySFX("audio/sfx/sfx_rhythm_perfect.ogg", 0.8)
end

function AudioManager.RhythmGood()
    AudioManager.PlaySFX("audio/sfx/sfx_rhythm_good.ogg", 0.6)
end

function AudioManager.RhythmMiss()
    AudioManager.PlaySFX("audio/sfx/sfx_rhythm_miss.ogg", 0.5)
end

-- 结局
function AudioManager.EndingChargeSuccess()
    AudioManager.PlaySFX("audio/sfx/sfx_ending_charge_success.ogg", 0.9)
end

function AudioManager.EndingNoBattery()
    AudioManager.PlaySFX("audio/sfx/sfx_ending_no_battery.ogg", 0.8)
end

function AudioManager.EndingStolen()
    AudioManager.PlaySFX("audio/sfx/sfx_ending_stolen.ogg", 0.8)
end

function AudioManager.EndingArrested()
    AudioManager.PlaySFX("audio/sfx/sfx_ending_arrested.ogg", 0.8)
end

return AudioManager
