local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Cam = workspace.CurrentCamera
local LP = Players.LocalPlayer

local Remotes = RS:WaitForChild("Remotes")
local EvFocus   = Remotes:WaitForChild("TrainingCameraFocus")
local EvRestore = Remotes:WaitForChild("TrainingCameraRestore")
local EvFail    = Remotes:WaitForChild("TrainingCameraFail")

-- Estado
local mode = "none"              -- "follow" | "death" | "none"
local targetModel: Model? = nil
local connRS: RBXScriptConnection? = nil
local t0, dur = 0, 0
local orbitCfg = nil

local function headOrPivot(model: Model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	return model.PrimaryPart or model
end

local function stopLoop()
	if connRS then connRS:Disconnect(); connRS = nil end
end

local function restoreCamera()
	mode = "none"; targetModel = nil; orbitCfg = nil
	stopLoop()
	pcall(function() Cam.FieldOfView = 70 end)
	Cam.CameraType = Enum.CameraType.Custom
end

local SIDE_DIST   = 10   -- distância lateral
local SIDE_HEIGHT = 5.5  -- altura da câmera
local BACK_NUDGE  = 2.0  -- leve recuo para evitar “colar” no ombro

local function sideFollowCFrame(model: Model)
	if not model or not model.Parent then
		return Cam.CFrame
	end
	local ref = model:FindFirstChild("Head") or model.PrimaryPart or model
	local pivot = model:GetPivot()
	local right = pivot.RightVector         -- lateral
	local look  = pivot.LookVector          -- frente

	-- posição da câmera: ao lado + um leve recuo para abrir o plano
	local camPos = ref.Position
		+ (right * SIDE_DIST)
		+ Vector3.new(0, SIDE_HEIGHT, 0)
	- (look  * BACK_NUDGE)

	-- olhar para o centro do modelo (ou cabeça)
	return CFrame.new(camPos, ref.Position)
end

local function startFollow(model: Model)
	mode = "follow"; targetModel = model
	stopLoop()
	Cam.CameraType = Enum.CameraType.Scriptable
	pcall(function() Cam.FieldOfView = 70 end)

	connRS = RunService.RenderStepped:Connect(function(dt)
		if not targetModel or not targetModel.Parent then return end
		local desired = sideFollowCFrame(targetModel)
		Cam.CFrame = Cam.CFrame:Lerp(desired, 0.15)
	end)
end

-- === NOVO: Cinemática de morte (zoom + órbita Y) ===
local function startDeathCinematic(model: Model, cfg)
	mode = "death"; targetModel = model; orbitCfg = cfg or {}
	stopLoop()
	Cam.CameraType = Enum.CameraType.Scriptable

	-- parâmetros
	local radiusStart = tonumber(orbitCfg.radiusStart) or 12
	local radiusEnd   = tonumber(orbitCfg.radiusEnd)   or 9
	local heightStart = tonumber(orbitCfg.heightStart) or 6
	local heightEnd   = tonumber(orbitCfg.heightEnd)   or 7.5
	local angSpeedDeg = tonumber(orbitCfg.angularSpeedDeg) or 55
	local fovStart    = tonumber(orbitCfg.fovStart) or 70
	local fovEnd      = tonumber(orbitCfg.fovEnd)   or 62
	dur               = math.max(0.1, tonumber(orbitCfg.duration) or 1.5)
	local easeTime    = tonumber(orbitCfg.easeTime) or 0.25

	-- set FOV inicial e tween pro final
	pcall(function() Cam.FieldOfView = fovStart end)
	TweenService:Create(Cam, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fovEnd }):Play()

	-- tempo base e ângulo inicial olhando pro alvo
	t0 = time()
	local angle = 0

	-- tween de chegada (suave)
	local ref = headOrPivot(model)
	local lookPos = ref.Position
	local startPos = lookPos + Vector3.new(0, heightStart, -radiusStart)
	Cam.CFrame = Cam.CFrame:Lerp(CFrame.new(startPos, lookPos), 0.5)
	TweenService:Create(Cam, TweenInfo.new(easeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(startPos, lookPos) }
	):Play()

	-- loop de órbita
	connRS = RunService.RenderStepped:Connect(function(dt)
		if mode ~= "death" or not targetModel or not targetModel.Parent then return end
		local t = math.clamp((time() - t0) / dur, 0, 1)

		-- Lerp de raio e altura (zoom leve + subida)
		local radius = radiusStart + (radiusEnd - radiusStart) * t
		local height = heightStart + (heightEnd - heightStart) * t

		-- Incremento angular
		angle += math.rad(angSpeedDeg) * dt

		local center = headOrPivot(targetModel).Position
		local offset = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius * -1)
		local camPos = center + offset
		Cam.CFrame = CFrame.new(camPos, center)

		-- termina automaticamente ao fim
		if t >= 1 then
			-- não restaura aqui: o servidor chamará EvRestore quando o treino encerrar
			stopLoop()
		end
	end)
end

-- Eventos
EvFocus.OnClientEvent:Connect(function(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	startFollow(model)
end)

EvRestore.OnClientEvent:Connect(function()
	restoreCamera()
end)

EvFail.OnClientEvent:Connect(function(model, cfg)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	startDeathCinematic(model, cfg)
end)