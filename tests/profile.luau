--!strict

local Profile = require("../src/logic/profile")
local Config = require("../src/logic/config")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local function newProfile(wallet: { [string]: number }, processedReceipts: { [string]: number })
	return {
		schemaVersion = 1,
		wallet = wallet,
		upgrades = {},
		rebirths = 0,
		processedReceipts = processedReceipts,
		stats = {
			firstJoinAt = 0,
			lastSeenAt = 0,
			playtimeSeconds = 0,
			totalEarned = {},
		},
	}
end

return function(t)
	local fixture = serde.decode("json", fs.readFile("tests/fixtures/main.json"))
	local validated = Config.validate(fixture)
	assert(validated.ok, "fixture config must validate")
	local config = validated.value

	local product = {
		id = "starter_pack",
		productId = 111,
		grant = { currency = "coins", amount = 50 },
	}

	-- Profile.new

	local fresh = Profile.new(config, 1000)
	t:eq("new sets schemaVersion", fresh.schemaVersion, 1)
	t:eq("new fills wallet with starting balance of each configured currency", fresh.wallet.coins, 0)
	t:eq("new sets rebirths to 0", fresh.rebirths, 0)
	t:eq("new starts with no processed receipts", next(fresh.processedReceipts), nil)
	t:eq("new stamps stats.firstJoinAt with now", fresh.stats.firstJoinAt, 1000)
	t:eq("new stamps stats.lastSeenAt with now", fresh.stats.lastSeenAt, 1000)
	t:eq("new starts playtimeSeconds at 0", fresh.stats.playtimeSeconds, 0)
	t:eq("new starts totalEarned empty", next(fresh.stats.totalEarned), nil)

	-- Profile.applyProductGrant: first grant

	local before = newProfile({ coins = 10 }, {})
	local granted = Profile.applyProductGrant(before, product, "receipt-1", 500)
	t:check("first applyProductGrant succeeds", granted.ok)
	if granted.ok then
		t:eq("applyProductGrant adds exactly grant.amount", granted.value.wallet.coins, 60)
		t:eq(
			"applyProductGrant records the receipt at now",
			granted.value.processedReceipts["receipt-1"],
			500
		)
	end
	t:eq("applyProductGrant does not mutate input wallet", before.wallet.coins, 10)
	t:eq("applyProductGrant does not mutate input processedReceipts", next(before.processedReceipts), nil)

	-- Profile.applyProductGrant: duplicate receipt

	local withReceipt = newProfile({ coins = 10 }, { ["receipt-1"] = 500 })
	local duplicate = Profile.applyProductGrant(withReceipt, product, "receipt-1", 900)
	t:errs("duplicate receiptId is ReceiptAlreadyProcessed", duplicate, "ReceiptAlreadyProcessed")

	local unwrapped = withReceipt :: any
	t:eq("duplicate receipt does not change the balance", unwrapped.wallet.coins, 10)

	-- Profile.applyProductGrant: unknown currency bubbles up from Economy.earn

	local badProduct = { id = "bad", productId = 222, grant = { currency = "gems", amount = 10 } }
	local unknown = Profile.applyProductGrant(newProfile({ coins = 0 }, {}), badProduct, "receipt-2", 0)
	t:errs(
		"grant with unknown currency bubbles UnknownCurrency from Economy.earn",
		unknown,
		"UnknownCurrency"
	)

	-- Profile.migrate

	local currentVersion = Profile.migrate({ schemaVersion = 1, wallet = {}, processedReceipts = {} })
	t:check("migrate accepts the current schema version", currentVersion.ok)

	local tooNew = Profile.migrate({ schemaVersion = 999, wallet = {} })
	t:errs("migrate with a newer schemaVersion is SchemaTooNew", tooNew, "SchemaTooNew")

	local garbage = Profile.migrate("not a table")
	t:check("migrate on a non-table raw is an Err", garbage.ok == false)

	-- Profile.pruneReceipts

	local ninetyDays = 90 * 24 * 60 * 60
	local now = 10_000_000
	local withReceipts = newProfile({ coins = 0 }, {
		fresh = now - 10,
		exactlyBoundary = now - ninetyDays,
		stale = now - ninetyDays - 1,
	})
	local pruned = Profile.pruneReceipts(withReceipts, now, ninetyDays)
	t:check("pruneReceipts keeps a fresh receipt", pruned.processedReceipts.fresh ~= nil)
	t:check(
		"pruneReceipts keeps a receipt exactly at the boundary",
		pruned.processedReceipts.exactlyBoundary ~= nil
	)
	t:check("pruneReceipts drops a receipt older than maxAgeSeconds", pruned.processedReceipts.stale == nil)
	t:check(
		"pruneReceipts does not mutate the input profile's receipts",
		withReceipts.processedReceipts.stale ~= nil
	)

	-- Profile.touch

	local touchable = newProfile({ coins = 0 }, {})
	touchable.stats.lastSeenAt = 100
	local touched = Profile.touch(touchable, 150)
	t:eq("touch advances lastSeenAt to now", touched.stats.lastSeenAt, 150)
	t:eq("touch accumulates elapsed time into playtimeSeconds", touched.stats.playtimeSeconds, 50)
	t:eq("touch does not mutate the input profile", touchable.stats.lastSeenAt, 100)
end
