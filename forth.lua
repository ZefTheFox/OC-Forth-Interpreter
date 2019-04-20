computer = require("computer")
term = require("term")
component = require("component")
local interpret

local function tableLen(tab); 
  local count = 0 
  for _ in pairs(tab) do;
    count = count + 1; 
  end; 
  return count; 
end

local function stringUntil(source, target, start)
  local start = start or 1
  local targetFound = false
  local fullString = ""
  local pos
  local str
  for i = start+1, tableLen(source) do
    if string.find(source[i], target) then
      targetFound = true
      pos = i
      break
    end
  end 
  pos = pos or 0
  for i = start+1, pos do 
    if string.find(source[i], target) then
      fullString = fullString.." "..string.gsub(source[i], target, "")
    else
      fullString = fullString.." "..source[i]
    end
  end
  return targetFound, pos, fullString
end

local function splitString(input)
  local words = {}
  for word in input:gmatch("%S+") do 
    table.insert(words, word) 
  end
  return words
end

-- All variables
words = {
  system = {},
  custom = {},
}
-- Compiling related
local isCompiling = false -- Keeps track of compiling
local currentContent = "" -- Keeps track of the content of what is being compiled
local currentName = "" -- Keeps track of the name of what is being compiled
local currentWordIsLua = false -- Keeps track of if the word is being defined for lua

-- Misc
local errors = {"Stack underflow", "Not enough information", "Variable already exists", "Component not avalible", [0]=""}
local skipIndex = 0
local version = "1.0.0-0004" -- Version number
local curDrive = {} -- Sector size 512 bytes, 16 lines on screen, 32 bytes per line on screen
local cachedSector = {} -- 39ba9ce0-eca7-4275-b88a-cb0e37fc0a88
for i = 1, 16 do
  cachedSector[i] = {}
end
curPos = 1
curLine = 1
curSector = 1

stack = {n = 0} -- Initializes the stack
rStack = {n = 0} -- Return stack, mainly for compatibility with Forth. unused for now

variables = {debugMode = {"1"}, 0, diskMode = {"2"}, 0, n = 2} -- Emulating memory addresses, should be reliably syncronized
--[[
  Disk modes:
  0 - Unmanaged
  1 - Managed
  2 - Tape
]]

local function reduceStack(); stack[stack.n] = nil; stack.n = stack.n-1; end -- Removes the top value from the stack
local function writeStack(number); stack.n = stack.n + 1; stack[stack.n] = number; end -- Writes a new number to the stack

-- Word definitions --

-- Execute a sector
-- (n -- )
words.system["LOAD"] = {isLua = true}
words.system["LOAD"][1] = function()
  if stack.n > 0 then
    curSector = stack[stack.n]
    reduceStack()
    for line = 1, 16 do
      currentLineToInterpret = ""
      for curByte = 1, 32 do
        cachedSector[line][curByte] = curDrive.readByte(((curSector-1)*512)+((line-1)*32)+curByte)
        currentLineToInterpret = currentLineToInterpret..string.char(cachedSector[line][curByte])
      end
      interpret(currentLineToInterpret)
    end
  else
    return 1
  end
end

words.system["WIPE"] = {isLua = true}
words.system["WIPE"][1] = function()
  for line = 1, 16 do
    for curByte = 1, 32 do
      curDrive.writeByte(((curSector-1)*512)+((line-1)*32)+curByte, 32)
    end
  end
end

-- Write to the current line
-- ( -- )
words.system["P"] = {isLua = true}
words.system["P"][1] = function(index, splitInput)
  fullString = ""
  for i = index+1, tableLen(splitInput) do
    fullString = fullString..splitInput[i].." "
  end
  for currentCharacter = 1, 32 do
    cachedSector[curLine][currentCharacter] = string.byte(fullString, currentCharacter) or 32
  end
  words.system["FLUSH"][1]()
  return 0 
end

-- Save the cached sector to the drive
-- ( -- )
words.system["FLUSH"] = {isLua = true}
words.system["FLUSH"][1] = function()
  for line = 1, 16 do
    for curByte = 1, 32 do
      curDrive.writeByte(((curSector-1)*512)+((line-1)*32)+curByte, cachedSector[line][curByte])
    end
  end
end

