-- ====================================================================
-- ScanMiniGame.lua - 扫码对准小游戏
-- ====================================================================
-- 玩家需要移动鼠标对准 QR 码，点击拍摄
-- 移动过快会模糊，QR 码会缓慢漂移
-- 电量低时有额外抖动干扰
-- ====================================================================

local Config = require("Config")
local AudioManager = require("AudioManager")

local ScanMiniGame = {}

-- ============ 内部状态 ============
local active = false
local nvgCtx = nil
local screenW, screenH = 0, 0

-- QR 码位置（相对于取景框中心的偏移）
local qrOffsetX, qrOffsetY = 0, 0
-- QR 码漂移方向
local qrDriftVX, qrDriftVY = 0, 0
local qrDriftTimer = 0

-- 鼠标上一帧位置
local lastMouseX, lastMouseY = 0, 0
-- 当前鼠标速度（用于模糊度）
local mouseSpeedX, mouseSpeedY = 0, 0

-- 模糊度 (0 = 完全清晰, 1 = 完全模糊)
local blurAmount = 0.0
-- 模糊度历史（用于滑动平均）
local blurHistory = {}
local BLUR_HISTORY_LEN = 10

-- 拍摄冷却
local refocusTimer = 0  -- > 0 时在重新对焦中
local REFOCUS_DURATION = 0.5

-- 加载状态（扫码成功后的加载圈）
local loadingActive = false
local loadingTimer = 0
local loadingDuration = 0

-- 结果回调
local onResultCallback = nil

-- 电量引用（外部传入）
local batteryRef = 5.0

-- 提示文案
local hintText = ""
local hintTimer = 0

-- 拍摄闪光效果
local flashTimer = 0

-- 对准参数
local ALIGN_TOLERANCE = 35  -- 对准容差半径（像素）
local BLUR_THRESHOLD = 0.35 -- 清晰度阈值

-- 取景框大小
local VIEWFINDER_W = 0
local VIEWFINDER_H = 0
local QR_SIZE = 0

-- ============ 公开 API ============

function ScanMiniGame.Init(vg, sw, sh)
    nvgCtx = vg
    screenW = sw
    screenH = sh
    -- 取景框占屏幕 65%
    VIEWFINDER_W = math.floor(sw * 0.65)
    VIEWFINDER_H = math.floor(sh * 0.75)
    QR_SIZE = math.floor(math.min(VIEWFINDER_W, VIEWFINDER_H) * 0.3)
end

function ScanMiniGame.Start(battery, callback)
    active = true
    onResultCallback = callback
    batteryRef = battery or 5.0

    -- 初始化 QR 码位置（随机偏移）
    local range = math.floor(VIEWFINDER_W * 0.25)
    qrOffsetX = math.random(-range, range)
    qrOffsetY = math.random(-range, range)

    -- 初始化漂移
    ScanMiniGame._NewDrift()

    -- 重置状态
    blurAmount = 0.0
    blurHistory = {}
    refocusTimer = 0
    loadingActive = false
    loadingTimer = 0
    hintText = "移动鼠标对准二维码，点击拍摄"
    hintTimer = 3.0
    flashTimer = 0

    lastMouseX = input:GetMousePosition().x
    lastMouseY = input:GetMousePosition().y
end

function ScanMiniGame.Stop()
    active = false
    loadingActive = false
end

function ScanMiniGame.IsActive()
    return active
end

function ScanMiniGame.IsLoading()
    return loadingActive
end

function ScanMiniGame.UpdateBattery(battery)
    batteryRef = battery
end

-- ============ 更新逻辑（每帧调用）============

