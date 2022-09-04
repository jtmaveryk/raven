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

`raven:Client(dsn, config)`: creates a new Raven client used to send events
(dsn) the "DSN" located in your Sentry project "Client Keys" setting
[config] a table of attributes applied to all events before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SendMessage(message, level, config)`: send plain message event to Sentry
[message] the message sent
[level] a string describing the severity level of the event *(fatal, error, warning, info, debug)*
[config] a table of attributes applied to this event before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SendException(eType, errorMessage, traceback, config)`: send exception event to Sentry
[eType] a string describing the type of exception *(ServerError/ClientError)*
[errorMessage] a string describing the error, typically the second argument returned from pcall or an error message from LogService
[traceback] a string returned by `debug.traceback()` OR a premade stacktrace, used to add stacktrace information to the event
[config] a table of attributes applied to this event before being sent to Sentry *(logger, level, culprit, release, tags, environment, extra, message)*

`raven:SetupClient(remoteEvent)`: setup client error logging (refer to docs)
[remoteEvent] a remoteEvent being configured for client error logging


# Usage

This module is designed to be only used on the server to prevent players spamming spoofed requests to your Sentry project, potentially risking violation of Sentry's terms or flooding your request/error limit.

### Server Usage

***stores every server-sided ScriptContext error***
```lua
game:GetService("ScriptContext").Error:Connect(function(message, trace, script)
	client:SendException("ServerError", message, debug.traceback())
end)
```

***stores every server-sided LogService error***
```lua
game:GetService("LogService").MessageOut:Connect(function(message, messageType)
	if (messageType == Enum.MessageType.MessageError) then
		client:SendException("ServerError", message)
	end
end)
```



Here are two examples of sending events to your Sentry project:

```lua
local success, err = pcall(function() error("test server error") end)
if (not success) then
    client:SendException(raven.ExceptionType.Server, err, debug.traceback())
end
```

```lua
client:SendMessage("Fatal error", raven.EventLevel.Fatal)
client:SendMessage("Basic error", raven.EventLevel.Error)
client:SendMessage("Warning message", raven.EventLevel.Warning)
client:SendMessage("Info message", raven.EventLevel.Info)
client:SendMessage("Debug message", raven.EventLevel.Debug)
```

`SendMessage` is for basic errors, messages, or information, whereas `SendException` is for more complicated errors optionally paired with tracebacks from debug.traceback().

Since this module is supposed to be used only on the server, there is functionality for client > server error reporting built-in. Here’s how to use it, first on the server:

```lua
client:ConnectRemoteEvent(Instance.new("RemoteEvent", game.ReplicatedStorage))
```

Now, on the client:

```lua
local success, err = pcall(function() error("test client error") end)
if (not success) then
    game.ReplicatedStorage.RemoteEvent:FireServer(err, debug.traceback())
end
```

The arguments sent are the same as SendException, excluding a few options.
Make sure the RemoteEvent you pass isn’t used for any other purposes!

Each ROBLOX client can report a (configurable) maximum of 5 events per server, however if Raven detects spoofed data being sent, it disables their ability to report errors in that server entirely.

Raven also tries to anonymize data received from ROBLOX clients before sending it to Sentry.
