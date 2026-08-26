--!strict
-- ProfileStore wrapper. The session lock itself is ProfileStore's job (S-03: the racy
-- network half is exactly what hand-rolled locks get wrong); this module only maps its
-- API onto the Result contract and owns the retry policy for forced saves.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local Types = require("../logic/types")
local Result = require("../logic/result")
local Profile = require("../logic/profile")

type ProfileData = Types.ProfileData
type TitleConfig = Types.TitleConfig
type Result<T> = Result.Result<T>

local RECEIPT_MAX_AGE = 90 * 24 * 60 * 60 -- Roblox never resends a receipt this old (S-03)

export type DataAdapter = {
	load: (self: DataAdapter, userId: number) -> Result<ProfileData>,
	-- Cheap: hands the new profile to ProfileStore's own autosave, no network call. Called
	-- on every mutation, which a forced save could not be — per-key writes are rate limited.
	sync: (self: DataAdapter, userId: number, profile: ProfileData) -> Result<true>,
	-- Yields until ProfileStore confirms the write, or until saveTimeoutSeconds passes.
	save: (self: DataAdapter, userId: number, profile: ProfileData) -> Result<true>,
	release: (self: DataAdapter, userId: number) -> (),
}

export type Options = {
	storeName: string,
	config: TitleConfig,
	autosaveSeconds: number,
	-- How long a forced save may wait for confirmation. ProfileStore retries the DataStore
	-- call itself with its own backoff, so this is a deadline, not an attempt count.
	saveTimeoutSeconds: number,
	staleAfterSeconds: number,
	-- Called from ProfileStore's Cancel handler: the adapter must not know about Players.
	isActive: (userId: number) -> boolean,
	-- Fired when ProfileStore drops the session under us (another server stole the lock).
	-- The player has to be kicked, or they keep playing a profile nobody is saving.
	onSessionEnd: ((userId: number) -> ())?,
}

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

function DataStoreAdapter.new(opts: Options): DataAdapter
	-- Both are ProfileStore-wide, not per-store. Autosave defaults to 300 s, so leaving it
	-- alone means up to five minutes of lost progress on a crash, where BindToClose never
	-- runs (S-03). SESSION_STEAL defaults to 40 s.
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", opts.autosaveSeconds)
	ProfileStore.SetConstant("SESSION_STEAL", opts.staleAfterSeconds)

	-- A Studio play-test must never touch the live store.
	local storeName = if RunService:IsStudio() then opts.storeName .. "_studio" else opts.storeName

	local self = setmetatable({
		_opts = opts,
		_store = ProfileStore.New(storeName, Profile.new(opts.config, os.time())),
		_sessions = {},
		_saved = {}, -- userId -> count of confirmed writes, bumped by OnAfterSave
		_releasing = {}, -- userId -> true while we are ending the session ourselves
	}, DataStoreAdapter)

	-- Without this the only trace of a failed write is a warn nobody reads.
	ProfileStore.OnError:Connect(function(message, failedStore, key)
		warn(`[data] {failedStore}/{key}: {message}`)
	end)

	return (self :: any) :: DataAdapter
end

function DataStoreAdapter:load(userId: number): Result<ProfileData>
	local opts: Options = self._opts

	local session = self._store:StartSessionAsync(`Player_{userId}`, {
		Cancel = function()
			return not opts.isActive(userId)
		end,
	})

	if session == nil then
		return Result.err("ProfileLocked", `session for {userId} is held elsewhere`)
	end

	local migrated = Profile.migrate(session.Data)
	if not migrated.ok then
		-- Unreadable or newer-than-us data: end the session without writing, so the bad
		-- value survives for inspection instead of being overwritten by a fresh profile.
		session:EndSession()
		return migrated
	end

	session:AddUserId(userId)
	session:Reconcile()

	-- Mutated in place: ProfileStore saves the table it handed out, so reassigning
	-- session.Data would leave it saving the old one.
	local pruned = Profile.pruneReceipts(migrated.value, os.time(), RECEIPT_MAX_AGE)
	session.Data.processedReceipts = pruned.processedReceipts

	self._saved[userId] = 0
	-- ProfileStore fires OnSessionEnd first and OnAfterSave for the same final write right
	-- after it, so this counter must survive the cleanup below and tolerate being absent.
	session.OnAfterSave:Connect(function()
		self._saved[userId] = (self._saved[userId] or 0) + 1
	end)

	session.OnSessionEnd:Connect(function()
		self._sessions[userId] = nil
		-- EndSession() fires this too, so without the flag every ordinary leave and every
		-- BindToClose would tell the player their save was stolen.
		local ours = self._releasing[userId] == true
		self._releasing[userId] = nil
		if opts.onSessionEnd and not ours then
			opts.onSessionEnd(userId)
		end
	end)

	if not opts.isActive(userId) then
		session:EndSession()
		return Result.err("ProfileLocked", `{userId} left while the session was loading`)
	end

	self._sessions[userId] = session
	return Result.ok(session.Data)
end

function DataStoreAdapter:sync(userId: number, profile: ProfileData): Result<true>
	local session = self._sessions[userId]
	if session == nil then
		return Result.err("ProfileNotLoaded", `no session for {userId}`)
	end

	-- Field-by-field, not a reassignment: ProfileStore saves the table it handed out.
	session.Data.wallet = profile.wallet
	session.Data.upgrades = profile.upgrades
	session.Data.rebirths = profile.rebirths
	session.Data.processedReceipts = profile.processedReceipts
	session.Data.stats = profile.stats
	return Result.ok(true)
end

-- Profile:Save() is fire-and-forget: it spawns the write and never yields or throws, so a
-- pcall around it proves nothing. The library does retry the DataStore call with its own
-- backoff, and announces each successful write through OnAfterSave — that signal is the
-- only honest evidence a save landed, so this waits for it.
function DataStoreAdapter:save(userId: number, profile: ProfileData): Result<true>
	local synced = self:sync(userId, profile)
	if not synced.ok then
		return synced
	end

	local session = self._sessions[userId]
	if session:IsActive() == false then
		return Result.err("DataStoreUnavailable", `session for {userId} is no longer active`)
	end

	local before = self._saved[userId] or 0
	session:Save()

	local deadline = os.clock() + self._opts.saveTimeoutSeconds
	while (self._saved[userId] or 0) == before do
		if os.clock() > deadline then
			return Result.err("DataStoreUnavailable", `save for {userId} was not confirmed in time`)
		end
		task.wait(0.1)
	end

	return Result.ok(true)
end

function DataStoreAdapter:release(userId: number)
	local session = self._sessions[userId]
	if session then
		self._releasing[userId] = true
		self._sessions[userId] = nil
		session:EndSession()
	end
end

return DataStoreAdapter