function ScanMiniGame.Update(dt)
    if not active then return end

    -- 加载中状态
    if loadingActive then
        loadingTimer = loadingTimer + dt
        if loadingTimer >= loadingDuration then
            loadingActive = false
            active = false
            if onResultCallback then
                onResultCallback("success")
            end
        end
        return
    end

    -- 重新对焦计时
    if refocusTimer > 0 then
        refocusTimer = refocusTimer - dt
        -- 对焦期间模糊度高
        blurAmount = 0.7 + math.sin(refocusTimer * 12) * 0.1
    end

    -- 鼠标移动计算
    local mx = input:GetMousePosition().x
    local my = input:GetMousePosition().y
    local dx = mx - lastMouseX
    local dy = my - lastMouseY
    lastMouseX = mx
    lastMouseY = my

    -- 鼠标速度（像素/帧）
    local speed = math.sqrt(dx * dx + dy * dy)

    -- 更新模糊度滑动平均
    table.insert(blurHistory, speed)
    if #blurHistory > BLUR_HISTORY_LEN then
        table.remove(blurHistory, 1)
    end
    local avgSpeed = 0
    for _, v in ipairs(blurHistory) do
        avgSpeed = avgSpeed + v
    end
    avgSpeed = avgSpeed / #blurHistory

    -- 模糊度计算（非对焦期间）
    if refocusTimer <= 0 then
        local targetBlur = math.min(1.0, avgSpeed / 40.0)
        -- 模糊度上升快、下降慢
        if targetBlur > blurAmount then
            blurAmount = blurAmount + (targetBlur - blurAmount) * 8 * dt
        else
            blurAmount = blurAmount + (targetBlur - blurAmount) * 3 * dt
        end
    end

    -- 鼠标移动影响取景偏移（鼠标往右移 → QR 码往左移，反向）
    if refocusTimer <= 0 then
        qrOffsetX = qrOffsetX - dx * 0.8
        qrOffsetY = qrOffsetY - dy * 0.8
    end

    -- QR 码漂移
    qrDriftTimer = qrDriftTimer - dt
    if qrDriftTimer <= 0 then
        ScanMiniGame._NewDrift()
    end
    qrOffsetX = qrOffsetX + qrDriftVX * dt
    qrOffsetY = qrOffsetY + qrDriftVY * dt

    -- 电量低时额外抖动
    local shakeAmount = 0
    if batteryRef <= 1 then
        shakeAmount = 4.0
    elseif batteryRef <= 2 then
        shakeAmount = 2.0
    elseif batteryRef <= 3 then
        shakeAmount = 0.8
    end
    if shakeAmount > 0 then
        qrOffsetX = qrOffsetX + math.sin(os.clock() * 15) * shakeAmount * dt * 60
        qrOffsetY = qrOffsetY + math.cos(os.clock() * 12) * shakeAmount * 0.6 * dt * 60
    end

    -- 限制 QR 码不要跑太远
    local maxRange = VIEWFINDER_W * 0.45
    qrOffsetX = math.max(-maxRange, math.min(maxRange, qrOffsetX))
    qrOffsetY = math.max(-maxRange, math.min(maxRange, qrOffsetY))

    -- 闪光衰减
    if flashTimer > 0 then
        flashTimer = flashTimer - dt
    end

    -- 提示衰减
    if hintTimer > 0 then
        hintTimer = hintTimer - dt
    end
end

-- ============ 点击拍摄 ============

