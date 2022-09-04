game:GetService("ScriptContext").Error:Connect(function(message, trace, script) -- stores every client-sided ScriptContext error (fires the remote, sending the data to the server
	game.ReplicatedStorage.RemoteEvent:FireServer(message, debug.traceback())
end)
