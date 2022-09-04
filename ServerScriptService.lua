local raven = require(10811628747) -- fetch the cloud-managed module (auto-updated)
local client = Raven:Client("sentry project dsn") -- establishes your sentry client

game:GetService("ScriptContext").Error:Connect(function(message, trace, script) -- sends every server-sided ScriptContext error
	client:SendException("ServerError", message, debug.traceback())
end)

game:GetService("LogService").MessageOut:Connect(function(message, messageType) -- sends every server-sided LogService error
	if (messageType == Enum.MessageType.MessageError) then
    client:SendException("ServerError", message)
	end
end)

client:SetupClient(Instance.new("RemoteEvent", game.ReplicatedStorage)) -- creates the RemoteEvent in ReplicatedService for client log/error monitoring