function ScanMiniGame.OnClick()
    if not active or loadingActive then return end

    -- 闪光效果
    flashTimer = 0.15

    -- 检查是否在重新对焦中
    if refocusTimer > 0 then
        hintText = "正在对焦中..."
        hintTimer = 1.5
        return
    end

    -- 判定条件
    local dist = math.sqrt(qrOffsetX * qrOffsetX + qrOffsetY * qrOffsetY)
    local isAligned = dist < ALIGN_TOLERANCE
    local isClear = blurAmount < BLUR_THRESHOLD

    if isAligned and isClear then
        -- 成功！进入加载状态
        AudioManager.ScanSuccess()
        hintText = "识别成功！正在加载..."
        hintTimer = 10
        loadingActive = true
        loadingTimer = 0
        -- 加载时长与电量相关：电量越低加载越慢
        if batteryRef <= 1 then
            loadingDuration = 3.5
        elseif batteryRef <= 2 then
            loadingDuration = 2.5
        elseif batteryRef <= 3 then
            loadingDuration = 1.8
        else
            loadingDuration = 1.2
        end
    else
        -- 失败 - 进入重新对焦
        AudioManager.ScanFail()
        refocusTimer = REFOCUS_DURATION

        -- 失败反馈文案
        if not isAligned and isClear then
            if dist < ALIGN_TOLERANCE * 2 then
                hintText = "请将二维码完整置于框内"
            else
                hintText = "二维码显示不全，请对准拍摄"
            end
        elseif isAligned and not isClear then
            hintText = "图片过于模糊，无法识别"
        else
            hintText = "未检测到二维码"
        end
        hintTimer = 2.0
    end
end

-- ============ NanoVG 渲染 ============

function ScanMiniGame.Render(vg, sw, sh)
    if not active then return end
    screenW = sw
    screenH = sh

    -- 全屏半透明背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    -- 取景框区域
    local vfX = (sw - VIEWFINDER_W) / 2
    local vfY = (sh - VIEWFINDER_H) / 2 - 20

    -- 取景框背景（模拟手机摄像头画面 - 深灰色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, vfX, vfY, VIEWFINDER_W, VIEWFINDER_H, 12)
    nvgFillColor(vg, nvgRGBA(15, 15, 20, 255))
    nvgFill(vg)

    -- QR 码（在取景框内偏移绘制）
    local qrCenterX = vfX + VIEWFINDER_W / 2 + qrOffsetX
    local qrCenterY = vfY + VIEWFINDER_H / 2 + qrOffsetY
    ScanMiniGame._RenderQRCode(vg, qrCenterX, qrCenterY, QR_SIZE, blurAmount)

    -- 对准框（取景框中央的方框）
    local targetSize = QR_SIZE + 20
    if batteryRef <= 1 then
        targetSize = targetSize - 10  -- 电量极低时对准框缩小
    end
    local targetX = vfX + VIEWFINDER_W / 2 - targetSize / 2
    local targetY = vfY + VIEWFINDER_H / 2 - targetSize / 2
    ScanMiniGame._RenderTargetFrame(vg, targetX, targetY, targetSize, targetSize)

    -- 取景框边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, vfX, vfY, VIEWFINDER_W, VIEWFINDER_H, 12)
    nvgStrokeColor(vg, nvgRGBA(80, 120, 200, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 手机外部 QR 码参考位置（半透明小图）
    ScanMiniGame._RenderExternalHint(vg, vfX, vfY, qrCenterX, qrCenterY)

    -- 提示文案（取景框底部）
    if hintTimer > 0 and hintText ~= "" then
        local hintAlpha = math.min(255, math.floor(hintTimer * 255))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        -- 背景条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, vfX + 10, vfY + VIEWFINDER_H - 36, VIEWFINDER_W - 20, 28, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(hintAlpha * 0.7)))
        nvgFill(vg)
        -- 文字
        nvgFillColor(vg, nvgRGBA(255, 220, 100, hintAlpha))
        nvgText(vg, vfX + VIEWFINDER_W / 2, vfY + VIEWFINDER_H - 32, hintText)
    end

    -- 闪光效果（拍摄瞬间）
    if flashTimer > 0 then
        local flashAlpha = math.floor((flashTimer / 0.15) * 180)
        nvgBeginPath(vg)
        nvgRect(vg, vfX, vfY, VIEWFINDER_W, VIEWFINDER_H)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end

    -- 加载中 UI
    if loadingActive then
        ScanMiniGame._RenderLoading(vg, sw, sh)
    end

    -- 顶部标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 255))
    nvgText(vg, sw / 2, vfY - 28, "扫描二维码")

    -- 操作提示（底部）
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(150, 150, 180, 200))
    nvgText(vg, sw / 2, vfY + VIEWFINDER_H + 12, "移动鼠标对准 · 点击拍摄 · ESC退出")
