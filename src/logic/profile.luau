--!strict
-- Player profile: creation, schema migration, idempotent product grants.
-- Pure — no Roblox globals, no clock reads: `now` arrives as a parameter (S-03).

local Types = require("./types")
local Result = require("./result")
local Economy = require("./economy")

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type ProductDef = Types.ProductDef
type Result<T> = Result.Result<T>

local SCHEMA_VERSION = Types.SCHEMA_VERSION

local Profile = {}

-- contracts.md's Profile.new(config) can't stamp stats.firstJoinAt without reading the
-- clock, which the pure layer forbids; keeping the slice's `now` parameter until the
-- contract is amended (flagged for stage 9).
function Profile.new(config: TitleConfig, now: number): ProfileData
	local wallet = {}
	for _, currency in config.currencies do
		wallet[currency.id] = currency.starting
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		wallet = wallet,
		upgrades = {},
		rebirths = 0,
		zones = {},
		processedReceipts = {},
		stats = {
			firstJoinAt = now,
			lastSeenAt = now,
			playtimeSeconds = 0,
			totalEarned = {},
		},
	}
end

-- A profile written by a newer build must not be silently downgraded: that is how a
-- rollback eats player progress, so newer-than-current stays a hard SchemaTooNew.
function Profile.migrate(raw: any): Result<ProfileData>
	if type(raw) ~= "table" then
		return Result.err("ProfileCorrupt", ("expected a table, got %s"):format(type(raw)))
	end

	local version = raw.schemaVersion
	if type(version) ~= "number" then
		return Result.err("ProfileCorrupt", "missing or non-numeric schemaVersion")
	end

	if version > SCHEMA_VERSION then
		return Result.err("SchemaTooNew", ("v%d > v%d"):format(version, SCHEMA_VERSION))
	end

	if version == SCHEMA_VERSION then
		return Result.ok(raw :: ProfileData)
	end

	-- Steps are cumulative and each one only adds what its version introduced, so a v1 save
	-- from a year ago walks the same path as a fresh one. The raw table is copied, never
	-- edited in place: the caller still holds it if a later step fails.
	local migrated = table.clone(raw)

	if version == 1 then
		-- v2 added zones. An old save owns none, which is exactly what a fresh profile has.
		migrated.zones = {}
		version = 2
	end

	if version ~= SCHEMA_VERSION then
		return Result.err("ProfileCorrupt", ("no migration path from schema v%d"):format(raw.schemaVersion))
	end

	migrated.schemaVersion = SCHEMA_VERSION
	return Result.ok(migrated :: ProfileData)
end

function Profile.applyProductGrant(
	profile: ProfileData,
	def: ProductDef,
	receiptId: string,
	now: number
): Result<ProfileData>
	if profile.processedReceipts[receiptId] ~= nil then
		return Result.err("ReceiptAlreadyProcessed", receiptId)
	end

	-- Economy.earn owns the lifetime totalEarned bookkeeping; duplicating the wallet write
	-- here would drift the two apart the next time earn's accounting changes.
	local earned = Economy.earn(profile, def.grant.currency, def.grant.amount)
	if not earned.ok then
		return earned
	end

	local updated = table.clone(earned.value)
	updated.processedReceipts = table.clone(earned.value.processedReceipts)
	updated.processedReceipts[receiptId] = now
	return Result.ok(updated)
end

-- Strictly-older receipts are dropped; a receipt exactly maxAgeSeconds old survives, since
-- Roblox may still resend a chargeback/receipt at that exact boundary.
function Profile.pruneReceipts(profile: ProfileData, now: number, maxAgeSeconds: number): ProfileData
	local updated = table.clone(profile)
	updated.processedReceipts = {}
	for receiptId, grantedAt in profile.processedReceipts do
		if now - grantedAt <= maxAgeSeconds then
			updated.processedReceipts[receiptId] = grantedAt
		end
	end
	return updated
end

function Profile.touch(profile: ProfileData, now: number): ProfileData
	local elapsed = math.max(0, now - profile.stats.lastSeenAt)
	local updated = table.clone(profile)
	updated.stats = table.clone(profile.stats)
	updated.stats.lastSeenAt = now
	updated.stats.playtimeSeconds += elapsed
	return updated
end

return Profile
