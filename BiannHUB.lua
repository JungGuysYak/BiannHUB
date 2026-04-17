--[[
    BIANNHUB RECORDER v2 - FINAL (No Empty Space)
    Fitur: Minimize collapse, Close total stop, layout rapat
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local VERSION = "2"
local DATA_FOLDER = "BiannHUBRecords"
local MIN_FRAMES = 5
local WALK_VEL_THRESHOLD = 0.2

local MAX_VELOCITY_CLAMP = 50
local SMOOTHING_FACTOR = 0.85

local SKIP_IDLE = true
local IDLE_VEL_THRESHOLD = 0.3

if not isfolder(DATA_FOLDER) then makefolder(DATA_FOLDER) end

-- ==================== STATE ====================
local isRecording = false
local recordedFrames = {}
local recordStartTime = 0
local recordHB = nil
local pendingFrames = nil
local isSaving = false

local isPlaying = false
local isPaused = false
local isLooping = false
local currentData = nil
local currentFrames = nil
local playbackStartTime = 0
local playbackTime = 0
local walkHB = nil
local originalWalkSpeed = 16
local originalJumpPower = 50

local savedRecords = {}
local selectedRecord = nil
local notifLabel = nil

local updatePlaybackUI = function() end
local renderList = function() end

local savedPosition = nil
local recordingIndicator = nil
local guiFrame = nil
local isCollapsed = false
local originalHeight = 470

-- ==================== FUNGSI DASAR ====================
local function getGroundLevel(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local origin = Vector3.new(pos.X, pos.Y + 5, pos.Z)
    local direction = Vector3.new(0, -15, 0)
    local result = Workspace:Raycast(origin, direction, params)
    if result then return result.Position.Y end
    return pos.Y - 3
end

local function getYaw(cf)
    local success, yaw = pcall(function() return cf:Yaw() end)
    if success then return yaw end
    return math.atan2(cf.LookVector.X, cf.LookVector.Z)
end

local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LP.Character
    return c and c:FindFirstChild("Humanoid")
end

-- ==================== NOTIF ====================
local function notif(msg, color, duration)
    if not notifLabel then return end
    notifLabel.Text = msg
    notifLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    notifLabel.TextTransparency = 0
    notifLabel.BackgroundTransparency = 0
    notifLabel.Visible = true
    task.delay(duration or 3.5, function()
        if not notifLabel then return end
        for i = 1, 10 do
            notifLabel.TextTransparency = i / 10
            notifLabel.BackgroundTransparency = i / 10
            task.wait(0.05)
        end
        notifLabel.Visible = false
        notifLabel.BackgroundTransparency = 0
        notifLabel.TextTransparency = 0
    end)
end

-- ==================== RECORDING (sama persis) ====================
local function stopRecording()
    if not isRecording then
        notif("❌ Tidak sedang merekam", Color3.fromRGB(255,100,100))
        return
    end
    isRecording = false
    if recordHB then recordHB:Disconnect(); recordHB = nil end
    local hum = getHum()
    if hum then hum.AutoRotate = true end

    if recordingIndicator then
        recordingIndicator:Destroy()
        recordingIndicator = nil
    end

    if #recordedFrames < MIN_FRAMES then
        notif(string.format("❌ Rekaman terlalu pendek (%d frame)", #recordedFrames), Color3.fromRGB(255,100,100))
        recordedFrames = {}
        pendingFrames = nil
        return
    end

    local startIdx = 1
    for i = 1, #recordedFrames do
        local f = recordedFrames[i]
        local speed = math.sqrt(f.velocity.x^2 + f.velocity.z^2)
        if speed >= WALK_VEL_THRESHOLD then
            startIdx = i
            break
        end
    end

    local trimmed = {}
    if startIdx > 1 and startIdx <= #recordedFrames then
        local timeOffset = recordedFrames[startIdx].time
        for i = startIdx, #recordedFrames do
            local f = recordedFrames[i]
            local newFrame = {}
            for k,v in pairs(f) do newFrame[k] = v end
            newFrame.time = f.time - timeOffset
            table.insert(trimmed, newFrame)
        end
    else
        trimmed = recordedFrames
    end

    if #trimmed < MIN_FRAMES then
        notif("❌ Rekaman terlalu pendek setelah trim", Color3.fromRGB(255,100,100))
        recordedFrames = {}
        pendingFrames = nil
        return
    end

    pendingFrames = trimmed
    recordedFrames = {}
    notif(string.format("⏹ %d frame (%.1fs) — siap save", #pendingFrames, pendingFrames[#pendingFrames].time),
          Color3.fromRGB(255,200,50))
end

local function createRecordingIndicator()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RecorderIndicator"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = LP:WaitForChild("PlayerGui")
    
    local blackBg = Instance.new("Frame")
    blackBg.Size = UDim2.new(0, 64, 0, 64)
    blackBg.Position = UDim2.new(0, 12, 0.6, -32)
    blackBg.AnchorPoint = Vector2.new(0, 0.5)
    blackBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    blackBg.BackgroundTransparency = 0
    blackBg.BorderSizePixel = 0
    blackBg.Visible = true
    blackBg.ZIndex = 10
    blackBg.Active = true
    blackBg.Selectable = true
    local blackCorner = Instance.new("UICorner")
    blackCorner.CornerRadius = UDim.new(1, 0)
    blackCorner.Parent = blackBg
    blackBg.Parent = screenGui
    
    local redDot = Instance.new("Frame")
    redDot.Size = UDim2.new(0, 36, 0, 36)
    redDot.Position = UDim2.new(0.5, -18, 0.5, -18)
    redDot.AnchorPoint = Vector2.new(0, 0)
    redDot.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
    redDot.BackgroundTransparency = 0
    redDot.BorderSizePixel = 0
    redDot.ZIndex = 12
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = redDot
    redDot.Parent = blackBg
    
    task.spawn(function()
        while redDot and redDot.Parent do
            redDot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
            redDot.BackgroundTransparency = 0
            task.wait(0.5)
            redDot.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
            redDot.BackgroundTransparency = 0.2
            task.wait(0.5)
        end
    end)
    
    blackBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if isRecording then stopRecording() end
            if guiFrame then guiFrame.Visible = true end
        end
    end)
    
    return blackBg
end

local function showRecordingIndicator(show)
    if show then
        if not recordingIndicator or not recordingIndicator.Parent then
            recordingIndicator = createRecordingIndicator()
        else
            recordingIndicator.Visible = true
        end
    else
        if recordingIndicator then
            recordingIndicator:Destroy()
            recordingIndicator = nil
        end
    end
end

local function getNextCheckpointNum()
    local max = 0
    if isfolder(DATA_FOLDER) then
        for _, file in ipairs(listfiles(DATA_FOLDER)) do
            local n = file:match("Checkpoint_(%d+)%.json$")
            if n then
                local num = tonumber(n)
                if num and num > max then max = num end
            end
        end
    end
    return max + 1
end

local function startRecording()
    if isPlaying then
        notif("❌ Hentikan playback dulu", Color3.fromRGB(255,100,100))
        return
    end
    if isRecording then
        if recordHB then recordHB:Disconnect(); recordHB = nil end
        isRecording = false
    end
    pendingFrames = nil
    recordedFrames = {}
    recordStartTime = tick()
    isRecording = true

    if guiFrame then guiFrame.Visible = false end
    showRecordingIndicator(true)

    local lastRecTick = tick()
    notif("🔴 Merekam...", Color3.fromRGB(255,80,80))

    if recordHB then recordHB:Disconnect() end
    recordHB = RunService.Heartbeat:Connect(function()
        if not isRecording then
            recordHB:Disconnect()
            recordHB = nil
            return
        end
        local now = tick()
        if now - lastRecTick < 1/60 then return end
        lastRecTick = now

        local hrp = getHRP()
        local hum = getHum()
        if not hrp then return end

        local pos = hrp.Position
        local cf = hrp.CFrame
        local vel = hrp.AssemblyLinearVelocity
        local groundY = getGroundLevel(pos)

        local rotY = getYaw(cf)
        local moveDir = Vector3.new(vel.X, 0, vel.Z).Unit
        if moveDir.Magnitude < 0.01 then moveDir = Vector3.new(0,0,0) end

        local state = hum and hum:GetState() or Enum.HumanoidStateType.Running
        local stateStr = tostring(state):gsub("Enum.HumanoidStateType.", "")
        local isJumping = (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall)

        table.insert(recordedFrames, {
            position = { x = pos.X, y = pos.Y, z = pos.Z },
            velocity = { x = vel.X, y = vel.Y, z = vel.Z },
            rotation = rotY,
            moveDirection = { x = moveDir.X, y = 0, z = moveDir.Z },
            state = stateStr,
            walkSpeed = hum and hum.WalkSpeed or 16,
            hipHeight = hum and hum.HipHeight or 0,
            jumping = isJumping,
            time = now - recordStartTime,
            groundLevel = groundY,
            cf_right = { x = cf.RightVector.X, y = cf.RightVector.Y, z = cf.RightVector.Z },
            cf_up = { x = cf.UpVector.X, y = cf.UpVector.Y, z = cf.UpVector.Z },
        })
    end)
end

local function saveRecording()
    if isSaving then
        notif("⚠️ Sedang menyimpan...", Color3.fromRGB(255,200,50))
        return nil
    end
    if not pendingFrames or #pendingFrames == 0 then
        notif("❌ Tidak ada rekaman", Color3.fromRGB(255,100,100))
        return nil
    end
    isSaving = true
    local num = getNextCheckpointNum()
    local name = "Checkpoint_" .. num
    local fileName = DATA_FOLDER .. "/" .. name .. ".json"
    local data = {
        name = name,
        date = os.time(),
        version = VERSION,
        frames = pendingFrames,
        totalFrames = #pendingFrames,
        duration = pendingFrames[#pendingFrames].time,
    }
    local ok, err = pcall(function()
        writefile(fileName, HttpService:JSONEncode(data))
    end)
    if ok then
        notif(string.format("💾 %s (%d frame)", name, #pendingFrames), Color3.fromRGB(100,255,150))
        pendingFrames = nil
        isSaving = false
        return name
    else
        notif("❌ Gagal: "..tostring(err), Color3.fromRGB(255,100,100))
        isSaving = false
        return nil
    end
end

-- ==================== LOAD RECORD ====================
local function getRecordFilePath(name)
    local mainFile = DATA_FOLDER .. "/" .. name .. ".json"
    if isfile(mainFile) then return mainFile end
    return nil
end

local function loadRecord(name)
    local filePath = getRecordFilePath(name)
    if not filePath then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(filePath)) end)
    if not ok then return false end
    currentData = data
    currentFrames = data.frames
    selectedRecord = name
    notif(string.format("📂 %s (%d frame)", name, data.totalFrames or 0), Color3.fromRGB(100,180,255))
    return true
end

local function deleteRecord(name)
    local filePath = getRecordFilePath(name)
    if not filePath then return false end
    delfile(filePath)
    if currentData and currentData.name == name then currentData = nil end
    if selectedRecord == name then selectedRecord = nil end
    notif("🗑️ Dihapus: "..name, Color3.fromRGB(255,160,60))
    return true
end

local function sortRecords(list)
    table.sort(list, function(a,b)
        local na = tonumber(a:match("Checkpoint_(%d+)$"))
        local nb = tonumber(b:match("Checkpoint_(%d+)$"))
        if na and nb then return na < nb end
        if na then return true end
        if nb then return false end
        return a < b
    end)
end

local function refreshRecords()
    savedRecords = {}
    if isfolder(DATA_FOLDER) then
        for _, file in ipairs(listfiles(DATA_FOLDER)) do
            if file:find("%.json$") then
                local name = file:match("([^/\\]+)%.json$")
                if name then table.insert(savedRecords, name) end
            end
        end
    end
    sortRecords(savedRecords)
end

-- ==================== KOMPRESI ====================
local function getCompressedFrames(originalFrames)
    if not SKIP_IDLE then return originalFrames end
    
    local movingFrames = {}
    for _, frame in ipairs(originalFrames) do
        local speed = math.sqrt(frame.velocity.x^2 + frame.velocity.z^2)
        local isIdle = speed < IDLE_VEL_THRESHOLD
        if not isIdle or frame.jumping then
            table.insert(movingFrames, frame)
        end
    end
    
    if #movingFrames < 2 then return originalFrames end
    
    local reconstructed = {}
    local currentTime = 0
    for i, frame in ipairs(movingFrames) do
        local newFrame = {}
        for k,v in pairs(frame) do newFrame[k] = v end
        newFrame.time = currentTime
        table.insert(reconstructed, newFrame)
        
        if i < #movingFrames then
            local nextFrame = movingFrames[i+1]
            local dx = nextFrame.position.x - frame.position.x
            local dz = nextFrame.position.z - frame.position.z
            local dist = math.sqrt(dx*dx + dz*dz)
            local v1 = math.sqrt(frame.velocity.x^2 + frame.velocity.z^2)
            local v2 = math.sqrt(nextFrame.velocity.x^2 + nextFrame.velocity.z^2)
            local avgSpeed = (v1 + v2) / 2
            local delta = 0.016
            if avgSpeed > 0.1 then
                delta = dist / avgSpeed
                delta = math.max(delta, 0.016)
                delta = math.min(delta, 0.1)
            end
            currentTime = currentTime + delta
        end
    end
    return reconstructed
end

-- ==================== PLAYBACK ENGINE ====================
local function binarySearch(frames, time)
    local lo, hi = 1, #frames
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if frames[mid].time <= time then lo = mid else hi = mid - 1 end
    end
    return lo
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpVector(v1, v2, t)
    return Vector3.new(lerp(v1.x, v2.x, t), lerp(v1.y, v2.y, t), lerp(v1.z, v2.z, t))
end

local function lerpAngle(a, b, t)
    local diff = b - a
    diff = math.atan2(math.sin(diff), math.cos(diff))
    return a + diff * t
end

local function findNearestFrameIndex(frames, currentPos)
    local nearestIdx = 1
    local nearestDist = math.huge
    for i, frame in ipairs(frames) do
        local framePos = Vector3.new(frame.position.x, frame.position.y, frame.position.z)
        local dist = (framePos - currentPos).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearestIdx = i
        end
    end
    return nearestIdx, nearestDist
end

local function stopPlayback()
    isPlaying = false
    isPaused = false
    if walkHB then walkHB:Disconnect(); walkHB = nil end
    
    local hrp = getHRP()
    local hum = getHum()
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    if hum then
        hum.AutoRotate = true
        hum.WalkSpeed = originalWalkSpeed
        hum.JumpPower = originalJumpPower
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    playbackTime = 0
    notif("⏹️ Playback berhenti", Color3.fromRGB(200,200,200))
    if updatePlaybackUI then updatePlaybackUI(false) end
end

local function pausePlayback()
    if not isPlaying then return end
    isPaused = not isPaused
    if not isPaused then
        playbackStartTime = tick() - playbackTime
    end
    notif(isPaused and "⏸️ Pause" or "▶️ Resume", Color3.fromRGB(255,180,60))
end

local function startPlaybackFromTime(startTime)
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        return false
    end
    
    if isPlaying then stopPlayback() end
    
    originalWalkSpeed = hum.WalkSpeed
    originalJumpPower = hum.JumpPower
    
    local frames = getCompressedFrames(currentFrames)
    if #frames < 2 then
        notif("❌ Rekaman terlalu pendek setelah kompresi", Color3.fromRGB(255,100,100))
        return false
    end
    
    playbackTime = math.clamp(startTime, 0, frames[#frames].time)
    local startFrame = frames[binarySearch(frames, playbackTime)]
    
    hrp.CFrame = CFrame.new(startFrame.position.x, startFrame.position.y, startFrame.position.z)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    
    hum.AutoRotate = false
    hum.WalkSpeed = originalWalkSpeed
    hum.JumpPower = originalJumpPower
    hum:ChangeState(Enum.HumanoidStateType.Running)
    
    isPlaying = true
    isPaused = false
    playbackStartTime = tick() - playbackTime
    
    if walkHB then walkHB:Disconnect() end
    
    local lastVelocity = Vector3.zero
    
    walkHB = RunService.Heartbeat:Connect(function()
        if not isPlaying then
            if walkHB then walkHB:Disconnect(); walkHB = nil end
            return
        end
        if isPaused then
            playbackStartTime = tick() - playbackTime
            return
        end
        
        local currentHRP = getHRP()
        local currentHum = getHum()
        if not currentHRP or not currentHum then
            stopPlayback()
            return
        end
        
        local now = tick()
        local newPlaybackTime = now - playbackStartTime
        local totalDur = frames[#frames].time
        
        if newPlaybackTime >= totalDur then
            if isLooping then
                newPlaybackTime = 0
                playbackStartTime = now
                playbackTime = 0
                notif("🔄 Loop", Color3.fromRGB(150,220,255), 1)
            else
                stopPlayback()
                notif("✅ Selesai", Color3.fromRGB(100,255,150))
                return
            end
        end
        
        playbackTime = newPlaybackTime
        
        local frameIdx = binarySearch(frames, playbackTime)
        local nextIdx = math.min(frameIdx + 1, #frames)
        local f1 = frames[frameIdx]
        local f2 = frames[nextIdx]
        
        local deltaTime = f2.time - f1.time
        local t = (playbackTime - f1.time) / (deltaTime > 0 and deltaTime or 0.001)
        t = math.clamp(t, 0, 1)
        
        local pos1 = Vector3.new(f1.position.x, f1.position.y, f1.position.z)
        local pos2 = Vector3.new(f2.position.x, f2.position.y, f2.position.z)
        local newPos = lerpVector(pos1, pos2, t)
        
        local right1 = Vector3.new(f1.cf_right.x, f1.cf_right.y, f1.cf_right.z)
        local right2 = Vector3.new(f2.cf_right.x, f2.cf_right.y, f2.cf_right.z)
        local up1 = Vector3.new(f1.cf_up.x, f1.cf_up.y, f1.cf_up.z)
        local up2 = Vector3.new(f2.cf_up.x, f2.cf_up.y, f2.cf_up.z)
        local right = lerpVector(right1, right2, t)
        local up = lerpVector(up1, up2, t)
        local newCF = CFrame.fromMatrix(newPos, right, up)
        
        local vel1 = Vector3.new(f1.velocity.x, f1.velocity.y, f1.velocity.z)
        local vel2 = Vector3.new(f2.velocity.x, f2.velocity.y, f2.velocity.z)
        local targetVel = lerpVector(vel1, vel2, t)
        
        local newVel = lastVelocity * SMOOTHING_FACTOR + targetVel * (1 - SMOOTHING_FACTOR)
        if newVel.Magnitude > MAX_VELOCITY_CLAMP then
            newVel = newVel.Unit * MAX_VELOCITY_CLAMP
        end
        
        currentHRP.CFrame = newCF
        currentHRP.AssemblyLinearVelocity = newVel
        currentHRP.AssemblyAngularVelocity = Vector3.zero
        
        local isJumpingNow = f1.jumping or (f2.jumping and t > 0.5)
        if isJumpingNow and currentHum:GetState() ~= Enum.HumanoidStateType.Jumping and currentHum:GetState() ~= Enum.HumanoidStateType.Freefall then
            currentHum:ChangeState(Enum.HumanoidStateType.Jumping)
        elseif not isJumpingNow and (currentHum:GetState() == Enum.HumanoidStateType.Jumping or currentHum:GetState() == Enum.HumanoidStateType.Freefall) then
            if currentHum.FloorMaterial ~= Enum.Material.Air then
                currentHum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        
        lastVelocity = newVel
    end)
    
    notif(string.format("▶️ %s (dari %.1fs)", currentData.name, playbackTime), Color3.fromRGB(100,255,150))
    if updatePlaybackUI then updatePlaybackUI(true) end
    return true
end

local function startPlaybackFromStart()
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    return startPlaybackFromTime(0)
end

local function startPlaybackFromNearest()
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    local hrp = getHRP()
    if not hrp then
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        return false
    end
    local currentPos = hrp.Position
    local nearestIdx, nearestDist = findNearestFrameIndex(currentFrames, currentPos)
    local startTime = currentFrames[nearestIdx].time
    notif(string.format("📍 Resume nearest: frame %d (jarak %.1f studs) | waktu: %.2fs", nearestIdx, nearestDist, startTime), Color3.fromRGB(100,255,150), 2.5)
    return startPlaybackFromTime(startTime)
end

-- ==================== SAVE/LOAD POSISI ====================
local function savePosition()
    local hrp = getHRP()
    if hrp then
        savedPosition = hrp.CFrame
        notif("💾 Posisi tersimpan", Color3.fromRGB(100,255,100))
    else
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
    end
end

local function loadPosition()
    if savedPosition then
        local hrp = getHRP()
        local hum = getHum()
        if hrp and hum then
            hrp.CFrame = savedPosition
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hum.AutoRotate = true
            hum:ChangeState(Enum.HumanoidStateType.Running)
            notif("📂 Posisi dimuat", Color3.fromRGB(100,200,255))
        else
            notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        end
    else
        notif("❌ Belum ada posisi tersimpan", Color3.fromRGB(255,100,100))
    end
end

-- ==================== MERGE TANPA JEDA ====================
local function mergeAndCompressAll()
    local toMerge = {}
    for _, name in ipairs(savedRecords) do
        if name:match("^Checkpoint_%d+$") or name:match("^Merged") then
            local filePath = DATA_FOLDER .. "/" .. name .. ".json"
            if isfile(filePath) then table.insert(toMerge, name) end
        end
    end
    if #toMerge < 2 then
        notif("❌ Minimal 2 Checkpoint", Color3.fromRGB(255,100,100))
        return
    end

    local cpDataList = {}
    for _, name in ipairs(toMerge) do
        local fileName = DATA_FOLDER .. "/" .. name .. ".json"
        if not isfile(fileName) then continue end
        local raw = readfile(fileName)
        if raw == "" then continue end
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or not data or not data.frames or #data.frames < 2 then continue end
        table.insert(cpDataList, { name = name, frames = data.frames })
    end

    if #cpDataList < 2 then
        notif("❌ Minimal 2 CP valid", Color3.fromRGB(255,100,100))
        return
    end

    local allRawFrames = {}
    for _, cpData in ipairs(cpDataList) do
        local frames = cpData.frames
        local startIdx, endIdx = 1, #frames
        for i = 1, #frames do
            local speed = math.sqrt(frames[i].velocity.x^2 + frames[i].velocity.z^2)
            if speed >= WALK_VEL_THRESHOLD then startIdx = i; break end
        end
        for i = #frames, 1, -1 do
            local speed = math.sqrt(frames[i].velocity.x^2 + frames[i].velocity.z^2)
            if speed >= WALK_VEL_THRESHOLD then endIdx = i; break end
        end
        if startIdx > endIdx then startIdx, endIdx = 1, #frames end
        for i = startIdx, endIdx do
            table.insert(allRawFrames, frames[i])
        end
    end

    if #allRawFrames < 2 then
        notif("❌ Tidak cukup frame setelah trim", Color3.fromRGB(255,100,100))
        return
    end

    local mergedFrames = {}
    local currentTime = 0
    for i = 1, #allRawFrames do
        local frame = allRawFrames[i]
        local newFrame = {}
        for k,v in pairs(frame) do newFrame[k] = v end
        newFrame.time = currentTime
        table.insert(mergedFrames, newFrame)
        
        if i < #allRawFrames then
            local nextFrame = allRawFrames[i+1]
            local pos1 = Vector3.new(frame.position.x, frame.position.y, frame.position.z)
            local pos2 = Vector3.new(nextFrame.position.x, nextFrame.position.y, nextFrame.position.z)
            local dist = (pos2 - pos1).Magnitude
            local v1 = Vector3.new(frame.velocity.x, frame.velocity.y, frame.velocity.z)
            local v2 = Vector3.new(nextFrame.velocity.x, nextFrame.velocity.y, nextFrame.velocity.z)
            local avgSpeed = (v1.Magnitude + v2.Magnitude) / 2
            local delta = 0.016
            if avgSpeed > 0.1 and dist > 0.01 then
                delta = dist / avgSpeed
                delta = math.max(delta, 0.016)
                delta = math.min(delta, 0.1)
            end
            currentTime = currentTime + delta
        end
    end

    local outName = "MergedNoJeda_" .. os.date("%d%m%y_%H%M%S")
    local outFile = DATA_FOLDER .. "/" .. outName .. ".json"
    local outData = {
        name = outName,
        date = os.time(),
        version = VERSION,
        frames = mergedFrames,
        totalFrames = #mergedFrames,
        duration = mergedFrames[#mergedFrames].time,
        merged = true,
        noJeda = true,
    }
    local ok, err = pcall(function() writefile(outFile, HttpService:JSONEncode(outData)) end)
    if ok then
        notif(string.format("🔗 Merge tanpa jeda: %d CP, %d frame (lintasan asli)", #cpDataList, #mergedFrames), Color3.fromRGB(100,255,150))
        refreshRecords()
        if renderList then renderList() end
    else
        notif("❌ Gagal: "..tostring(err), Color3.fromRGB(255,100,100))
    end
end

-- ==================== CLEANUP TOTAL ====================
local function cleanupAll()
    if isRecording then
        isRecording = false
        if recordHB then recordHB:Disconnect(); recordHB = nil end
        showRecordingIndicator(false)
        local hum = getHum()
        if hum then hum.AutoRotate = true end
    end
    if isPlaying then
        isPlaying = false
        isPaused = false
        if walkHB then walkHB:Disconnect(); walkHB = nil end
        local hrp = getHRP()
        local hum = getHum()
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        if hum then
            hum.AutoRotate = true
            hum.WalkSpeed = originalWalkSpeed
            hum.JumpPower = originalJumpPower
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end
    if recordingIndicator then
        recordingIndicator:Destroy()
        recordingIndicator = nil
    end
    local gui = LP.PlayerGui:FindFirstChild("BiannHUBRecorder")
    if gui then gui:Destroy() end
    guiFrame = nil
    notifLabel = nil
end

-- ==================== GUI DENGAN LAYOUT RAPAT ====================
local function createGUI()
    local old = LP.PlayerGui:FindFirstChild("BiannHUBRecorder")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BiannHUBRecorder"
    gui.ResetOnSpawn = false
    gui.Parent = LP:WaitForChild("PlayerGui")

    local W, H = 300, 470  -- tinggi sudah pas tanpa space kosong
    originalHeight = H
    
    local frame = Instance.new("Frame", gui)
    frame.BackgroundColor3 = Color3.fromRGB(10,10,14)
    frame.BorderSizePixel = 0
    frame.Position = UDim2.new(0.5,-W/2,0.5,-H/2)
    frame.Size = UDim2.new(0,W,0,H)
    frame.Active = true
    frame.Draggable = true
    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0,12)
    frameCorner.Parent = frame
    guiFrame = frame

    local fs = Instance.new("UIStroke", frame)
    fs.Color = Color3.fromRGB(0,180,255)
    fs.Thickness = 1.5

    -- Title bar
    local titleBar = Instance.new("Frame", frame)
    titleBar.BackgroundColor3 = Color3.fromRGB(0,120,180)
    titleBar.BorderSizePixel = 0
    titleBar.Size = UDim2.new(1,0,0,36)
    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0,12)
    titleBarCorner.Parent = titleBar

    local titleLbl = Instance.new("TextLabel", titleBar)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.new(0,12,0,0)
    titleLbl.Size = UDim2.new(1,-80,1,0)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.Text = "📼 BiannHUB R3CORD3R ( ARTHUR )"
    titleLbl.TextColor3 = Color3.fromRGB(255,255,255)
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Tombol Minimize
    local minBtn = Instance.new("TextButton", titleBar)
    minBtn.BackgroundColor3 = Color3.fromRGB(80,80,100)
    minBtn.BorderSizePixel = 0
    minBtn.Position = UDim2.new(1,-62,0,6)
    minBtn.Size = UDim2.new(0,24,0,24)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255,255,255)
    minBtn.TextSize = 16
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0,6)
    minCorner.Parent = minBtn

    -- Tombol Close
    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Position = UDim2.new(1,-32,0,6)
    closeBtn.Size = UDim2.new(0,24,0,24)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
    closeBtn.TextSize = 12
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0,6)
    closeCorner.Parent = closeBtn

    -- Container untuk semua konten
    local contentContainer = Instance.new("Frame", frame)
    contentContainer.BackgroundTransparency = 1
    contentContainer.Position = UDim2.new(0,0,0,36)
    contentContainer.Size = UDim2.new(1,0,1,-36)
    
    -- ========== KOMPONEN GUI (Y diatur rapat dari 0) ==========
    local function mkBtn(x,y,w,h,text,r,g,b)
        local btn = Instance.new("TextButton", contentContainer)
        btn.BackgroundColor3 = Color3.fromRGB(r,g,b)
        btn.BorderSizePixel = 0
        btn.Position = UDim2.new(0,x,0,y)
        btn.Size = UDim2.new(0,w,0,h)
        btn.Font = Enum.Font.GothamBold
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.TextSize = 11
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0,6)
        btnCorner.Parent = btn
        return btn
    end

    local function mkDiv(y)
        local d = Instance.new("Frame", contentContainer)
        d.BackgroundColor3 = Color3.fromRGB(25,35,50)
        d.BorderSizePixel = 0
        d.Position = UDim2.new(0,12,0,y)
        d.Size = UDim2.new(1,-24,0,1.5)
    end

    local function mkLbl(y,text)
        local lbl = Instance.new("TextLabel", contentContainer)
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0,12,0,y)
        lbl.Size = UDim2.new(1,-24,0,16)
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(0,180,255)
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
    end

    -- Mulai dari Y=0 (tanpa jarak)
    mkLbl(0, "REKAM")
    local recBtn = mkBtn(12,18,132,32,"🔴 REC",170,35,35)
    local stpBtn = mkBtn(152,18,136,32,"⏹ SAVE",25,130,70)

    local recStatus = Instance.new("TextLabel", contentContainer)
    recStatus.BackgroundTransparency = 1
    recStatus.Position = UDim2.new(0,12,0,54)
    recStatus.Size = UDim2.new(1,-24,0,14)
    recStatus.Font = Enum.Font.Gotham
    recStatus.Text = "Siap | F = Record"
    recStatus.TextColor3 = Color3.fromRGB(100,255,150)
    recStatus.TextSize = 10
    recStatus.TextXAlignment = Enum.TextXAlignment.Left

    mkDiv(72)

    mkLbl(80, "PLAYBACK")
    local playStartBtn = mkBtn(12,96,86,30,"▶ START",25,155,85)
    local playNearestBtn = mkBtn(104,96,86,30,"📍 NEAREST",0,130,70)
    local pauseBtn = mkBtn(196,96,92,30,"⏸ PAUSE",180,120,20)
    local stopBtn2 = mkBtn(12,132,86,30,"⏹ STOP",160,40,40)
    local loopBtn = mkBtn(104,132,86,30,"🔁 LOOP: OFF",35,35,55)
    local savePosBtn = mkBtn(12,168,86,26,"💾 Save Pos",30,100,30)
    local loadPosBtn = mkBtn(104,168,86,26,"📂 Load Pos",30,80,120)

    mkDiv(200)
    mkLbl(206, "REKAMAN")
    local refreshBtn = mkBtn(208,204,80,20,"🔄",25,50,90)

    local listFrame = Instance.new("ScrollingFrame", contentContainer)
    listFrame.BackgroundColor3 = Color3.fromRGB(14,14,20)
    listFrame.BorderSizePixel = 0
    listFrame.Position = UDim2.new(0,12,0,228)
    listFrame.Size = UDim2.new(1,-24,0,150)
    listFrame.ScrollBarThickness = 4
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(0,160,230)
    listFrame.CanvasSize = UDim2.new(0,0,0,0)
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0,6)
    listCorner.Parent = listFrame

    local ll = Instance.new("UIListLayout", listFrame)
    ll.Padding = UDim.new(0,3)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    local lp2 = Instance.new("UIPadding", listFrame)
    lp2.PaddingTop = UDim.new(0,6)
    lp2.PaddingLeft = UDim.new(0,6)
    lp2.PaddingRight = UDim.new(0,6)

    mkDiv(388)
    local mergeBtn = mkBtn(12,394,100,32,"🔗 MERGE & COMP",0,100,160)

    notifLabel = Instance.new("TextLabel", contentContainer)
    notifLabel.BackgroundColor3 = Color3.fromRGB(0,80,150)
    notifLabel.BorderSizePixel = 0
    notifLabel.Position = UDim2.new(0,12,0,430)
    notifLabel.Size = UDim2.new(1,-24,0,36)
    notifLabel.Font = Enum.Font.Gotham
    notifLabel.Text = ""
    notifLabel.TextColor3 = Color3.fromRGB(255,255,255)
    notifLabel.TextSize = 10
    notifLabel.TextWrapped = true
    notifLabel.Visible = false
    local notifCorner = Instance.new("UICorner")
    notifCorner.CornerRadius = UDim.new(0,6)
    notifCorner.Parent = notifLabel

    -- ========== LIST RECORD ==========
    local rowCache = {}

    local function getLayoutOrder(recName)
        for i,n in ipairs(savedRecords) do if n == recName then return i end end
        return 9999
    end

    local function addEmptyLabel()
        local e = Instance.new("TextLabel", listFrame)
        e.Name = "__empty"
        e.BackgroundTransparency = 1
        e.Size = UDim2.new(1,-12,0,32)
        e.Font = Enum.Font.Gotham
        e.Text = "Belum ada rekaman"
        e.TextColor3 = Color3.fromRGB(70,80,100)
        e.TextSize = 11
    end

    local function addRowToList(recName)
        local isSel = (selectedRecord == recName)
        local row = Instance.new("Frame", listFrame)
        row.Name = "row_"..recName
        row.LayoutOrder = getLayoutOrder(recName)
        row.BackgroundColor3 = isSel and Color3.fromRGB(0,70,120) or Color3.fromRGB(20,20,30)
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1,-12,0,32)
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0,6)
        rowCorner.Parent = row
        rowCache[recName] = row

        local nb = Instance.new("TextButton", row)
        nb.BackgroundTransparency = 1
        nb.Position = UDim2.new(0,8,0,0)
        nb.Size = UDim2.new(1,-44,1,0)
        nb.Font = isSel and Enum.Font.GothamBold or Enum.Font.Gotham
        nb.Text = (isSel and "▶ " or "  ")..recName
        nb.TextColor3 = isSel and Color3.fromRGB(0,210,255) or Color3.fromRGB(160,175,200)
        nb.TextSize = 11
        nb.TextXAlignment = Enum.TextXAlignment.Left
        nb.TextTruncate = Enum.TextTruncate.AtEnd
        nb.MouseButton1Click:Connect(function()
            if selectedRecord and rowCache[selectedRecord] then
                local oldRow = rowCache[selectedRecord]
                if oldRow and oldRow.Parent then
                    oldRow.BackgroundColor3 = Color3.fromRGB(20,20,30)
                    local oldNb = oldRow:FindFirstChildOfClass("TextButton")
                    if oldNb then
                        oldNb.Font = Enum.Font.Gotham
                        oldNb.Text = "  "..selectedRecord
                        oldNb.TextColor3 = Color3.fromRGB(160,175,200)
                    end
                end
            end
            selectedRecord = recName
            row.BackgroundColor3 = Color3.fromRGB(0,70,120)
            nb.Font = Enum.Font.GothamBold
            nb.Text = "▶ "..recName
            nb.TextColor3 = Color3.fromRGB(0,210,255)
            loadRecord(recName)
        end)

        local db = Instance.new("TextButton", row)
        db.BackgroundColor3 = Color3.fromRGB(120,25,25)
        db.BorderSizePixel = 0
        db.Position = UDim2.new(1,-28,0,4)
        db.Size = UDim2.new(0,22,0,24)
        db.Font = Enum.Font.GothamBold
        db.Text = "🗑"
        db.TextSize = 11
        db.TextColor3 = Color3.fromRGB(255,255,255)
        local dbCorner = Instance.new("UICorner")
        dbCorner.CornerRadius = UDim.new(0,4)
        dbCorner.Parent = db
        db.MouseButton1Click:Connect(function()
            row:Destroy()
            rowCache[recName] = nil
            if selectedRecord == recName then selectedRecord = nil end
            local hasRows = false
            for _,c in pairs(listFrame:GetChildren()) do
                if c:IsA("Frame") then hasRows = true; break end
            end
            if not hasRows then addEmptyLabel() end
            task.spawn(function()
                deleteRecord(recName)
                for i,n in ipairs(savedRecords) do if n == recName then table.remove(savedRecords,i); break end end
            end)
        end)
    end

    renderList = function()
        for _,c in pairs(listFrame:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
        end
        rowCache = {}
        if #savedRecords == 0 then addEmptyLabel(); return end
        for _,recName in ipairs(savedRecords) do addRowToList(recName) end
    end

    updatePlaybackUI = function(playing) end

    -- Update status text periodik
    task.spawn(function()
        while gui and gui.Parent do
            if isRecording then
                recStatus.Text = string.format("🔴 %d frame  |  %.1fs", #recordedFrames, tick()-recordStartTime)
                recStatus.TextColor3 = Color3.fromRGB(255,90,90)
            elseif isPlaying and currentData then
                local pct = math.floor(playbackTime / (currentData.duration or 1) * 100)
                recStatus.Text = string.format("▶ %.1fs / %.1fs  (%d%%)", playbackTime, currentData.duration or 0, pct)
                recStatus.TextColor3 = Color3.fromRGB(80,220,130)
            else
                recStatus.Text = "✅ Siap | F = Record | ORDER DI BIO GUYS"
                recStatus.TextColor3 = Color3.fromRGB(100,255,150)
            end
            task.wait(0.2)
        end
    end)

    -- Event tombol
    recBtn.MouseButton1Click:Connect(startRecording)
    stpBtn.MouseButton1Click:Connect(function()
        if isRecording then stopRecording() end
        task.defer(function()
            local saved = saveRecording()
            if saved then refreshRecords(); renderList() end
        end)
    end)
    playStartBtn.MouseButton1Click:Connect(startPlaybackFromStart)
    playNearestBtn.MouseButton1Click:Connect(startPlaybackFromNearest)
    pauseBtn.MouseButton1Click:Connect(pausePlayback)
    stopBtn2.MouseButton1Click:Connect(stopPlayback)
    savePosBtn.MouseButton1Click:Connect(savePosition)
    loadPosBtn.MouseButton1Click:Connect(loadPosition)
    loopBtn.MouseButton1Click:Connect(function()
        isLooping = not isLooping
        loopBtn.Text = isLooping and "🔁 LOOP: ON" or "🔁 LOOP: OFF"
        loopBtn.BackgroundColor3 = isLooping and Color3.fromRGB(0,120,65) or Color3.fromRGB(35,35,55)
    end)
    refreshBtn.MouseButton1Click:Connect(function()
        refreshRecords()
        renderList()
        notif("🔄 Direfresh", Color3.fromRGB(130,190,255),1.5)
    end)
    mergeBtn.MouseButton1Click:Connect(mergeAndCompressAll)

    -- Minimize (collapse) logic
    local function toggleCollapse()
        if isCollapsed then
            frame.Size = UDim2.new(0, W, 0, originalHeight)
            contentContainer.Visible = true
            minBtn.Text = "—"
            isCollapsed = false
        else
            frame.Size = UDim2.new(0, W, 0, 36)
            contentContainer.Visible = false
            minBtn.Text = "□"
            isCollapsed = true
        end
    end
    minBtn.MouseButton1Click:Connect(toggleCollapse)

    -- Close total
    closeBtn.MouseButton1Click:Connect(cleanupAll)

    refreshRecords()
    renderList()
end

-- ==================== CHARACTER ADDED ====================
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    local hum = getHum()
    if hum then
        hum.AutoRotate = true
        hum.JumpPower = 50
        hum.WalkSpeed = 16
    end
    if isPlaying then stopPlayback() end
    if isRecording then stopRecording() end
end)

-- ==================== KEYBIND F ====================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        if isRecording then
            stopRecording()
            if guiFrame then guiFrame.Visible = true end
        else
            startRecording()
            if guiFrame then guiFrame.Visible = false end
        end
    end
end)

-- ==================== START ====================
createGUI()
refreshRecords()
showRecordingIndicator(false)