end

-- ============ 内部绘制函数 ============

function ScanMiniGame._RenderQRCode(vg, cx, cy, size, blur)
    local half = size / 2
    local x = cx - half
    local y = cy - half

    -- 模糊效果：通过多次偏移半透明绘制模拟
    local passes = 1
    local baseAlpha = 255
    if blur > 0.1 then
        passes = math.floor(blur * 6) + 1
        baseAlpha = math.floor(255 / (passes * 0.6))
    end

    for p = 1, passes do
        local ox, oy = 0, 0
        if p > 1 then
            -- 随机偏移模拟运动模糊
            local blurDist = blur * 12
            ox = (math.random() - 0.5) * blurDist * 2
            oy = (math.random() - 0.5) * blurDist * 2
        end

        local px = x + ox
        local py = y + oy

        -- QR 码白底
        nvgBeginPath(vg)
        nvgRect(vg, px - 4, py - 4, size + 8, size + 8)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, baseAlpha))
        nvgFill(vg)

        -- 程序化 QR 码方块图案
        local cellCount = 8
        local cellSize = size / cellCount
        -- 使用固定随机种子让 QR 码图案一致
        local seed = 42
        for row = 0, cellCount - 1 do
            for col = 0, cellCount - 1 do
                -- 定位方块（三个角必有）
                local isCorner = (row < 2 and col < 2) or
                                 (row < 2 and col >= cellCount - 2) or
                                 (row >= cellCount - 2 and col < 2)
                -- 伪随机填充
                seed = (seed * 1103515245 + 12345) % 2147483648
                local filled = isCorner or (seed % 3 ~= 0)

                if filled then
                    nvgBeginPath(vg)
                    nvgRect(vg, px + col * cellSize + 1, py + row * cellSize + 1,
                            cellSize - 2, cellSize - 2)
                    nvgFillColor(vg, nvgRGBA(20, 20, 30, baseAlpha))
                    nvgFill(vg)
                end
            end
        end

        -- 三个定位点（方框套方框）
        ScanMiniGame._RenderFinderPattern(vg, px + cellSize * 0.2, py + cellSize * 0.2, cellSize * 1.6, baseAlpha)
        ScanMiniGame._RenderFinderPattern(vg, px + (cellCount - 2) * cellSize + cellSize * 0.2, py + cellSize * 0.2, cellSize * 1.6, baseAlpha)
        ScanMiniGame._RenderFinderPattern(vg, px + cellSize * 0.2, py + (cellCount - 2) * cellSize + cellSize * 0.2, cellSize * 1.6, baseAlpha)
    end
end