-- Selects a line
-- (n -- )
words.system["T"] = {isLua = true}
words.system["T"][1] = function()
  if stack.n > 0 then
    curLine = stack[stack.n]
    curPos = 1
    reduceStack()
    for curByte = 1, 32 do
      cachedSector[curLine][curByte] = curDrive.readByte(((curSector-1)*512)+((curLine-1)*32)+curByte)
      if curPos == curByte then io.write("^") end
      io.write(string.char(cachedSector[curLine][curByte]))
    end
    io.write(curLine)
  else 
    return 1
  end
end

-- List all avalible drives
-- ( -- )
words.system["DRVLIST"] = {isLua = true}
words.system["DRVLIST"][1] = function()
  if variables[tonumber(variables.diskMode[1])] == 0 then
    if component.isAvailable("drive") then
      for address, _ in component.list("drive") do 
        io.write(address.."\n")
      end
    else
      return 4
    end
  else
    -- TODO add more drive support
  end
end

-- "mount" a drive
-- ( -- )
words.system["DRVSEL\""] = {isLua = true}
words.system["DRVSEL\""][1] = function(index, splitInput)
  local hasEnd, endPos, fullString = stringUntil(splitInput, "\"", index)
  if hasEnd then
    fullString = string.gsub(fullString, "%s+", "")
    if component.proxy(fullString) then
      curDrive = component.proxy(fullString)
      io.write("Drive mounted successfully")
      skipIndex = endPos
    else
      return 4
    end
  else
    return 2
  end
end

-- List but uses the current sector instead of what's on the stack
-- ( -- )
words.system["L"] = {isLua = true}
words.system["L"][1] = function()
  writeStack(curSector)
  words.system["LIST"][1]()
end

-- List a sector
-- (n -- )
words.system["LIST"] = {isLua = true}
words.system["LIST"][1] = function()
  if stack.n > 0 then
    curSector = stack[stack.n]
    reduceStack()
    for line = 1, 16 do
      if string.len(tostring(line)) > 1 then
        io.write(line.." | ")
      else
        io.write(line.."  | ")
      end
      for curByte = 1, 32 do
        cachedSector[line][curByte] = curDrive.readByte(((curSector-1)*512)+((line-1)*32)+curByte)
        if curLine == line and curPos == curByte then io.write("^") end
        io.write(string.char(cachedSector[line][curByte]))
      end
      io.write("\n")
    end
  else
    return 1
  end
end

-- Read from a variable
-- (a -- n)
words.system["@"] = {isLua = true}
words.system["@"][1] = function()
  if stack.n > 0 and variables[tonumber(stack[stack.n])] then
    local address = stack[stack.n]
    reduceStack()
    writeStack(variables[tonumber(address)])
  else
    return 1
  end
end

-- Write to a variable
-- (n a -- )
words.system["!"] = {isLua = true}
words.system["!"][1] = function()
  if stack.n > 1 and variables[tonumber(stack[stack.n])] then
    local address = stack[stack.n]
    local input = stack[stack.n-1]
    reduceStack()
    reduceStack()
    variables[tonumber(address)] = input
  else
    return 1
  end
end

-- Define a word in lua
-- ( -- )
words.system["L:"] = {isLua = true}
words.system["L:"][1] = function(index, splitInput)
  if splitInput[index+1] then
    isCompiling = true
    currentName = splitInput[index+1]
    currentWordIsLua = true
    skipIndex = 1
  else
    return 2
  end
end

-- Define a word
-- ( -- )
words.system[":"] = {isLua = true}
words.system[":"][1] = function(index, splitInput)
  if splitInput[index+1] then
    isCompiling = true
    currentName = splitInput[index+1]
    skipIndex = 1
  else
    return 2
  end
end

-- Display a string to the screen
-- ( -- )
words.system[".\""] = {isLua = true}
words.system[".\""][1] = function(index, splitInput)
  hasEnd, endPos, fullString = stringUntil(splitInput, "\"", index)
  if hasEnd then
    io.write(fullString)
    skipIndex = endPos-index
    
  else
    return 2
  end
end

-- Divide numbers 
-- (n1 n2 -- n)
words.system["/"] = {isLua = true}
words.system["/"][1] = function()
  if stack.n > 1 then
    stack[stack.n-1] = stack[stack.n-1] / stack[stack.n]
    reduceStack()
  else
    return 1
  end
end

