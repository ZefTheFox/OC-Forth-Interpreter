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

local errors = {"Stack underflow", "Not enough information", "Variable already exists", [0]=""}
stack = {n = 0} -- Initializes the stack
rStack = {n = 0} -- Return stack, mainly for compatibility with Forth
local variables = {ignoreCaps = "1", 0, debug = "2", 0, n = 1} -- Emulating memory addresses, should be reliably syncronized
local version = "1.0.0-0002" -- Version number
local skipIndex = 0

local function reduceStack(); stack[stack.n] = nil; stack.n = stack.n-1;  end -- Used a lot

-- Word definitions --

-- Define a word
-- ( -- )
words.system[":"] = {isLua = true}
words.system[":"][1] = function(index, splitInput)
  if splitInput[index+1] then
    hasEnd, endPos, fullString = stringUntil(splitInput, ";", index+1)
    if hasEnd then
      words.custom[splitInput[index+1]] = {fullString}
      skipIndex = endPos
    else
      return 2
    end
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
    stack[stack.n+1] = tonumber(input)
    stack.n = stack.n+1
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
  local splitInput
  if variables[tonumber(variables.ignoreCaps)] == 0 then
    splitInput = text.tokenize(input) -- Split input up into a table, with space as the delimiter
  else
    splitInput = text.tokenize(string.upper(input))
  end

  for index, word in pairs(splitInput) do
    if variables[variables.debug] == 1 then; print(stack[1], stack[2], stack[3]); end
    if skipIndex <= 0 then
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
    else
      skipIndex = skipIndex - 1
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

-- loadExternal("/mnt/633/forthExtended.lua") -- This is for my testing
main()