function ScanMiniGame._RenderFinderPattern(vg, x, y, size, alpha)
    -- 外框
    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
    nvgFill(vg)
    -- 内白
    local m = size * 0.2
    nvgBeginPath(vg)
    nvgRect(vg, x + m, y + m, size - m * 2, size - m * 2)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(vg)
    -- 内核
    local m2 = size * 0.35
    nvgBeginPath(vg)
    nvgRect(vg, x + m2, y + m2, size - m2 * 2, size - m2 * 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
    nvgFill(vg)
end

function ScanMiniGame._RenderTargetFrame(vg, x, y, w, h)
    -- 四角 L 型标记
    local cornerLen = 18
    local lineWidth = 3

    -- 计算对准程度决定颜色
    local dist = math.sqrt(qrOffsetX * qrOffsetX + qrOffsetY * qrOffsetY)
    local r, g, b = 100, 180, 255  -- 默认蓝色
    if dist < ALIGN_TOLERANCE then
        r, g, b = 50, 255, 100  -- 对准了 → 绿色
    elseif dist < ALIGN_TOLERANCE * 2 then
        r, g, b = 255, 200, 50  -- 接近 → 黄色
    end

    nvgStrokeColor(vg, nvgRGBA(r, g, b, 230))
    nvgStrokeWidth(vg, lineWidth)

    -- 左上角
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + cornerLen)
    nvgLineTo(vg, x, y)
    nvgLineTo(vg, x + cornerLen, y)
    nvgStroke(vg)
    -- 右上角
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w - cornerLen, y)
    nvgLineTo(vg, x + w, y)
    nvgLineTo(vg, x + w, y + cornerLen)
    nvgStroke(vg)
    -- 左下角
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + h - cornerLen)
    nvgLineTo(vg, x, y + h)
    nvgLineTo(vg, x + cornerLen, y + h)
    nvgStroke(vg)
    -- 右下角
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w - cornerLen, y + h)
    nvgLineTo(vg, x + w, y + h)
    nvgLineTo(vg, x + w, y + h - cornerLen)
    nvgStroke(vg)

    -- 中心十字辅助线（小）
    local crossSize = 6
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, 120))
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w / 2 - crossSize, y + h / 2)
    nvgLineTo(vg, x + w / 2 + crossSize, y + h / 2)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w / 2, y + h / 2 - crossSize)
    nvgLineTo(vg, x + w / 2, y + h / 2 + crossSize)
    nvgStroke(vg)
end

function ScanMiniGame._RenderExternalHint(vg, vfX, vfY, qrCX, qrCY)
    -- 在取景框外画一个小箭头和 QR 码的参考位置
    -- 显示 QR 码相对于屏幕中心的方向

    local centerX = vfX + VIEWFINDER_W / 2
    local centerY = vfY + VIEWFINDER_H / 2
    local dirX = qrCX - centerX
    local dirY = qrCY - centerY
    local dist = math.sqrt(dirX * dirX + dirY * dirY)

    if dist < 5 then return end  -- 几乎对准了就不显示

    -- 归一化方向
    local ndx = dirX / dist
    local ndy = dirY / dist

    -- 箭头位置（取景框边缘外侧）
    local arrowDist = math.min(VIEWFINDER_W, VIEWFINDER_H) / 2 + 25
    local arrowX = centerX + ndx * arrowDist
    local arrowY = centerY + ndy * arrowDist

    -- 小箭头三角形
    local arrowSize = 8
    local perpX = -ndy * arrowSize
    local perpY = ndx * arrowSize

    local alpha = math.min(255, math.floor(dist * 2))
    nvgBeginPath(vg)
    nvgMoveTo(vg, arrowX + ndx * arrowSize, arrowY + ndy * arrowSize)
    nvgLineTo(vg, arrowX + perpX, arrowY + perpY)
    nvgLineTo(vg, arrowX - perpX, arrowY - perpY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, alpha))
    nvgFill(vg)

    -- 在箭头旁写"QR"标记
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, alpha))
    nvgText(vg, arrowX + ndx * 18, arrowY + ndy * 18, "QR")
end

function ScanMiniGame._RenderLoading(vg, sw, sh)
    -- 全屏半透明覆盖
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 加载圈
    local cx = sw / 2
    local cy = sh / 2
    local radius = 24
    local angle = loadingTimer * 4  -- 旋转速度

    -- 圆弧
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, radius, angle, angle + math.pi * 1.5, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 255))
    nvgText(vg, cx, cy + radius + 12, "加载中...")

    -- 进度百分比
    local pct = math.floor((loadingTimer / loadingDuration) * 100)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(150, 150, 180, 200))
    nvgText(vg, cx, cy + radius + 30, pct .. "%")
end

-- ============ 内部工具 ============

function ScanMiniGame._NewDrift()
    -- 随机新漂移方向
    local speed = 15 + math.random() * 20  -- 漂移速度
    local angle = math.random() * math.pi * 2
    qrDriftVX = math.cos(angle) * speed
    qrDriftVY = math.sin(angle) * speed
    qrDriftTimer = 1.5 + math.random() * 2.0
end

return ScanMiniGame
