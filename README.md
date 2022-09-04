Credits towards [nomer888](https://devforum.roblox.com/u/nomer888) for creating the original module and source for this SDK, you can visit their [gitlab](https://gitlab.com/nomer/rbxlua-raven) or [roblox devforum post](https://devforum.roblox.com/t/error-tracking-with-sentry-on-roblox/49751).

# Installation

### Automatic (cloud) Installation

To install **raven** into your game, create a script in `ServerScriptService` and paste the following contents in the top of the script:

```lua
local raven = require(10811628747)
local client = Raven:Client("sentry project dsn")
```

### Manual (local) Installation

Alternatively, you can copy the contents of [MainModule.lua](https://github.com/jtmaveryk/raven/blob/1.2/MainModule.lua) from this repository and paste it into a ModuleScript in the location of your choice. This is only suggested for experienced individuals interested in reconfiguring or editing the module.

```lua
local raven = require(game.ReplicatedStorage.Raven)
local client = Raven:Client("sentry project dsn")
```

# Documentation

`raven:Client(dsn, config)`: creates a new Raven client used to send events <br>
> **[dsn]** the "DSN" located in your Sentry project "Client Keys" setting <br>
> **[config]** a table of attributes applied to all events before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SendMessage(message, level, config)`: send plain message event to Sentry
> **[message]** the message sent <br>
> **[level]** a string describing the severity level of the event *(fatal, error, warning, info, debug)* <br>
> **[config]** a table of attributes applied to this event before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SendException(eType, errorMessage, traceback, config)`: send exception event to Sentry
> **[eType]** a string describing the type of exception *(ServerError/ClientError)* <br>
> **[errorMessage]** a string describing the error, typically the second argument returned from pcall or an error message from LogService <br>
> **[traceback]** a string returned by `debug.traceback()` OR a premade stacktrace, used to add stacktrace information to the event <br>
> **[config]** a table of attributes applied to this event before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SetupClient(remoteEvent)`: setup client error logging (refer to docs)
> **[remoteEvent]** a remoteEvent being configured for client error logging


# Examples

This module is designed to be only used on the server to prevent players spamming spoofed requests to your Sentry project, potentially risking violation of Sentry's terms or flooding your request/error limit. However, client to server error monitoring is built-in, allowing the logging/monitoring of client errors with certain precautions and limitations.

### Server Usage

Sends every server-sided **ScriptContext** error:
```lua
game:GetService("ScriptContext").Error:Connect(function(message, trace, script)
	client:SendException("ServerError", message, debug.traceback())
end)
```

Sends every server-sided **LogService** error:
```lua
game:GetService("LogService").MessageOut:Connect(function(message, messageType)
	if (messageType == Enum.MessageType.MessageError) then
		client:SendException("ServerError", message)
	end
end)
```

Sends a server test error:
```lua
local success, err = pcall(function() error("test server error") end)
if (not success) then
	client:SendException(raven.ExceptionType.Server, err, debug.traceback())
end
```

Sends a custom message error:
```lua
client:SendMessage("fatal error", "fatal")
client:SendMessage("basic error", "error")
client:SendMessage("warning message", "warning")
client:SendMessage("info message", "info")
client:SendMessage("debug message", "debug")
```

`client:SendMessage` is for basic errors, messages, or information, whereas `client:SendException` is for more complicated errors optionally paired with tracebacks from `debug.traceback()`.

### Client Usage

Each ROBLOX client can report a (configurable) maximum of 5 events per server, however if Raven detects spoofed data being sent, it disables their ability to report errors in that server entirely.

In order to initialize/setup the client to run and receive requests from the client, you must first create a RemoteEvent or generate one on startup (like below) and initalize it in a server-sided script using the `client:SetupClient` function. The RemoteEvent must be unique to this certain use, not used or fired from any other scripts.
```lua
client:SetupClient(Instance.new("RemoteEvent", game.ReplicatedStorage))
```

Stores every client-sided **ScriptContext** error:
```lua
game:GetService("ScriptContext").Error:Connect(function(message, trace, script)
	game.ReplicatedStorage.RemoteEvent:FireServer(message, debug.traceback())
end)
```

Sends a client test error:
```lua
local success, err = pcall(function() error("test client error") end)
if (not success) then
	game.ReplicatedStorage.RemoteEvent:FireServer(err, debug.traceback())
end
```
