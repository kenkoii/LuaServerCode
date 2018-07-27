local nk = require("nakama")
local du = require("debug_utils")
local rus = require("round_result_state")

--Players--
local players = {}
--Question--
local question_filters = {}
local question_result_states = {}
local questions_list = {}
local questionID = {}
local filter = {}
-- RoundResult--
local round_winner_id = ""
local round_winner_dic = {}
local round_result_state = {}
local game_winner = "-10"

--CallbackIds--
local callbackIds = {}

local function match_init(context, params)
  local state = {
    debug = (params and params.debug) or false,
    presences = {}
  }
  if state.debug then
    print("match init context:\n" .. du.print_r(context) .. "match init params:\n" .. du.print_r(params))
  end
  local tick_rate = 30
  local label = ""

  return state, tick_rate, label
end

local function match_join_attempt(context, dispatcher, tick, state, presence)
  if state.debug then
    print("match join attempt:\n" .. du.print_r(presence))
  end
  return state, true
end

local function match_join(context, dispatcher, tick, state, presences)
  print("match join:\n" .. du.print_r(presences))
  if state.debug then
    for _, presence in ipairs(presences) do
      state.presences[presence.user_id] = presence
    end
  end
  return state
end

local function match_leave(context, dispatcher, tick, state, presences)
  if state.debug then
    print("match leave:\n" .. du.print_r(presences))
    for _, presence in ipairs(presences) do
      state.presences[presence.user_id] = nil
    end
  end

  if tablelength(state.presences) == 0 then
    return nil
  end
  
  return state
end

local function match_loop(context, dispatcher, tick, state, messages)
  if state.debug then
    print("match " .. context.match_id .. " tick " .. tick)
    print("match " .. context.match_id .. " messages:\n" .. du.print_r(messages))
  end

  -- Check for Messages here --
  for _, message in ipairs(messages) do
    print(("Received %s from %s"):format(message.data, message.sender.username))
    local decoded = nk.json_decode(message.data)
    for k, v in pairs(decoded) do
      print(("Message contained %s value %s"):format(k, v))
    end

    -- switch code here --
    -- INITIALIZE PLAYERS --
    if decoded['_opCode'] == 0 then
      local complete_players = add_player(decoded['_playerDataString']) 
      if complete_players == true then
        -- send players list to both players --
        local msg = {
          _opCode = decoded['_opCode'],
          _callId = decoded['_callId'],
          _playerDataString = nk.json_encode({
            _list = players
          })
        }
        print("sending match state" .. context.match_id .. " messages:\n" .. du.print_r(msg))
        dispatcher.broadcast_message(0, nk.json_encode(msg), nil, nil)
      end
    end

    -- SEND ANSWER --
    if decoded['_opCode'] == 1 then
      local playerDataString = nk.json_decode(decoded['_playerDataString'])
      local msg = {
        _opCode = decoded['_opCode'],
        -- _callId = decoded['_callId'],
        _playerDataString = nk.json_encode(playerDataString)
      }
      print("sending match state" .. context.match_id .. " messages:\n" .. du.print_r(msg))
      dispatcher.broadcast_message(0, nk.json_encode(msg), nil, nil)
    end

    -- QUESTION FILTERS --
    if decoded['_opCode'] == 6 then
      local complete_questions = add_question_filter(decoded['_playerDataString'])
      if complete_questions == true then
        local msg = {
          _opCode = decoded['_opCode'],
          _callId = decoded['_callId'],
          _playerDataString = nk.json_encode(filter)
        }
        print("sending match state" .. context.match_id .. " messages:\n" .. du.print_r(msg))
        dispatcher.broadcast_message(0, nk.json_encode(msg), nil, nil)
      end
    end

    -- QUESTION ADDING --
    if decoded['_opCode'] == 3 then
      local complete_questions = add_questions(decoded['_playerDataString'])
      if complete_questions == true then
        local msg = {
          _opCode = decoded['_opCode'],
          _callId = decoded['_callId'],
          _playerDataString = nk.json_encode(questionID)
        }
        print("sending match state" .. context.match_id .. " messages:\n" .. du.print_r(msg))
        dispatcher.broadcast_message(0, nk.json_encode(msg), nil, nil)
      end
    end

    if decoded['_opCode'] == 2 then
      print("State Presences:\n" .. du.print_r(state.presences))
      local _playerDataString = decoded['_playerDataString']
      local complete_results = add_round_result(_playerDataString)
      local playerId = nk.json_decode(_playerDataString)._playerId
      for k, presence in pairs(state.presences) do
        if k == message.sender.user_id then
          table.insert(callbackIds, {_presence = {presence}, _callId = decoded['_callId'], _playerId = playerId})
          print("Adding Callback ID: " .. decoded['_callId'] .. " Presence:\n" .. presence.user_id .. "PlayerId:\n" .. playerId)
        end
      end
      if complete_results == true then
        for i=1, #callbackIds do
          local game_state = round_result_state._enumGameState
          if game_state == 1 then
            if callbackIds[i]._playerId .. "" == game_winner then
              game_state = 1
            else
              game_state = 2
            end
          end
          local _playerDataString = nk.json_encode({
            _enumGameState = game_state,
            _roundWinnerId = round_result_state._roundWinnerId,
            _playerAnswers = round_result_state._playerAnswers,
            _questionResults = round_result_state._questionResults
          })
          print("PlayerDataString: " .. _playerDataString)
          local _parsed = string.gsub(_playerDataString .. "", "{}", "[]")
          local msg = {
            _opCode = decoded['_opCode'],
            _callId = callbackIds[i]._callId,
            _playerDataString = _parsed
          }
          print("sending match state" .. context.match_id .. " messages:\n" .. du.print_r(msg))
          dispatcher.broadcast_message(0, nk.json_encode(msg), callbackIds[i]._presence, nil)
        end
        question_result_states = {}
        callbackIds = {}
      end
    end
  end

  return state
