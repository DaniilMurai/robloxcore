--!strict
-- Procedural HUD: balance, income, rebirth state and one button per upgrade. Built from
-- code rather than a .rbxm so a title's screen changes with its config, not by hand.

local Types = require("../logic/types")
local Economy = require("../logic/economy")
local Progression = require("../logic/progression")

type TitleConfig = Types.TitleConfig
type StateSnapshot = Types.StateSnapshot
type Action = Types.Action

local BACKDROP = Color3.fromRGB(18, 20, 26)
local ACCENT = Color3.fromRGB(96, 205, 255)
local MUTED = Color3.fromRGB(150, 156, 168)
local DENIED = Color3.fromRGB(226, 96, 96)

local Hud = {}
Hud.__index = Hud

local function label(parent: Instance, size: UDim2, text: string, color: Color3): TextLabel
	local text_label = Instance.new("TextLabel")
	text_label.Size = size
	text_label.BackgroundTransparency = 1
	text_label.Text = text
	text_label.TextColor3 = color
	text_label.TextXAlignment = Enum.TextXAlignment.Left
	text_label.TextScaled = true
	text_label.Font = Enum.Font.GothamBold
	text_label.Parent = parent
	return text_label
end

function Hud.new(config: TitleConfig, onAction: (action: Action) -> ())
	return setmetatable({
		_config = config,
		_onAction = onAction,
		_upgradeButtons = {},
		_passButtons = {},
		_snapshot = nil,
	}, Hud)
end

function Hud:mount(parent: Instance)
	local config: TitleConfig = self._config
	local currency = config.currencies[1]

	local screen = Instance.new("ScreenGui")
	screen.Name = "HUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 96)
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.BackgroundColor3 = BACKDROP
	panel.BackgroundTransparency = 0.15
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	self._balance = label(panel, UDim2.new(1, -24, 0, 40), "0", ACCENT)
	self._balance.Position = UDim2.new(0, 12, 0, 8)
	self._income = label(panel, UDim2.new(1, -24, 0, 24), "+0/s", MUTED)
	self._income.Position = UDim2.new(0, 12, 0, 52)

	local buttons = Instance.new("Frame")
	buttons.Size = UDim2.new(0, 320, 0, 56 * (#config.upgrades + #config.passes + 1))
	buttons.Position = UDim2.new(0, 16, 0, 124)
	buttons.BackgroundTransparency = 1
	buttons.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = buttons

	for _, def in config.upgrades do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 48)
		button.BackgroundColor3 = BACKDROP
		button.BackgroundTransparency = 0.15
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextScaled = true
		button.Font = Enum.Font.GothamBold
		button.Text = def.name
		button.Parent = buttons

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 10)
		buttonCorner.Parent = button

		button.Activated:Connect(function()
			self._onAction({ kind = "BuyUpgrade", upgradeId = def.id })
		end)
		self._upgradeButtons[def.id] = button
	end

	for _, def in config.passes do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 48)
		button.BackgroundColor3 = BACKDROP
		button.BackgroundTransparency = 0.15
		button.TextColor3 = ACCENT
		button.TextScaled = true
		button.Font = Enum.Font.GothamBold
		button.Text = def.id
		button.Parent = buttons

		local passCorner = Instance.new("UICorner")
		passCorner.CornerRadius = UDim.new(0, 10)
		passCorner.Parent = button

		button.Activated:Connect(function()
			self._onAction({ kind = "PromptPass", passId = def.id })
		end)
		self._passButtons[def.id] = button
	end

	local rebirth = Instance.new("TextButton")
	rebirth.Size = UDim2.new(1, 0, 0, 48)
	rebirth.BackgroundColor3 = BACKDROP
	rebirth.BackgroundTransparency = 0.15
	rebirth.TextColor3 = ACCENT
	rebirth.TextScaled = true
	rebirth.Font = Enum.Font.GothamBold
	rebirth.Text = "Rebirth"
	rebirth.Parent = buttons
	rebirth.Activated:Connect(function()
		self._onAction({ kind = "Rebirth" })
	end)

	local rebirthCorner = Instance.new("UICorner")
	rebirthCorner.CornerRadius = UDim.new(0, 10)
	rebirthCorner.Parent = rebirth

	self._rebirth = rebirth
	self._currencyShort = currency.short
	screen.Parent = parent
	return screen
end

function Hud:update(snapshot: StateSnapshot)
	local config: TitleConfig = self._config
	local currency = config.currencies[1]
	local balance = snapshot.wallet[currency.id] or 0

	self._snapshot = snapshot
	self._balance.Text = ("%d %s"):format(balance, self._currencyShort)
	self._income.Text = ("+%.1f/s · rebirth %d"):format(snapshot.incomePerSecond, snapshot.rebirths)

	for _, def in config.upgrades do
		local button = self._upgradeButtons[def.id]
		local level = snapshot.upgrades[def.id] or 0
		if level >= def.maxLevel then
			button.Text = ("%s · MAX"):format(def.name)
			button.TextColor3 = MUTED
		else
			local cost = Economy.upgradeCost(def, level)
			button.Text = ("%s lvl %d · %d"):format(def.name, level, cost)
			-- Affordability is shown, not enforced: the server recomputes the cost anyway,
			-- and a client-side lock would only hide the InsufficientFunds feedback.
			button.TextColor3 = if balance >= cost then Color3.new(1, 1, 1) else MUTED
		end
	end

	local owned: { [string]: boolean } = {}
	for _, passId in snapshot.ownedPassIds do
		owned[passId] = true
	end
	for _, def in config.passes do
		local button = self._passButtons[def.id]
		if button then
			button.Text = if owned[def.id] then `{def.id} · owned` else `{def.id} · buy`
			button.TextColor3 = if owned[def.id] then MUTED else ACCENT
		end
	end

	local cost = Progression.rebirthCost(config, snapshot.rebirths)
	local threshold = snapshot.wallet[config.rebirth.requirement.currency] or 0
	self._rebirth.Text = ("Rebirth · %d"):format(cost)
	self._rebirth.TextColor3 = if threshold >= cost then ACCENT else MUTED
end

-- Refusals surface on the button that caused them and fade back on the next update:
-- a snapshot arrives at least every heartbeat, so nothing stays red for long.
function Hud:deny(action: Action, code: string)
	local button = if action.kind == "BuyUpgrade"
		then self._upgradeButtons[action.upgradeId]
		else self._rebirth
	if button then
		button.Text = code
		button.TextColor3 = DENIED
	end
end

return Hud
