local logWarnings = true
local maxClientErrorCount = 5

local sentryVersion = "7"
local sdkName = "raven"
local sdkVersion = "1.2"

local Http = game:GetService("HttpService")

local GenerateUUID
do
	local hexTable = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 'a', 'b', 'c', 'd', 'e', 'f'}
	local rand = Random.new()
	local function RandomHex(length)
		local s = ""
		for i = 1, length do
			s = s .. hexTable[rand:NextInteger(1, 16)]
		end
		return s
	end
	GenerateUUID = function()
		return string.format("%s4%s8%s%s", RandomHex(12), RandomHex(3), RandomHex(3), RandomHex(12))
	end
end

local function GetTimestamp()
	local t = os.date("!*t")
	return ("%04d-%02d-%02dT%02d:%02d:%02d"):format(t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function TrySend(client, rawData, headers)
	if (client.enabled) then
		local succeed, err = pcall(Http.JSONEncode, Http, rawData)
		if (succeed) then
			local packetJSON = err
			local succeed, err = pcall(Http.PostAsync, Http, client.requestUrl, packetJSON, Enum.HttpContentType.ApplicationJson, true, headers)
			if (succeed) then
				local responseJSON = err
				local succeed, err = pcall(Http.JSONDecode, Http, responseJSON)
				if (succeed) then
					return true, err
				else
					return false, err
				end
			else
				local status = tonumber(err:match("^HTTP (%d+)"))
				if (status) then
					if (status >= 400 and status < 500) then
						if (logWarnings) then
							warn(("raven: HTTP %d in TrySend, JSON packet:"):format(status))
							warn(packetJSON)
							warn("Headers:")
							for i, v in pairs(headers) do
								warn(i.." "..v)
							end
							warn("Response:")
							warn(err)
							if (status == 401) then
								warn("Please check the validity of your DSN.")
							end
						end
					elseif (status == 429) then
						if (logWarnings) then
							warn("raven: HTTP 429 Retry-After in TrySend, disabling SDK for this server.")
						end
						client.enabled = false
					end
				end
				return false, err
			end
		else
			return false, err
		end
	else
		return false, "SDK disabled."
	end
end

local function SendEvent(client, packet, config)
	assert(type(packet) == "table")
	local timestamp = GetTimestamp()
	packet.event_id = GenerateUUID()
	packet.timestamp = timestamp
	packet.logger = "server"
	packet.platform = "other"
	packet.sdk = {name = sdkName; version = sdkVersion;}
	for i, v in pairs(client.config) do
		packet[i] = v
	end
	for i, v in pairs(config) do
		if (i == "tags" and type(packet[i]) == "table") then
			for k, c in pairs(v) do
				packet[i][k] = c
			end
		else
			packet[i] = v
		end
	end
	local headers = {Authorization = client.authHeader:format(timestamp)}
	local succeed, response = TrySend(client, packet, headers)
	return succeed, response
end

local function StringTraceToTable(trace)
	local stacktrace = {}
	for line in trace:gmatch("[^\n\r]+") do
		if (not line:match("^Stack Begin$") and not line:match("^Stack End$")) then
			local path, lineNum, value = line:match("^Script '(.-)', Line (%d+)%s?%-?%s?(.*)$")
			if (path and lineNum and value) then
				stacktrace[#stacktrace + 1] = {filename = path; ["function"] = value or "nil"; lineno = lineNum;}
			else
				return false, "invalid traceback"
			end
		end
	end
	if (#stacktrace == 0) then
		return false, "invalid traceback"
	end
	local sorted = {}
	for i = #stacktrace, 1, -1 do
		sorted[i] = stacktrace[i]
	end
	return true, sorted
end

local function ScrubData(playerName, errorMessage, traceback)
	errorMessage = errorMessage:gsub(playerName, "<Player>")
	local success, stacktrace
	if (traceback ~= nil) then
		success, stacktrace = StringTraceToTable(traceback)
		if (success) then
			for i, frame in pairs(stacktrace) do
				frame.filename = frame.filename:gsub(playerName, "<Player>")
			end
		end
	else
		success = true
	end
	if (success and errorMessage ~= "") then
		return true, errorMessage, stacktrace
	end
	return false, "invalid exception"
end

local raven = {}

--[[**
	creates a new Raven client used to send events
	@param [t:url] dsn the "DSN" located in your Sentry project "Client Keys" setting
	@param [t:table] config a table of attributes applied to all events before being sent to Sentry (logger, level, culprit, release, tags, environment, extra, message)
**--]]
function raven:Client(dsn, config)
	local client = {}
	client.DSN = dsn
	local protocol, publicKey, host, projectId = dsn:match("^([^:]+)://([^:]+)@([^/]+)/(.+)$")
	assert(protocol and protocol:lower():match("^https?$"), "invalid DSN: protocol not valid")
	assert(publicKey, "invalid DSN: public key not valid")
	assert(host, "invalid DSN: host not valid")
	assert(projectId, "invalid DSN: project ID not valid")
	client.requestUrl = ("%s://%s%sapi/%d/store/"):format(protocol, host, "/", projectId)
	client.authHeader = ("Sentry sentry_version=%d,sentry_timestamp=%s,sentry_key=%s,sentry_client=%s"):format(sentryVersion, "%s", publicKey, ("%s/%s"):format(sdkName, sdkVersion))
	client.config = config or {}
	client.enabled = true
	return setmetatable(client, {__index = self})
end

--[[**
	send plain message event to Sentry
	@param [t:string] message the message sent
	@param [t:string] level a string describing the severity level of the event (fatal, error, warning, info, debug)
	@param [t:table] config a table of attributes applied to this event before being sent to Sentry (logger, level, culprit, release, tags, environment, extra, message)
**--]]
function raven:SendMessage(message, level, config)
	config = config or {}
	local packet = {level = level or "info"; message = message;}
	return SendEvent(self, packet, config)
end

--[[**
	send exception event to Sentry
	@param [t:string] eType a string describing the type of exception (ServerError/ClientError)
	@param [t:string] errorMessage a string describing the error, typically the second argument returned from pcall or an error message from LogService
	@param [t:string] traceback a string returned by debug.traceback() OR a premade stacktrace, used to add stacktrace information to the event
	@param [t:table] config a table of attributes applied to this event before being sent to Sentry (logger, level, culprit, release, tags, environment, extra, message)
**--]]
function raven:SendException(eType, errorMessage, traceback, config)
	assert(type(eType) == "string", "invalid exception type")
	config = config or {}
	local exception = {type = eType; value = errorMessage;}
	local culprit
	if (type(traceback) == "string") then
		local success, frames = StringTraceToTable(traceback)
		if (success) then
			exception.stacktrace = {frames = frames}
			culprit = frames[#frames].filename
		else
			if (logWarnings) then
				warn(("raven: Failed to convert string traceback to stacktrace: %s"):format(frames))
				warn(traceback)
			end
		end
	elseif (type(traceback) == "table") then
		exception.stacktrace = {frames = traceback}
		culprit = traceback[#traceback].filename
	end
	local packet = {level = "error"; exception = {exception}; culprit = culprit;}
	return SendEvent(self, packet, config)
end

local errorCount = setmetatable({}, {__mode = "k"})

--[[**
	setup client error logging (refer to docs)
	@param [t:instance] remoteEvent a remoteEvent being configured for client error logging
**--]]
function raven:SetupClient(remoteEvent)
	assert(typeof(remoteEvent) == "Instance" and remoteEvent.ClassName == "RemoteEvent", "SetupClient did not receive RemoteEvent instance")
	remoteEvent.OnServerEvent:Connect(function(player, errorMessage, traceback)
		local count = errorCount[player]
		if (not count) then
			count = maxClientErrorCount
		end

		if (count > 0) then
			if (type(errorMessage) == "string" and (type(traceback) == "string" or traceback == nil)) then
				local success, scrubbedErrorMessage, scrubbedTraceback = ScrubData(player.Name, errorMessage, traceback)
				if (success) then
					count = count - 1
					self:SendException("ClientError", scrubbedErrorMessage, scrubbedTraceback)
				else
					if (logWarnings) then
						warn(("raven: Player '%s' tried to send spoofed data, their ability to report errors has been disabled."):format(player.Name))
						warn("errorMessage:")
						warn(errorMessage)
						warn("traceback:")
						warn(traceback)
					end
					count = 0
				end
			else
				if (logWarnings) then
					warn(("raven: Player '%s' tried to send spoofed data, their ability to report errors has been disabled."):format(player.Name))
					warn("errorMessage:")
					warn(errorMessage)
					warn("traceback:")
					warn(traceback)
				end
				count = 0
			end
		end

		errorCount[player] = count
	end)
end

return raven