end

function add_player(player_state)
  table.insert(players, nk.json_decode(player_state))

  if #players == 2 then
    return true
  end
  return false
end

function add_round_result(question_result_state)
  table.insert(question_result_states, nk.json_decode(question_result_state))
  if #question_result_states < 2 then
    return false
  end
  print("question_result_states:\n" .. du.print_r(question_result_states))

  round_winner_id = get_round_winner()
  --if round_winner_dic[round_winner_id] then
  round_winner_dic[round_winner_id .. ""] = (round_winner_dic[round_winner_id .. ""] or 0) + 1
  --end
  print("round_winner_id:\n" .. du.print_r(round_winner_id))
  print("round_winner_dic:\n" .. du.print_r(round_winner_dic))
  --Insert something
  round_result_state = get_all_round_result_model(question_result_states[1], question_result_states[2])
  return true
end

function get_round_winner()
  local totalPoints1 = 0
  local totalPoints2 = 0
  local totalTimePassed1 = 0
  local totalTimePassed2 = 0
  print("question_result_states[1]:\n" .. du.print_r(question_result_states[1]))
  print("question_result_states[2]:\n" .. du.print_r(question_result_states[2]))
  for i = 1, #question_result_states[1]._questionResultContents do
    print("question_result_states[1]._questionResultContents[i]:\n" .. du.print_r(question_result_states[1]._questionResultContents[i]))
    totalPoints1 = question_result_states[1]._questionResultContents[i]._points + totalPoints1
    totalTimePassed1 = question_result_states[1]._questionResultContents[i]._timePassed + totalTimePassed1
  end  
  for i = 1, #question_result_states[2]._questionResultContents do
    totalPoints2 = question_result_states[2]._questionResultContents[i]._points + totalPoints2
    totalTimePassed2 = question_result_states[2]._questionResultContents[i]._timePassed + totalTimePassed2
  end

  if totalTimePassed1 < totalTimePassed2 then
    totalPoints1 = totalPoints1 + 1
  end

  if totalTimePassed2 < totalTimePassed1 then
    totalPoints2 = totalPoints2 + 1
  end


  if totalPoints1 == totalPoints2 then
    return -10
  end

  if totalPoints1 > totalPoints2 then
    return question_result_states[1]._playerId
  end

  return question_result_states[2]._playerId
