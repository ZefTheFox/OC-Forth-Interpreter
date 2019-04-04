local computer = require("computer")
local term = require("term")
local text = require("text")
local component = require("component")
local interpret

-- Current Word List and additional information
local WORDS = {
  WORDS = {isLua = true}, ["."] = {isLua = true},
  ["+"] = {isLua = true}, [":"] = {isLua = true},
  EXIT = {isLua = true}, IGNORECAPS = {isLua = true},
  HOE = {isLua = true}, PAGE = {isLua = true},
  IOXINIT = {isLua = true}, IOXSET = {isLua = true},
  DUP = {isLua = true}, [".S"] = {isLua = true},
  [".*"] = {isLua = true},
}

local STACK = {n = 0} -- Stack, n is number of items in the stack
local VARS = {}
local VER = "0.0.1a" -- Version
local HOE = true -- H.O.E. Halt on error
local IGNORECAPS = false -- When enabled capitalizes inputs automatically
local IDW = false -- Is defining word, best way I could think of doing this
local CWD = ""    -- Current Word Definition, SHOULD BE BLANK WHEN IDW IS FALSE
local CWN = ""    -- Current Word Name, SHOULD BE BLANK WHEN IDW IS FALSE
local REDSTONECARD -- Redstone Card, call IOXINIT to search for one
local SKIPLINES = 0 -- Set SKIPNEXT to true then increase this to skip more lines

-- Write text to the screen
WORDS[".*"][1] = function(_, wordIndex)
  local hasEnd = false
  local End
  local returnString = ""
  local function tableLen(tab); 
    local count = 0 
    for _ in pairs(tab) do;
      count = count + 1; 
    end; 
    return count; 
  end;

  for i = wordIndex+1, tableLen(splitInput) do
    if string.find(splitInput[i], "*") then; hasEnd = true; End = i; break; end
  end

  if hasEnd then
    SKIPNEXT = true; SKIPLINES = End - wordIndex
    for i = wordIndex+1, End do
      preparedInput = splitInput[i]
      if string.find(preparedInput, "*") then
        preparedInput = string.sub(preparedInput, 1, string.find(preparedInput, "*")-1)
      end
      returnString = returnString.." "..preparedInput
    end
    io.write(returnString.."\n")
  else
    io.stderr:write("ERROR: String doesn't end\n")
    return 1
  end
end

-- Displays whole stack
WORDS[".S"][1] = function()
  if STACK.n > 0 then
    for i, number in pairs(STACK) do
      if i == "n" then; io.write(" N:"..number.." "); 
      else; io.write(number.." "); end
    end
    io.write("\n")
  else
    io.stderr:write("Stack Empty\n")
    return 0
  end
end

-- Duplicate Top of stack
WORDS.DUP[1] = function()
  if STACK.n > 0 then
    STACK[STACK.n+1] = STACK[STACK.n]
    STACK.n = STACK.n+1
  else
    io.stderr:write("ERROR: Stack Empty\n")
    return 1
  end
end

-- Set redstone output
WORDS.IOXSET[1] = function()
  if REDSTONECARD and STACK.n > 1 then
    REDSTONECARD.setOutput(STACK[STACK.n-1], STACK[STACK.n])
    STACK[STACK.n] = nil
    STACK[STACK.n-1] = nil
    STACK.n = STACK.n - 2
  else
    io.stderr:write("ERROR: RS Card not Init or Stack Empty\n")
    return 1
  end
end

-- Try to find a redstone card
WORDS.IOXINIT[1] = function()
  local card = component.list("redstone")()
  if card then
    REDSTONECARD = component.proxy(card)
  else
    io.stderr:write("ERROR: No Redstone Card Avalible\n")
    return 1 
  end
end

-- Clear the screen
WORDS.PAGE[1] = function() term.clear() end

-- Halt on error
WORDS.HOE[1] = function()
  if STACK.n > 0 then
    if STACK[STACK.n] == 1 then
      HOE = true
    else
      HOE = false
    end
    STACK[STACK.n] = nil
    STACK.n = STACK.n - 1
  else
    io.stderr:write("ERROR: Stack Empty\n")
    return 1 -- An error happened
  end
end

-- Ignore Caps 
WORDS.IGNORECAPS[1] = function()
  if STACK.n > 0 then
    if STACK[STACK.n] == 1 then
      IGNORECAPS = true
    else
      IGNORECAPS = false
    end
    STACK[STACK.n] = nil
    STACK.n = STACK.n - 1
  else
    io.stderr:write("ERROR: Stack Empty\n")
    return 1 -- An error happened
  end
end

-- Display all current words
WORDS.WORDS[1] = function()
  for i, word in pairs(WORDS) do
    io.write(i.." ")
  end
  io.write("\n")
  return 0 
end

-- Output top item in stack to terminal
WORDS["."][1] = function()
  if not pcall(function()
    io.write(STACK[STACK.n].."\n")
    STACK[STACK.n] = nil
    STACK.n = STACK.n - 1
    return 0 -- No error
  end) then
    io.stderr:write("ERROR: Stack Empty\n")
    return 1 -- An error happened
  end
end

-- Addition
WORDS["+"][1] = function()
  if not pcall(function()
    STACK[STACK.n-1] = STACK[STACK.n] + STACK[STACK.n-1]
    STACK[STACK.n] = nil
    STACK.n = STACK.n-1
  end) then
    io.stderr:write("ERROR: Not enough items in stack\n")
    return 1
  end
end

-- Begin Word Definition
WORDS[":"][1] = function(NEXTWORD)
  if NEXTWORD then
    IDW = true
    CWD = ""
    CWN = NEXTWORD
    return 2 -- Skip the next word
  else
    io.stderr:write("ERROR: A name is required\n")
    return 1
  end
end

-- Exit interpreter
WORDS.EXIT[1] = function()
  os.exit(0)
end

-- Interpret The Input
local function interpret(input)
  splitInput = text.tokenize(input)

  for wordIndex, wordText in pairs(splitInput) do
  if not SKIPNEXT and not IDW then
    if tonumber(wordText) then
      -- Current "word" is just a number
      STACK[STACK.n+1] = tonumber(wordText)
      STACK.n = STACK.n + 1
    else
      if IGNORECAPS then wordText = wordText:upper() end
      if WORDS[wordText] then 
        -- The Word Exists
        if WORDS[wordText].isLua then 
          -- Function is implemented in lua
          local EXITCODE = WORDS[wordText][1](splitInput[wordIndex+1], wordIndex)
          if EXITCODE == 1 and HOE then
            io.stderr:write("\nExecuting Stopped, View Error Above\n")
            break
          elseif EXITCODE == 2 then
            SKIPNEXT = true
          end

        else
          -- Function is implemented in Forth
          interpret(WORDS[wordText][1], wordIndex)
        end
      else
        -- The Word Does Not Exist
        
        io.stderr:write("ERROR: Word Does Not Exist\n")
      end
  
    end
  elseif SKIPNEXT then; SKIPNEXT = false; 
    if SKIPLINES > 0 then
      SKIPNEXT = true
      SKIPLINES = SKIPLINES - 1
    end
  else
    if wordText == ";" then
      WORDS[CWN] = {}; WORDS[CWN][1] = CWD; CWD = ""; CWN = ""; IDW = false;
    else; CWD = CWD..wordText.." "; end
  end
  end
end

-- Actual Running

term.clear()
io.write("Zef's Forth "..VER.."\n")
io.write(computer.freeMemory().." bytes free\n\n")
while true do
  if not IDW then; io.write("> "); else; io.write("COMP> "); end
  local input = io.read()
  interpret(input)
end