-- Multiply numbers together
-- (n1 n2 -- n)
words.system["*"] = {isLua = true}
words.system["*"][1] = function()
  if stack.n > 1 then
    stack[stack.n-1] = stack[stack.n] * stack[stack.n-1]
    reduceStack()
  else
    return 1
  end
end

-- Add numbers together
-- (n1 n2 -- n)
words.system["+"] = {"0 SWAP - -"}

-- Swap the top 2 numbers on the stack
-- (n1 n2 -- n2 n1)
words.system.SWAP = {isLua = true}
words.system.SWAP[1] = function()
  if stack.n > 1 then
    local tmp = stack[stack.n]
    stack[stack.n] = stack[stack.n-1]
    stack[stack.n-1] = tmp
    tmp = nil
  else
    return 1
  end
end

-- Subtract n1 from n2 and put the result where n1 was
-- (n1 n2 -- n)
words.system["-"] = {isLua = true}
words.system["-"][1] = function()
  if stack.n > 1 then
    stack[stack.n-1] = stack[stack.n-1] - stack[stack.n]
    reduceStack()
  else
    return 1 
  end
end

-- Display all current words
-- ( -- )
words.system["WORDS"] = {isLua = true}
words.system["WORDS"][1] = function()
  for i, word in pairs(words.system) do
    io.write(i.." ")
  end
  for i, word in pairs(words.custom) do
    io.write(i.." ")
  end
end

-- Display and remove top number of the stack
-- (n -- )
words.system["."] = {isLua = true}
words.system["."][1] = function()
  if stack.n > 0 then
    io.write(" "..stack[stack.n])
    reduceStack()
  else
    return 1
  end
end

-- Define a variable
-- (n s- )
words.system.VARIABLE = {isLua = true}
words.system.VARIABLE[1] = function(index, splitInput)
  if splitInput[index+1] and stack.n > 0 and not variables[splitInput[index+1]] then
    variables[splitInput[index+1]] = variables.n+1
    variables[variables.n+1] = tostring(stack[stack.n])
    variables.n = variables.n+1
    reduceStack()
    skipIndex = 1
  elseif variables[splitInput[index+1]] then
    return 3
  elseif stack.n > 0 then
    return 2
  else
    return 1
  end
end


-- Rest of the interpreter --
local function number(input)
  if tonumber(input) then
    writeStack(tonumber(input))
    return 0 
  else
    return 1
  end
end

local function wordExecute(wordTable, index, splitInput)
  local returnState
  if wordTable.isLua then
    returnState = wordTable[1](index, splitInput)
  else
    interpret(tostring(wordTable[1]))
  end
  return returnState
end

local function loadExternal(file)
  os.execute(file)
end

function interpret(input)
  local splitInput = splitString(input) -- Split input up into a table, with space as the delimiter
  for index, word in pairs(splitInput) do
    if variables[tonumber(variables.debugMode[1])] == 1 then; print(word, stack[1], stack[2], stack[3]); end
    if skipIndex <= 0 and not isCompiling then
      local currentWordTable = nil
      local currentWordTable = words.system[word] or words.custom[word] or variables[word]
      if currentWordTable then
        local wordState = wordExecute(currentWordTable, index, splitInput)
        if wordState then
          io.stderr:write(errors[wordState])
          break
        end
      else
        if number(word) == 1 then -- Tries to put the "number" into the stack, if it fails then print an error
          io.stderr:write(word.." ?")
          break
        end
      end
    elseif skipIndex > 0 then
      skipIndex = skipIndex - 1
    elseif isCompiling then
      if word == ";" then
        isCompiling = false
        words.custom[currentName] = {currentContent}
        if currentWordIsLua then
          words.custom[currentName][1] = load(currentContent)
          currentWordIsLua = false
          words.custom[currentName].isLua = true
        end
        currentName = ""
        currentContent = ""
      else
        currentContent = currentContent.." "..word
      end
    
    end
  
  end
  
end


local function main()
  term.clear()
  io.write("Zef's Forth "..version.."\n")
  io.write(computer.freeMemory().." bytes free\n\n")
  while true do
    if not isCompiling then; io.write("> "); else; io.write("COMP> "); end
    local input = io.read()
    interpret(input)
    io.write(" ok\n")
  end
end

-- loadExternal("/mnt/633/forthExtended.lua")
main()