end

function get_all_round_result_model(player1_result, player2_result)
  local round_result_state = rus.new()
  local question_result_content_count = 0
  round_result_state:AddResultState(player1_result)
  round_result_state:AddResultState(player2_result)
  print("player1_result:\n" .. du.print_r(player1_result))
  print("player2_result:\n" .. du.print_r(player2_result))


  if #player1_result._questionResultContents >= #player2_result._questionResultContents then
    question_result_content_count = #player1_result._questionResultContents
  else
    question_result_content_count = #player2_result._questionResultContents
  end

  for i=1, question_result_content_count do
    round_result_state:CreatePlayerAnswerState()
    print("round_result_state" .. "[" .. i .."]:\n" .. du.print_r(round_result_state))
    round_result_state:SetPlayer1Id(i, player1_result._playerId)
    if i <= #player1_result._questionResultContents then
      round_result_state:SetPlayer1Points(i, player1_result._questionResultContents[i]._points)
      round_result_state:SetPlayer1Speedy(i, player1_result._questionResultContents[i]._speedy)
      round_result_state:SetQuestionAnswer(i, player1_result._questionResultContents[i]._questionAnswer)
    end

    if i <= #player2_result._questionResultContents then
      round_result_state:SetPlayer2Points(i, player2_result._questionResultContents[i]._points)
      round_result_state:SetPlayer2Speedy(i, player2_result._questionResultContents[i]._speedy)

      if round_result_state._playerAnswers[i]._questionAnswer == nil or round_result_state._playerAnswers[i]._questionAnswer == "" then
        round_result_state:SetQuestionAnswer(i, player2_result._questionResultContents[i]._questionAnswer)
      end
    end
  end
  round_result_state._enumGameState = check_game_status()
  round_result_state._roundWinnerId = round_winner_id

  return round_result_state
end

function check_game_status()
  print("round_winner_dic: " .. du.print_r(round_winner_dic) .. "\ncount:" .. tablelength(round_winner_dic))

  if tablelength(round_winner_dic) == 1 then
    for round_winner_id, score in pairs(round_winner_dic) do
      if round_winner_id == "-10" then
        if score > 2 then
          game_winner = round_winner_id .. ""
          return 3
        end
      end
      if score > 1 then
        game_winner = round_winner_id .. ""
      end
    end
    print("Game winner: " .. game_winner)
    if game_winner ~= "-10" then
      return 1
    end
  end

  if tablelength(round_winner_dic) == 2 then
    local values = {}
    for _, value in pairs(round_winner_dic) do
      table.insert(values, value)
    end

    local max = math.max(unpack(values))
    local min = math.min(unpack(values))
    if max ~= min then
      for id, score in pairs(round_winner_dic) do
        if score > 1 and score == max then
          if id == "-10" then
            game_winner = get_key_for_value(round_winner_dic, min)
            return 1
          else
            game_winner = id
            return 1
          end
        end
      end
    else
      return 0
    end
  end

  if tablelength(round_winner_dic) == 3 then
    return 3
  end
  -- Fallback Return value, Continue
  return 0
end

