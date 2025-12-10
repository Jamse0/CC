local pp = require "cc.pretty"

local Moveset = {}
Moveset.__index = Moveset

function Moveset:generateKey(move)
    pp.pretty_print(self.move)
    local key
    -- Find an unused key
    repeat
        key = math.random()
    until self.move[key] == nil

    self.move[key] = move

    return key
end

function Moveset:removeMove(move)
    for k, v in pairs(self.move) do
        if (v == move) then
            self.move[k] = nil
        end
    end
end

function Moveset:peek(key)
    return self.move[key]
end

function Moveset:pop(key)
    local move = self.move[key]
    self.move[key] = nil
    return move
end

-- get and replace key-move pair
function Moveset:get(key)
    local move = self:pop(key)
    if not move then return false end

    local newKey = self:generateKey(move)

    return move, newKey
end

function Moveset:new(moves)

    local instance = {
        move = {}
    }
    setmetatable(instance,Moveset)

    return instance
end


local Game = {}
Game.__index = Game

function Game.moves() 
    return {"rock","paper","scissors"}
end

function Game.moveName(move_id)
    return Game.moves()[move_id]
end

function Game:new(player1,player2,pointsToWin)
    print("Creating new game")
    local instance = {
        -- players = {player1, player2},
        player1 = player1,
        player2 = player2,
        last_move={
            player = nil,
            move_id = nil
        },
        pointsToWin=pointsToWin,
        -- score = {0,0}, -- {p1, p2}
        score = {
            [player1]=0,
            [player2]=0
        }, -- {p1, p2}
        moveset = {
            [player1]=Moveset:new(),
            [player2]=Moveset:new()
        }
    }

    for _, move in ipairs({1,2,3}) do
        instance.moveset[player1]:generateKey(move)
        instance.moveset[player2]:generateKey(move)
    end

    setmetatable(instance, Game)
    
    return instance
end

function Game:otherPlayer(player)
    return (player == self.player1) and self.player2 or self.player1
end

-- You can play if you didn't just
function Game:isPlayerTurn(player)
    return (self.last_move.player ~= player)
end

-- returns false if invalid, returns move id and replacement key
function Game:getMove(player,move_key)
    return self:isPlayerTurn(player) and 
        self.moveset[player].get(move_key)
end

-- Could return other player move and name, could fetch that separately 

-- No validation.
function Game:sendMove(player,move_id)
    local last_move_id = self.last_move.move_id
    if (last_move_id == nil) then
        -- first move
        self.last_move.player = player
        self.last_move.move_id = move_id
        return "FIRST_MOVE"
    end

    if (last_move_id == move_id) then
        -- tie. Round is a push.
        self.last_move.player = nil
        self.last_move.move_id = nil
        return "ROUND_TIE"
    end

    if (move_id == (last_move_id % 3 + 1)) then
        -- player wins!
        self.score[player] = self.score[player] + 1
        if self.score[player] >= self.pointsToWin then
            -- Game over

            return "GAME_WIN"
        else
            self.last_move.player = nil
            self.last_move.move_id = nil
            return "ROUND_WIN"
        end
    end

    if (last_move_id == (move_id % 3 + 1)) then
        -- player loses!
        local other_player = self.otherPlayer(player)

        self.score[other_player] = self.score[other_player] + 1
        if self.score[other_player] >= self.pointsToWin then
            -- Game over

            return "GAME_LOSE"
        else
            self.last_move.player = nil
            self.last_move.move_id = nil
            return "ROUND_LOSE"
        end
    end
end



return Game
