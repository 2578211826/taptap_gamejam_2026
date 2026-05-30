-- ====================================================================
-- DiagLog.lua - 诊断日志系统
-- ====================================================================
-- 环形缓冲区存储最近N条日志，右键双击电量条触发显示/复制
-- 日志格式：[时间戳] [分类] 中文描述
-- ====================================================================

local DiagLog = {}

-- 配置
local MAX_ENTRIES = 120        -- 最多保留条数
local DISPLAY_LINES = 35       -- 浮层显示行数

-- 状态
local entries = {}             -- 环形日志缓冲
local entryIndex = 0           -- 当前写入索引
local totalCount = 0           -- 总写入计数
local visible = false          -- 浮层是否显示
local startTime = 0            -- 游戏启动时间戳

-- 右键双击检测
local rightClickTimes = {}     -- 记录最近的右键时间
local DOUBLE_CLICK_WINDOW = 0.6 -- 双击判定窗口（秒）

-- ====================================================================
-- 核心 API
-- ====================================================================

function DiagLog.Init()
    entries = {}
    entryIndex = 0
    totalCount = 0
    visible = false
    startTime = os.clock()
    rightClickTimes = {}
    DiagLog.Log("系统", "诊断日志系统启动")
end

--- 写入一条日志
--- @param category string 分类（如"贷款"、"事件"、"渲染"、"输入"）
--- @param msg string 中文描述
function DiagLog.Log(category, msg)
    totalCount = totalCount + 1
    entryIndex = ((entryIndex) % MAX_ENTRIES) + 1
    local elapsed = os.clock() - startTime
    local timestamp = string.format("%.1f", elapsed)
    entries[entryIndex] = "[" .. timestamp .. "s][" .. category .. "] " .. msg
    -- 同时输出到控制台方便开发时查看
    print("[诊断] " .. entries[entryIndex])
end

--- 带环境信息的日志（自动附加电量/状态）
--- @param category string
--- @param msg string
--- @param env table|nil {battery, phase, loanState, ...}
function DiagLog.LogWithEnv(category, msg, env)
    local suffix = ""
    if env then
        local parts = {}
        if env.battery then table.insert(parts, "电量=" .. string.format("%.1f%%", env.battery)) end
        if env.phase then table.insert(parts, "阶段=" .. env.phase) end
        if env.loanState then table.insert(parts, "贷款=" .. env.loanState) end
        if env.phoneOpen ~= nil then table.insert(parts, "手机=" .. (env.phoneOpen and "开" or "关")) end
        if #parts > 0 then
            suffix = " | " .. table.concat(parts, ", ")
        end
    end
    DiagLog.Log(category, msg .. suffix)
end

