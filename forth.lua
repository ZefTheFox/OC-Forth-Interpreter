computer = require("computer")
term = require("term")
text = require("text")
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

  for i = start+1, pos do 
    if string.find(source[i], target) then
      fullString = fullString.." "..string.gsub(source[i], target, "")
    else
      fullString = fullString.." "..source[i]
    end
  end
  return targetFound, pos, fullString
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

local errors = {"Stack underflow", "Not enough information", "Variable already exists", [0]=""}
stack = {n = 0} -- Initializes the stack
rStack = {n = 0} -- Return stack, mainly for compatibility with Forth
variables = {debugMode = {"1"}, 0, n = 1} -- Emulating memory addresses, should be reliably syncronized
local version = "1.0.0-0002" -- Version number
local skipIndex = 0

local function reduceStack(); stack[stack.n] = nil; stack.n = stack.n-1; end -- Removes the top value from the stack
local function writeStack(number); stack.n = stack.n + 1; stack[stack.n] = number; end -- Writes a new number to the stack

-- Word definitions --

-- Read from a variable
-- (a -- n)
words.system["@"] = {isLua = true}
words.system["@"][1] = function()
  if stack.n > 0 then
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
  if stack.n > 1 then
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
words.system[".*"] = {isLua = true}
words.system[".*"][1] = function(index, splitInput)
  hasEnd, endPos, fullString = stringUntil(splitInput, "*", index+1)
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
words.system.WORDS = {isLua = true}
words.system.WORDS[1] = function()
  for i, word in pairs(words.system) do
    io.write(i.." ")
  end
  for i, word in pairs(words.custom) do
    io.write(i.." ")
  end
  return 0 
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
  local splitInput = text.tokenize(input) -- Split input up into a table, with space as the delimiter
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
        if number(word) ~= 0 then -- Tries to put the "number" into the stack, if it fails then print an error
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
