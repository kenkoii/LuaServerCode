local player_answer_state = require('player_answer_state')
local du = require('debug_utils')
local M = {}

function M:new()
    local object = {}

    object._enumGameState = 0
    object._roundWinnerId = 0
    object._playerAnswers = {}
    object._questionResults = {}

    function object:CreatePlayerAnswerState()
        table.insert(object._playerAnswers, player_answer_state.new())
    end

    function object:AddResultState(player_result)
        table.insert(object._questionResults, player_result)
    end

    function object:SetPlayer1Id(index, player1ResultPlayerId)
        object._playerAnswers[index]._player1Id = player1ResultPlayerId
    end

    function object:IsQuestionAnswerEmpty(index)
        return object._playerAnswers[index]._questionAnswer == ""
    end

    function object:SetPlayer1Points(index, points)
        object._playerAnswers[index]._player1Points = points
    end

    function object:SetPlayer1Speedy(index, points)
        object._playerAnswers[index]._player1Speedy = points
    end

    function object:SetQuestionAnswer(index, questionAnswer)
        object._playerAnswers[index]._questionAnswer = questionAnswer
    end

    function object:SetPlayer2Points(index, points)
        object._playerAnswers[index]._player2Points = points
    end

    function object:SetPlayer2Speedy(index, points)
        object._playerAnswers[index]._player2Speedy = points
    end

    return object
end

return M