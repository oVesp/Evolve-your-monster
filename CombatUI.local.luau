local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local UIB = require(RS.Modules.UIBillboards)
local UI = RS.Remotes.CombatUI
local HealthUpdate = UI:WaitForChild("HealthUpdate")
local TargetUpdate = UI:WaitForChild("TargetUpdate")
local AttackBanner = UI:WaitForChild("AttackBanner")

-- Garante HUD local (Opção 1)
UIB.EnsureCombatHUD(player)

-- Opção 2 (auto-attach): quando um mob aparecer, anexamos HP + Arrow
workspace.ChildAdded:Connect(function(obj)
	print("1")
	if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
		print("2")
		if obj.Parent == workspace then
			local isMine = obj:GetAttribute("OwnerId") == player.UserId
			if isMine or obj:GetAttribute("Team") then
				UIB.AttachHpBar(obj)
				UIB.AttachTeamArrow(obj, isMine)	
			end
		end
	end
end)

-- Atualiza HUD quando hp mudar
HealthUpdate.OnClientEvent:Connect(function(model, cur, max)
	-- Decide se é minha barra esquerda ou a direita (target)
	local isMine = model and (model:GetAttribute("OwnerId") == player.UserId)
	if isMine then
		UIB.UpdateHUDFor(player, model, nil, cur, max)
	else
		UIB.UpdateHUDFor(player, nil, model, nil, nil, cur, max)
	end
end)

-- Quando o alvo do meu monstro muda (jit real time)
TargetUpdate.OnClientEvent:Connect(function(myModel, newTarget)
	-- Atualiza nomes e futura barra direita
	local hum = myModel and myModel:FindFirstChildOfClass("Humanoid")
	local maxMy = hum and hum.MaxHealth or (myModel and myModel:GetAttribute("Hp") or 100)
	local curMy = hum and hum.Health or (myModel and myModel:GetAttribute("Hp") or maxMy)
	local th = newTarget and newTarget:FindFirstChildOfClass("Humanoid")
	local maxT = th and th.MaxHealth or (newTarget and newTarget:GetAttribute("Hp") or 100)
	local curT = th and th.Health or (newTarget and newTarget:GetAttribute("Hp") or maxT)
	UIB.UpdateHUDFor(player, myModel, newTarget, curMy, maxMy, curT, maxT)
end)

-- Banner de ataque + som custom do mob
AttackBanner.OnClientEvent:Connect(function(attackerModel, moveName, sfxName)
	UIB.SpawnAttackBanner(attackerModel, tostring(moveName or "ATTACK!"))
	if _G.EFFECTS and _G.EFFECTS.PlaySound then
		_G.EFFECTS.PlaySound(sfxName or "DefaultImpact", { Where = attackerModel })
	end
end)
