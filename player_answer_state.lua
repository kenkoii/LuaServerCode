local P = {}

function P:new()
    local object = {}
    
    object._player1Speedy = 3
    object._player2Speedy = 3

    object._player1Points = 0
    object._player2Points = 0

    object._player1Id = 0
    object._player2Id = 0

    object._questionAnswer = ""

    return object
end

return P