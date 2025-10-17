-- StarterPlayerScripts/TrainingCamera.client.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("Remotes")
local EvFocus   = Remotes:WaitForChild("TrainingCameraFocus")
local EvRestore = Remotes:WaitForChild("TrainingCameraRestore")
local EvFail    = Remotes:FindFirstChild("TrainingCameraFail") -- opcional

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera

local state = {
	active = false,
	mode = "follow",
	stopToken = 0,
	restoreConn = nil,
}

local function setSubjectEnabled(enabled: boolean)
	if enabled then
		cam.CameraType = Enum.CameraType.Custom
	else
		cam.CameraType = Enum.CameraType.Scriptable
	end
end

local function lerp(a, b, t) return a + (b - a) * t end

local function computeOrbitCF(targetCF: CFrame, radius: number, height: number, yawDeg: number)
	local base = targetCF * CFrame.new(0, height, 0) * CFrame.Angles(0, math.rad(yawDeg), 0)
	return base * CFrame.new(0, 0, radius)
end

local function getLookCF(fromPos: Vector3, toPos: Vector3)
	return CFrame.new(fromPos, toPos)
end

local function getTargetCF(targetModel: Model)
	local root = targetModel and (targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart)
	return root and root.CFrame or CFrame.new()
end

local function tweenFOV(toFov: number, dur: number)
	if not toFov then return end
	pcall(function()
		TweenService:Create(cam, TweenInfo.new(dur or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = toFov}):Play()
	end)
end

-- Orbital take (one shot). Moves camera for duration while orbiting.
local function playOrbit(target: Model, opt)
	opt = opt or {}
	local dur = tonumber(opt.duration) or 1.0
	local radius = tonumber(opt.radius) or 10
	local height = tonumber(opt.height) or 4
	local yawOffset = tonumber(opt.yawOffsetDeg) or 0
	local fov = opt.fov

	state.stopToken += 1
	local token = state.stopToken

	setSubjectEnabled(false)
	state.active = true
	if fov then tweenFOV(fov, 0.2) end

	local t0 = os.clock()
	local baseYaw = yawOffset
	local yawSpeed = tonumber(opt.angularSpeedDeg) or 0

	local heartbeatConn
	heartbeatConn = RunService.RenderStepped:Connect(function()
		if token ~= state.stopToken then heartbeatConn:Disconnect() return end
		local t = os.clock() - t0
		local tf = math.clamp(t / dur, 0, 1)

		local tgtCF = getTargetCF(target)
		local yawNow = baseYaw + yawSpeed * t
		local camPosCF = computeOrbitCF(tgtCF, radius, height, yawNow)
		cam.CFrame = getLookCF(camPosCF.Position, tgtCF.Position)

		if tf >= 1 then
			heartbeatConn:Disconnect()
		end
	end)

	task.delay(dur + 0.05, function()
		-- mantém scriptable até o próximo foco/restauração
	end)
end

-- Fail cinematic: orbit + zoom in/out along time
local function playFailCinematic(target: Model, opt)
	opt = opt or {}
	local dur = tonumber(opt.duration) or 1.3
	local r0  = tonumber(opt.radiusStart) or 12
	local r1  = tonumber(opt.radiusEnd)   or  9
	local h0  = tonumber(opt.heightStart) or  6
	local h1  = tonumber(opt.heightEnd)   or  7.5
	local yawSpeed = tonumber(opt.angularSpeedDeg) or 55
	local fov0 = tonumber(opt.fovStart) or 70
	local fov1 = tonumber(opt.fovEnd)   or 62
	local easeTime = tonumber(opt.easeTime) or 0.25

	state.stopToken += 1
	local token = state.stopToken

	setSubjectEnabled(false)
	state.active = true
	tweenFOV(fov0, 0.01)

	local t0 = os.clock()
	local heartbeatConn
	heartbeatConn = RunService.RenderStepped:Connect(function()
		if token ~= state.stopToken then heartbeatConn:Disconnect() return end
		local t = os.clock() - t0
		local tf = math.clamp(t / dur, 0, 1)

		local tgtCF = getTargetCF(target)
		local radius = lerp(r0, r1, tf)
		local height = lerp(h0, h1, tf)
		local yaw = yawSpeed * t
		local camPosCF = computeOrbitCF(tgtCF, radius, height, yaw)
		cam.CFrame = getLookCF(camPosCF.Position, tgtCF.Position)

		-- FOV lerp manual para não brigar com outros tweens
		cam.FieldOfView = lerp(fov0, fov1, math.clamp(t / math.max(easeTime, 0.01), 0, 1))

		if tf >= 1 then
			heartbeatConn:Disconnect()
		end
	end)
end

-- ===== Remotes =====

EvFocus.OnClientEvent:Connect(function(monster: Model, trainingName: string, payload: table?)
	-- payload esperado do servidor (RockSmash/BoulderCarry): mode="orbit", duration, radius, height, yawOffsetDeg, fov
	local p = payload or {}
	if p.mode == "orbit" then
		playOrbit(monster, p)
	else
		-- fallback: foco simples
		setSubjectEnabled(false)
		local cf = getTargetCF(monster)
		cam.CFrame = getLookCF(cf.Position + Vector3.new(-8, 6, -8), cf.Position)
		tweenFOV(p.fov or 70, 0.2)
	end
end)

if EvFail then
	EvFail.OnClientEvent:Connect(function(monster: Model, payload: table?)
		playFailCinematic(monster, payload or {})
	end)
end

EvRestore.OnClientEvent:Connect(function()
	state.stopToken += 1
	state.active = false
	tweenFOV(70, 0.2)
	setSubjectEnabled(true)
end)