function add_question_filter(question_filter)
  table.insert(question_filters, nk.json_decode(question_filter))
  if #question_filters < 2 then
    return false
  end

  local rank = question_filters[1].playerRank + 1
  if question_filters[1].playerLevel < rank and question_filters[2].playerLevel < rank then
    if question_filters[1].playerLevel > question_filters[2].playerLevel then
      filter.playerLevel = question_filters[1].playerLevel
    else
      filter.playerLevel = question_filters[2].playerLevel
    end
  elseif question_filters[1].playerLevel > rank and question_filters[2].playerLevel < rank then
    if question_filters[1].playerLevel > question_filters[2].playerLevel then
      filter.playerLevel = question_filters[2].playerLevel
    else
      filter.playerLevel = question_filters[1].playerLevel
    end
  elseif question_filters[1].playerLevel == question_filters[2].playerLevel then
    filter.playerLevel = question_filters[1].playerLevel
  else
    filter.playerLevel = rank - 1
  end
  -- filter.selectionType = question_filters[math.random(1, #question_filters)].selectionType
  -- filter.targetType = question_filters[math.random(1, #question_filters)].targetType
  if question_filters[1].playerRank < question_filters[2].playerRank then
    filter.selectionType = question_filters[1].selectionType;
    filter.targetType = question_filters[1].targetType;
  else
    filter.selectionType = question_filters[2].selectionType;
    filter.targetType = question_filters[2].targetType;
  end
  return true
end

function add_questions(question)
  local questionObject = nk.json_decode(question)
  table.insert(questions_list, questionObject)
  if #questions_list < 2 then
    return false
  end

  if questions_list[1].player1Level == 0 then
    questionObject.player2Level = questions_list[1].player2Level;
  else
    questionObject.player1Level = questions_list[1].player1Level;
  end

  if questions_list[2].player1Level == 0 then
    questionObject.player2Level = questions_list[2].player2Level;
  else
    questionObject.player1Level = questions_list[2].player1Level;
  end

  local combinedQuestionList = questions_list[1]
  print("questions_list[1]\n" .. du.print_r(questions_list[1]))
  print("questions_list[2].questionIDList\n" .. du.print_r(questions_list[2].questionIDList))

  for i = 1, #questions_list[2].questionIDList do
    table.insert(combinedQuestionList.questionIDList, questions_list[2].questionIDList[i])  
  end

  print("combinedQuestionList combined\n" .. du.print_r(combinedQuestionList.questionIDList))

  questionID = get_question_sequence(
                combinedQuestionList.questionIDList, 
                combinedQuestionList.player1Level, 
                combinedQuestionList.player2Level,
                questions_list[math.random(1,#questions_list)].selectionType);

  return true
end

function get_question_sequence(questionIDList, player1Level, player2Level, selectionTypes)
  local player1Sequence = {}
  local player2Sequence = {}
  -- Player 1 sequence 
  for i = 1, #questionIDList / 2 do
    table.insert(player1Sequence, questionIDList[i])
  end

  -- Player 2
  -- 15+1 = 16 / 2 = 8 - 15
  for i = (#questionIDList / 2) + 1, #questionIDList do
    table.insert(player2Sequence, questionIDList[i])
  end

  print("player1Sequence\n" .. du.print_r(player1Sequence))
  print("player2Sequence\n" .. du.print_r(player2Sequence))

  local question_sequence = {}
  local idList = {}
  idList.questionIDList = {}

  local isAlternate = not (player2Level < player1Level)

  for i = 1, 3 do
    question_sequence = {}
    for j = 1, #questionIDList / 3 do
      isAlternate = not isAlternate
      local question = ""
      if isAlternate then
        question = player2Sequence[1]
        table.remove(player2Sequence, 1)
      else
        if #player1Sequence > 0 then
          question = player1Sequence[1]
          table.remove(player1Sequence, 1)
        end
      end
      
      if not has_value(question_sequence, question) then
        table.insert(question_sequence, question)
      end
    end
      table.insert(idList.questionIDList, {
        questionIDList = question_sequence,
        selectionType = selectionTypes
      })
  end 
  idList.selectionType = selectionTypes
  print("idList:\n" .. du.print_r(idList))
  return idList
end

function has_value (tab, val)
  for index, value in ipairs(tab) do
      if value == val then
          return true
      end
  end
  return false
end

function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end


function get_key_for_value(t, value)
  for k,v in pairs(t) do
    if v == value then return k end
  end
  return nil
end

-- Match modules must return a table with these functions defined. All functions are required.
return {
  match_init = match_init,
  match_join_attempt = match_join_attempt,
  match_join = match_join,
  match_leave = match_leave,
  match_loop = match_loop
}