--!strict
-- MarketplaceService wrapper. Ownership is asked of the platform on every join instead of
-- being stored in the profile: that is what keeps a re-join from granting a pass twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Packages = script.Parent.Parent
local Types = require(Packages.logic.types)

type TitleConfig = Types.TitleConfig

export type MarketAdapter = {
	ownedPassIds: (self: MarketAdapter, userId: number) -> { string },
	promptPass: (self: MarketAdapter, player: Player, passId: string) -> (),
	promptProduct: (self: MarketAdapter, player: Player, productId: string) -> (),
	onReceipt: (
		self: MarketAdapter,
		handler: (userId: number, productId: string, receiptId: string) -> boolean
	) -> (),
	forget: (self: MarketAdapter, userId: number) -> (),
}

local MarketplaceAdapter = {}
MarketplaceAdapter.__index = MarketplaceAdapter

function MarketplaceAdapter.new(config: TitleConfig): MarketAdapter
	local self = setmetatable({
		_config = config,
		_owned = {}, -- userId -> { passId -> true }
	}, MarketplaceAdapter)

	-- UserOwnsGamePassAsync answers from a cache that does not refresh mid-session, so a
	-- pass bought while playing stays invisible until this signal updates our own table.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for _, def in config.passes do
			if def.gamepassId == gamepassId then
				local owned = self._owned[player.UserId]
				if owned then
					owned[def.id] = true
				end
			end
		end
	end)

	return (self :: any) :: MarketAdapter
end

function MarketplaceAdapter:ownedPassIds(userId: number): { string }
	local owned = self._owned[userId]
	if owned == nil then
		owned = {}
		for _, def in self._config.passes do
			-- One failed call must not cost the player every other pass they own.
			local ok, hasPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(userId, def.gamepassId)
			end)
			if ok and hasPass then
				owned[def.id] = true
			end
		end
		self._owned[userId] = owned
	end

	local ids = {}
	for passId in owned do
		table.insert(ids, passId)
	end
	return ids
end

function MarketplaceAdapter:forget(userId: number)
	self._owned[userId] = nil
end

function MarketplaceAdapter:promptPass(player: Player, passId: string)
	for _, def in self._config.passes do
		if def.id == passId then
			MarketplaceService:PromptGamePassPurchase(player, def.gamepassId)
			return
		end
	end
end

function MarketplaceAdapter:promptProduct(player: Player, productId: string)
	for _, def in self._config.products do
		if def.id == productId then
			MarketplaceService:PromptProductPurchase(player, def.productId)
			return
		end
	end
end

-- The handler returns true only once the grant is saved. Anything else — an unknown
-- product, an absent player, a handler that threw — must stay NotProcessedYet so Roblox
-- resends the receipt later; PurchaseGranted on an unsaved grant is a paid item lost.
function MarketplaceAdapter:onReceipt(handler: (number, string, string) -> boolean)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local granted = Enum.ProductPurchaseDecision.PurchaseGranted
		local pending = Enum.ProductPurchaseDecision.NotProcessedYet

		local productId: string? = nil
		for _, def in self._config.products do
			if def.productId == receiptInfo.ProductId then
				productId = def.id
				break
			end
		end
		if productId == nil then
			return pending
		end

		if Players:GetPlayerByUserId(receiptInfo.PlayerId) == nil then
			return pending
		end

		local ok, accepted = pcall(handler, receiptInfo.PlayerId, productId, tostring(receiptInfo.PurchaseId))
		if ok and accepted then
			return granted
		end
		return pending
	end
end

return MarketplaceAdapter
