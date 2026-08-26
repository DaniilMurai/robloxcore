--!strict
-- Domain failures are values, not error(); error() stays reserved for programmer
-- mistakes (broken invariant, malformed config at startup) per contracts.md.

export type ErrorCode =
	"InsufficientFunds"
	| "UnknownUpgrade"
	| "MaxLevelReached"
	| "RebirthNotAffordable"
	| "UnknownCurrency"
	| "ConfigInvalid"
	| "ProfileNotLoaded"
	| "ProfileLocked"
	| "ProfileCorrupt"
	| "SchemaTooNew"
	| "DataStoreUnavailable"
	| "ReceiptAlreadyProcessed"
	| "UnknownProduct"
	| "UnknownZone"
	| "ZoneAlreadyOwned"
	| "UpgradeLocked"

export type Err = { ok: false, code: ErrorCode, message: string }
export type Ok<T> = { ok: true, value: T }
export type Result<T> = Ok<T> | Err

-- The set membership check below is why ErrorCode can't be a plain string param:
-- a caller passing a typo'd code fails loudly here instead of shipping a silent Err.
local VALID_CODES: { [string]: true } = {
	InsufficientFunds = true,
	UnknownUpgrade = true,
	MaxLevelReached = true,
	RebirthNotAffordable = true,
	UnknownCurrency = true,
	ConfigInvalid = true,
	ProfileNotLoaded = true,
	ProfileLocked = true,
	ProfileCorrupt = true,
	SchemaTooNew = true,
	DataStoreUnavailable = true,
	ReceiptAlreadyProcessed = true,
	UnknownProduct = true,
	UnknownZone = true,
	ZoneAlreadyOwned = true,
	UpgradeLocked = true,
}

local Result = {}

function Result.ok<T>(value: T): Ok<T>
	return { ok = true, value = value }
end

function Result.err(code: ErrorCode, message: string): Err
	if not VALID_CODES[code] then
		error(("Result.err: unknown ErrorCode %s"):format(tostring(code)))
	end
	return { ok = false, code = code, message = message }
end

return Result
