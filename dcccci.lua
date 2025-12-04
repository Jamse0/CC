local ccstring = require "cc.strings"
local pp = require "cc.pretty"

local is_emu = not not ccemux
local cb
if (is_emu) then
    -- pretend chatbox exists
    cb = {}
    function cb.validate(message,prefix,brackets)
        if (prefix == nil) then prefix = "AP"
        elseif (prefix == "") then error("Prefix cannot be empty string")
        end
        brackets = brackets or "[]"
        if (#brackets ~= 2) then error("Brackets must be exactly 2 characters")
        end
        if (message == nil or #message == 0 or message == "") then
            error("Message invalid")
        end
        return prefix,brackets
    end
    function cb.sendMessage(message,prefix,brackets)
        prefix,brackets = validate(message,prefix,brackets)
        print("to chat:",brackets[1]..prefix..brackets[2] .. " " .. message)
    end
    function cb.sendFormattedMessage(message,prefix,brackets)
        prefix,brackets = validate(message,prefix,brackets)
        print("formatted to chat:",brackets[1]..prefix..brackets[2] .. " " .. message)
    end
    function cb.sendMessageToPlayer(message,target,prefix,brackets)
        prefix,brackets = validate(message,prefix,brackets)
        print("to " .. target .. ":",brackets[1]..prefix..brackets[2] .. " " .. message)
    end
    function cb.sendFormattedMessageToPlayer(message,target,prefix,brackets)
        prefix,brackets = validate(message,prefix,brackets)
        print("formatted to " .. target .. ":",brackets[1]..prefix..brackets[2] .. " " .. message)
    end
else
    cb = peripheral.find("chat_box")
end

-- If you are planning on expanding functionality, intents are in this link
-- https://discord.com/developers/docs/events/gateway#gateway-intents
local intents = {
    -- Events
    GUILD_MESSAGES = 2^(9),

    -- Configuration
    MESSAGE_CONTENT= 2^(15)
}

local url_api = "https://discord.com/api/v10"
local gateway = url_api .. "/gateway"

local bot_token
local channel_id
local url_webhook
local url_log_webhook

local function initCredentials(env_path)
    local env = fs.open(env_path,"r")
    if (env) then
        local rawEnvData = env.readAll()
        if (rawEnvData) then
            local envData = textutils.unserialize(rawEnvData)
            if (envData) then
                bot_token = envData.bot_token
                channel_id = envData.channel_id
                url_webhook = envData.url_webhook
                url_log_webhook = envData.url_log_webhook
                print("Token:  ",bot_token)
                print("Channel:",channel_id)
                print("Webhook:",url_webhook)
                print("Log Webhook:",url_log_webhook)
                if (bot_token and channel_id and url_webhook and url_log_webhook) then
                    env.close()
                    return
                else
                    print("invalid data")
                end
            else
                print("could not parse env")
            end
        else
            print("Failed to read env data, could be blank")
        end

        env.close()
    else
        print("env doesn't exist")
    end
    print("Please insert requested data:")
    local input
    local input_history

    local b64String = "[A-Za-z0-9%+/%.%_%-]+"
    input_history = {bot_token}
    repeat 
        write("Bot token: ")
        input = read(nil,input_history)
        -- local token = string.match(input, "(" .. b64Char.."+%." .. b64Char.."+%." .. b64Char.."+" .. ")")
        local token = string.match(input, "(" ..
        -- table.concat({b64String,b64String,b64String},"%.") -- exactly 3 base64 strings separated by a dot
        string.rep(b64String,3,"%.") -- exactly 3 base64 strings separated by a dot
        .. ")" .. "[^%.]*$") -- no more dots.
        
        if (token) then
            if (http.get(url_api .. "/users/@me",{
                ["Authorization"]="Bot "..token
            })) then
                -- if discord accepts the token
                bot_token = token
                break
            else
                print("Token incorrect")
            end
        else
            print("Invalid token format")
        end

        table.insert(input_history,input)
    until false
    input_history = {channel_id}
    repeat 
        write("Channel ID: ")
        input = read(nil,input_history)
        local id = string.match(input, "(" .. string.rep("%d",17) .. string.rep("%d?",20-17) .. ")" .. "%D*$")
        
        if (id) then
            local response,e,o = http.get(url_api .. "/channels/" .. id,{
                ["Authorization"]="Bot "..bot_token
            })
            if (response) then
                -- if discord accepts the token
                channel_id = id
                break
            else
                print("ID not visible to bot")
            end
        else
            print("Invalid ID format")
        end
        table.insert(input_history,input)
    until false
    input_history = {url_webhook}
    repeat 
        write("Webhook URL: ")
        input = read(nil,input_history)
        local url = string.match(input, "(" .. "https://discord%.com/api/webhooks/%d+/[A-Za-z0-9%-%_]+" .. ")")
        
        if (url) then
            if (http.get(url)) then
                url_webhook = url
                break
            else
                print("URL incorrect")
            end
        else
            print("URL invalid or missing")
        end
        table.insert(input_history,input)
    until false
    input_history = {url_log_webhook}
    repeat 
        write("Log Webhook URL: ")
        input = read(nil,input_history)
        local url = string.match(input, "(" .. "https://discord%.com/api/webhooks/%d+/[A-Za-z0-9%-%_]+" .. ")")
        
        if (url) then
            if (http.get(url)) then
                url_log_webhook = url
                break
            else
                print("URL incorrect")
            end
        else
            print("URL invalid or missing")
        end
        table.insert(input_history,input)
    until false
    
    local newEnv = fs.open(env_path,"w")
    newEnv.write(textutils.serialize({
        bot_token = bot_token,
        channel_id = channel_id,
        url_webhook = url_webhook,
        url_log_webhook = url_log_webhook
    }))
    newEnv.close()
    print("env completed")
end
initCredentials("/dcccci.env")

local DiscordHook = require "DiscordHook"
local success,webhook = DiscordHook.createWebhook(url_webhook)
local success2,log_webhook = DiscordHook.createWebhook(url_log_webhook)

local bot_ws
local heartbeat_interval
local sequence_number = 0

local function sendDiscord(message)
    print("sending message in discord")
    webhook.send(message)
end

local function log(message, thing, level)
    level = string.upper(level or "INFO")
    local msg = "["..level.."] " .. message
    if (thing) then 
        msg = msg.." " .. pp.render(pp.pretty(thing))
    end
    if (level == "ERROR") then
        msg = msg.."\n@toughtntman37"
    end
    log_webhook.send(msg)
end

local function info(message,thing)
    log(message,thing,"INFO")
end

local function warn(message,thing)
    log(message,thing,"WARN")
end

local function err(message,thing)
    log(message,thing,"ERROR")
end
local debug_logging = true
local function debug(message,thing)
    if (debug_logging) then
        log(message,thing,"DEBUG")
    end
end

local function connect()
    info("Connecting to Discord Bot")
-- Establish Connection
    local request = http.get(gateway .. "/bot",{
        ["Authorization"]="Bot "..bot_token
    })
    if (not request) then error("Request Failed") end
    local response = textutils.unserializeJSON(request.readAll())
    if (not response) then error("Response Invalid") end
    local bot_ws_url = response.url
    if (not bot_ws_url) then error("Response Invalid") end

    local ws,err_msg = http.websocket(bot_ws_url .. "?v=10&encoding=json")
    if (not ws) then error(err_msg) end
    bot_ws = ws

-- Handle Hello
    local hello = bot_ws.receive()
    hello = textutils.unserializeJSON(hello)
    info("Received Hello:",hello)
    if (hello.op ~= 10) then error("Received non-hello") end
    
    heartbeat_interval = hello.d.heartbeat_interval / 1000
    info("heartbeat_interval: " .. heartbeat_interval)

-- Identify
    local device
    if (is_emu) then
        device = "ccemux"
    else
        device = "ComputerCraft_Tweaked_PC"
    end

    local identification = {
        ["op"]= 2,
        ["d"] = {
            ["token"] = bot_token,
            ["intents"] = intents.GUILD_MESSAGES + intents.MESSAGE_CONTENT,
            ["properties"] = {
                ["os"] = os.version(),
                ["browser"] = "none",
                ["device"] = device
            }
        }
    }
    bot_ws.send(textutils.serializeJSON(identification))
    
    -- Next, we need to start the heartbeat.
end

-- Starts a background loop to read user input and send it
local function chatLoop()
    while true do
        local msg
        local event, name, message = os.pullEvent("chat")
        msg = "<" .. name .. "> " .. message

        sendDiscord(msg)
    end
end

local function terminalLoop()
    while true do
        local message = read()
        local msg = "[TERMINAL]" .. message

        sendDiscord(msg)
    end
end

local function parseCommand(string)
    local command = ccstring.split(string,"%s")
    local head = string.lower(command[1])

    info("Parsing command:",command)

    if (head == "!fakejoin" and #command == 2) then
        local out = {
            {
                text = command[2].." joined the game",
                color = "yellow"
            }
        }
        out = textutils.serializeJSON(out)
        cb.sendMessage("",out,"  ")

    elseif (head == "!fakeleave" and #command == 2) then
        local out = {
            {
                color = "yellow",
                text = command[2].." left the game"
            }
        }
        out = textutils.serializeJSON(out)
        cb.sendMessage("",out,"  ")

    elseif (head == "!raw"  and #command > 1) then
        local out = string.sub(msg,#head+1)
        cb.sendMessage("",out,"  ")

    elseif (head == "!sudo" and #command > 2) then
        cb.sendMessage(string.sub(msg,#command[1] + #command[2] + 3),command[2],"<>")

    elseif ((head == "!whisper" or head == "!w") and #command > 2) then
        cb.sendMessageToPlayer(string.sub(msg,#command[1] + #command[2] + 3),command[2],username.." whispers to you"," :")

    elseif (head == "!whisperas" and #command > 3) then
        cb.sendMessageToPlayer(string.sub(msg,#command[1] + #command[2] + #command[3] + 4),command[3],command[2].." whispers to you"," :")
    
    elseif (head == "!anonymouswhisper" and #command > 2) then
        cb.sendMessageToPlayer(string.sub(msg,#command[1] + #command[2] + 3),command[2],"You hear a whisper from beyond"," :")

    elseif (head == "!formattedwhisper" and #command > 2) then
        cb.sendMessageToPlayer(string.sub(msg,#command[1] + #command[2] + 3),command[2],username.." whispers to you"," :")

    elseif (head == "!formattedwhisperas" and #command > 3) then
        cb.sendFormattedMessageToPlayer(string.sub(msg,#command[1] + #command[2] + #command[3] + 4),command[3],command[2].." whispers to you"," :")
    
    elseif (head == "!formattedanonymouswhisper" and #command > 2) then
        cb.sendFormattedMessageToPlayer(string.sub(msg,#command[1] + #command[2] + 3),command[2],"You hear a whisper from beyond"," :")
        
    elseif ((head == "!rawwhisper" or head == "!rw") and #command > 2) then
        cb.sendMessageToPlayer("",command[2],string.sub(msg,#command[1] + #command[2] + 3),"  ")

    elseif (head == "!reboot") then
        os.reboot()
    else
        warn("Failed to parse command")
        return false
    end
    return true
end

local function handleDiscordMessage(d)
    print("Handling discord message")
    local username = d.author.global_name
    local msg = d.content
    if (d.author.bot) then return end

    if (string.sub(msg,1,1) == "!") then
        if not parseCommand(msg) then sendDiscord("Invalid command or usage") end
    else
        print("Sending normal message in minecraft chat")
        cb.sendMessage(msg,username,"<>")
    end
end

local function websocketLoop()
    while true do
        while (not bot_ws) do
            warn("Refreshing bot")
            connect()
        end
        -- print("Awaiting message...")
        
        local thing 
        local function get() 
            thing = bot_ws.receive()
        end
        pcall(get) 

        if (thing) then 
            thing = textutils.unserializeJSON(thing)
            if (thing.op ~= 11) then 
                info("Received from bot:",thing)
            end
            if (thing.s) then
                sequence_number = thing.s
            end
            if (thing.d and thing.d.channel_id and thing.d.channel_id == channel_id) then
                
                if thing.t == "MESSAGE_CREATE" then
                    pcall(handleDiscordMessage,thing.d)
                end
            end

            -- wait for chatbot to cooldown
            sleep(0.1)
        else
            warn("Did not receive from bot")
            sleep(0.05)
        end
    end
end

local function heartbeat()
    while true do
        bot_ws.send(textutils.serializeJSON({
            ["op"]= 1,
            ["d"] = sequence_number,
            ["s"] = textutils.json_null,
            ["t"] = textutils.json_null
        }))
        repeat
            local response
            local function getResponse()
                response = bot_ws.receive()
            end
            pcall(getResponse)
            if (not response) then
                bot_ws.close()
                sleep(1)
                if (not response) then
                    error("Failed response twice in heartbeat! reconnecting...")
                    connect()
                end
            end

            response = textutils.unserializeJSON(response)
            if (response.s) then
                sequence_number = response.s
            end
        until response.op == 11
        sleep(heartbeat_interval)
    end
end
while true do
    local s,e = pcall(connect)
    if (not s) then
        err("Could not connect:",e)
        print("ERROR:",e)
        sleep(5)
        os.reboot()
    end
    connect()
    -- Run both loops in parallel
    -- parallel.waitForAny(heartbeat,websocketLoop,chatLoop)
    s,e = pcall(parallel.waitForAny,heartbeat,websocketLoop,chatLoop)
    if (not s) then
        err("An unknown fatal error occured:",e)
        print("ERROR:",e)
        sleep(5)
        os.reboot()
    else
        info("Closing intentionally?")
    end
end