--- 处理鼠标右键按下事件（检测双击）
--- @param x number 鼠标逻辑坐标X
--- @param y number 鼠标逻辑坐标Y
--- @param batteryBarRect table|nil {x, y, w, h} 电量条的屏幕矩形
--- @return boolean 是否触发了日志面板
function DiagLog.OnRightClick(x, y, batteryBarRect)
    -- 检查是否点在电量条区域
    if batteryBarRect then
        local bx, by, bw, bh = batteryBarRect.x, batteryBarRect.y, batteryBarRect.w, batteryBarRect.h
        if x < bx or x > bx + bw or y < by or y > bx + bh then
            return false  -- 不在电量条区域
        end
    end

    local now = os.clock()
    table.insert(rightClickTimes, now)

    -- 只保留最近2次
    while #rightClickTimes > 2 do
        table.remove(rightClickTimes, 1)
    end

    -- 判断双击
    if #rightClickTimes >= 2 then
        local interval = rightClickTimes[#rightClickTimes] - rightClickTimes[#rightClickTimes - 1]
        if interval <= DOUBLE_CLICK_WINDOW then
            visible = not visible
            rightClickTimes = {}
            DiagLog.Log("系统", visible and "日志面板已打开" or "日志面板已关闭")
            return true
        end
    end
    return false
end

--- 日志浮层是否可见
function DiagLog.IsVisible()
    return visible
end

--- 关闭浮层
function DiagLog.Hide()
    visible = false
end

--- 获取所有日志文本（用于复制）
function DiagLog.GetAllText()
    local lines = {}
    local count = math.min(totalCount, MAX_ENTRIES)
    -- 从最旧到最新排列
    local startIdx
    if totalCount <= MAX_ENTRIES then
        startIdx = 1
    else
        startIdx = (entryIndex % MAX_ENTRIES) + 1
    end
    for i = 0, count - 1 do
        local idx = ((startIdx - 1 + i) % MAX_ENTRIES) + 1
        if entries[idx] then
            table.insert(lines, entries[idx])
        end
    end
    return table.concat(lines, "\n")
end

--- 获取最近N条日志（用于浮层显示）
function DiagLog.GetRecentLines(n)
    n = n or DISPLAY_LINES
    local lines = {}
    local count = math.min(totalCount, MAX_ENTRIES)
    local displayCount = math.min(n, count)
    -- 从最新往回取
    for i = 0, displayCount - 1 do
        local idx = ((entryIndex - 1 - i) % MAX_ENTRIES) + 1
        if entries[idx] then
            table.insert(lines, 1, entries[idx])
        end
    end
    return lines
end

--- 设置实时状态获取回调（避免DiagLog依赖game state）
--- @param fn function 返回 {battery, phase, loanState, phoneOpen, adShowing, ...}
local statusGetter = nil
function DiagLog.SetStatusGetter(fn)
    statusGetter = fn
end

--- 渲染日志浮层（NanoVG）- 大面板版
function DiagLog.Render(vg, sw, sh)
    if not visible then return end

    local lines = DiagLog.GetRecentLines()
    local lineH = 16
    local padding = 12
    local panelW = math.min(sw - 10, 620)
    local statusH = 60  -- 状态栏高度
    local panelH = math.min(sh - 20, #lines * lineH + padding * 2 + 30 + statusH)
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2

    -- 半透明背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(5, 8, 15, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(0, 255, 100, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题栏
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0, 255, 100, 255))
    nvgText(vg, sw / 2, panelY + 8, "诊断日志 (" .. totalCount .. "条) | 右键双击电量条关闭")

    -- ===== 实时状态栏 =====
    local statusY = panelY + 28
    nvgBeginPath(vg)
    nvgRect(vg, panelX + 6, statusY, panelW - 12, statusH - 4)
    nvgFillColor(vg, nvgRGBA(20, 30, 50, 200))
    nvgFill(vg)

    if statusGetter then
        local st = statusGetter()
        if st then
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 第一行
            nvgFillColor(vg, nvgRGBA(180, 220, 255, 255))
            local line1 = string.format("阶段=%s | 电量=%.1f%% | 手机=%s | 贷款=%s",
                st.phase or "?", st.battery or 0,
                st.phoneOpen and "开" or "关", st.loanState or "idle")
            nvgText(vg, panelX + 12, statusY + 4, line1)
            -- 第二行
            nvgFillColor(vg, nvgRGBA(160, 200, 240, 220))
            local line2 = string.format("广告=%s | 低电=%s | 屏幕=%.0fx%.0f | 时间=%.0fs",
                st.adShowing and "显示中" or "无",
                st.lowBattery and string.format("%.0fs", st.lowBatteryCountdown or 0) or "否",
                sw, sh, os.clock() - startTime)
            nvgText(vg, panelX + 12, statusY + 20, line2)
            -- 第三行
            if st.extra then
                nvgFillColor(vg, nvgRGBA(255, 200, 100, 200))
                nvgText(vg, panelX + 12, statusY + 36, st.extra)
            end
        end
    end

    -- ===== 日志内容 =====
    local logStartY = statusY + statusH + 4
    local availableH = panelY + panelH - logStartY - padding
    local maxLines = math.floor(availableH / lineH)
    local displayLines = {}
    for i = math.max(1, #lines - maxLines + 1), #lines do
        table.insert(displayLines, lines[i])
    end

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local textY = logStartY
    for _, line in ipairs(displayLines) do
        -- 根据分类着色
        if string.find(line, "%[错误%]") then
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        elseif string.find(line, "%[警告%]") then
            nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        elseif string.find(line, "%[贷款%]") then
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        elseif string.find(line, "%[广告%]") then
            nvgFillColor(vg, nvgRGBA(255, 150, 50, 255))
        elseif string.find(line, "%[事件%]") then
            nvgFillColor(vg, nvgRGBA(200, 255, 100, 255))
        elseif string.find(line, "%[渲染%]") then
            nvgFillColor(vg, nvgRGBA(200, 150, 255, 255))
        elseif string.find(line, "%[输入%]") then
            nvgFillColor(vg, nvgRGBA(255, 180, 220, 255))
        elseif string.find(line, "%[系统%]") then
            nvgFillColor(vg, nvgRGBA(0, 255, 100, 200))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        end
        nvgText(vg, panelX + padding, textY, line)
        textY = textY + lineH
        if textY > panelY + panelH - padding then break end
    end
end

return DiagLog
