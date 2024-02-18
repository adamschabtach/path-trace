-- patch trace
-- v1.0 @awakening.systems
--
-- short script description
-- A movement recorder for Norns and Crow. 
-- Four looping buffers
-- Independent playback control with optional sample and hold/quantization
--
-- E1 selects buffer; K2 toggles record; K3 toggles playback
-- More config in Params menu

musicutil = require 'musicutil' -- Musicutil library for quantization support

-- Configuration Variables
sleepTime = 0.03 -- Time in between recording 50ms fairly arbitrary
buffers = {} -- The buffers where we store everything
scaleNames = {} -- Constructed from musicutil, used in "scale" parameter selection
mode = 1 -- Mode parameter for global quantization
scaleKey = 0 -- Key parameter for gloval quantization
rawValue = 0 -- Initial value for knob recording
rawValueMin = -100 -- Knob recording minimum
rawValueMax = 100 -- Knob recording maximum
selectedBufferId = 1 -- Initial buffer. Changed with e2

-- Helper Functions for common tasks
function getVoltageRange(value)
  if value == 1 then
      return -5, 5
  elseif value == 2 then
      return 0, 10
  else
      return 0, 5
  end
end
function capValue(value, min, max)
    return math.min(math.max(value, min), max)
end
function mapValue(rawValue, rawMin, rawMax, outMin, outMax)
  -- LATER: Where am I setting nil
  rawValue = rawValue or 0 -- Default to 0 if rawValue is nil
  return (rawValue - rawMin) / (rawMax - rawMin) * (outMax - outMin) + outMin
end
function midiToVOct(midiNote)
  return (midiNote - 60) / 12
end

-- Creates buffer object with cv data buffer, recording logic, and playback control
function createBuffer(bufferId)
  return {
    -- Metadata
    bufferId = bufferId,
    outputMin = -5,
    outputMax = 5,
    -- Recording
    recording = false,
    recordingRef = nil,
    maximum_duration = 5 * 60 / sleepTime, -- Arbitrarily set to be 5 minutes
    recordingBuffer = {},
    recording_start = function(self)
      self.playing = false
      self.recording = true
      self.recordingBuffer = {}
      self.recordingRef = clock.run(self.add_to_buffer, self)
      redraw()
    end,
    recording_stop = function(self)
      self.recording = false
      rawValue = 0
      clock.cancel(self.recordingRef)
      self.bufferPosition = 1
      redraw()
    end,
    add_to_buffer = function(self)      
      while self.recording do
        -- Check if buffer length exceeds maximum_duration before adding new value
        if #self.recordingBuffer >= self.maximum_duration then
          self:recording_stop()
          return 
        end

        -- Transform and save knob position 
        local rawInCv = mapValue(rawValue, rawValueMin, rawValueMax, self.outputMin, self.outputMax)
        table.insert(self.recordingBuffer, rawInCv)

        -- Output the voltage
        crow.output[self.bufferId].volts = self.recordingBuffer[#self.recordingBuffer]

        redraw()
        clock.sleep(sleepTime)
      end
    end,
    -- Playback
    playing = false,
    playback_ref = nil,
    bufferPosition = 1,
    playback_start = function(self)
      if #self.recordingBuffer == 0 then 
        return -- If there's nothing in the buffer don't play
      elseif self.recording then
        return -- If we're recording don't play
      else
        self.playing = true
        self.playback_ref = clock.run(function() self:next_playback_position() end)
      end
    end,
    playback_stop = function(self)
      self.playing = false 

      if self.playback_ref then
        clock.cancel(self.playback_ref)
        self.playback_ref = nil
        self.bufferPosition = 1
      end
    end,
    next_playback_position = function(self)
      while self.playing do
        -- Use the held value is sample and hold is active
        if self.sampleAndHoldInput == 1 or self.sampleAndHoldInput == 2 then
          -- print('B:' .. self.bufferId .. ' S&H: ' .. self.heldValue)
          crow.output[self.bufferId].volts = self.heldValue
        else
          -- print('B:' .. self.bufferId .. ' V: ' .. self.recordingBuffer[self.bufferPosition])
          -- Otherwise use whatever is in the current buffer position
          crow.output[self.bufferId].volts = self.recordingBuffer[self.bufferPosition]
        end
        -- Update buffer position for playback and loop if at end
        self.bufferPosition = (self.bufferPosition % #self.recordingBuffer) + 1
        redraw()
        clock.sleep(sleepTime)
      end
    end,
    -- Quantization
    quantizedActive = false,
    sampleAndHoldInput = 0,
    scale = {},
    heldValue = 0,
    octaveMin = 2,
    octaveRange = 4,
    sampleAndHold = function(self)
      -- print('New s&h event on buffer ' .. self.bufferId)
      if #self.recordingBuffer == 0 then
        return -- Exit the function if the recording buffer is empty
      end
      
      -- Fetch the most recent value from the recordingBuffer
      local currentValue = self.recordingBuffer[self.bufferPosition]

      -- TODO: This needs to only draw if the pulse is happening on the on screen buffer
      draw_sh_pulse(self.bufferId)
      
      -- Determine if quantization is active and process accordingly
      if self.quantizedActive then
        -- Quantization is active:
        -- 1. Map the currentValue to a scale index within the output range
        local scaleIndex = math.floor(mapValue(currentValue, self.outputMin, self.outputMax, 1, #self.scale + 1))
        -- 2. Ensure the scaleIndex is within the bounds of the scale
        scaleIndex = capValue(scaleIndex, 1, #self.scale)
        -- 3. Select the note from the scale based on the scaleIndex
        local selectedNote = self.scale[scaleIndex]
        local noteInV8 = midiToVOct(selectedNote)
        
        -- print('Q ' .. selectedNote) -- Log the quantized note
        -- print('v/8 ' .. noteInV8) -- Log the v/oct note
        self.heldValue = noteInV8 -- Set the voltage to the helf value
      else
        -- Quantization is not active: use the currentValue directly
        -- print('R ' .. currentValue) -- Log the raw currentValue
        self.heldValue = currentValue -- Set the heldValue to the raw currentValue
      end
    end,
    buildScale = function(self)
      local rootNote =  (self.octaveMin * 12) + scaleKey
      self.scale = musicutil.generate_scale(rootNote, params:get("mode"), self.octaveRange)
    end
  }
end

function addParameters()
    params:add_separator('Path Tracer')
    
    params:add{
      type = "option",
      id = "scaleKey",
      name = "Key",
      options = musicutil.NOTE_NAMES,
      default = 1,
      action = function(value)
        scaleKey = value - 1 -- Store the selected index (adjusted for 0-based indexing used in buildScale math)
        for i = 1, 4 do
          buffers[i]:buildScale()
        end
      end
    }
    
    params:add{
      type = "option",
      id = "mode",
      name = "Mode",
      options = scaleNames,
      default = 1,
      action = function(value)
        for i = 1, 4 do
          buffers[i]:buildScale()
        end
      end
    }
      
    -- Create a group for individual buffer params
    for i = 1, 4 do
      params:add_group("Buffer " .. i, 5)
      -- Select voltage range
      params:add{
        type = "option",
        id = "voltage_range_" .. i,
        name = "Voltage Range",
        options = {"-5/5", "0/10", "0/5"},
        action = function(value)
            -- TODO: It there a better way to do this? getVoltageRange seems unnecessary
            buffers[i].outputMin, buffers[i].outputMax = getVoltageRange(value)
        end
      }
      -- Select crow input to trigger s&h
      local CROW_INPUT_OPTIONS={"Off", "1", "2"}
      params:add{
        type = "option",
        id = "sampleAndHoldInput_" .. i,
        name = "Crow S&H Input",
        options = CROW_INPUT_OPTIONS,
        default = tab.key(CROW_INPUT_OPTIONS, "Off"), 
        action = function(value)
          local input = CROW_INPUT_OPTIONS[value]
          if input == "off" then
            buffers[i].sampleAndHoldInput = 0
            params:hide("quantize_buffer_" .. i)
            params:hide("octaveMin_" .. i)
            params:hide("octaveMax_" .. i)
          else
            buffers[i].sampleAndHoldInput = tonumber(input)
            params:show("quantize_buffer_" .. i)
            if params:string("quantize_buffer_" .. i) == "On" then -- NB: params:string allows getting the option name for an options param
              params:show("octaveMin_" .. i)
              params:show("octaveMax_" .. i)              
            end
          end
          _menu.rebuild_params()
        end
      }
      params:add{
        type = "option",
        id = "quantize_buffer_" .. i,
        name = "S&H Quantize",
        options = {"Off", "On"},
        action = function(value)
          local status = (value == 2)
          buffers[i].quantizedActive = status
          if status then
             params:show("octaveMin_" .. i)
             params:show("octaveMax_" .. i)
          else
             params:hide("octaveMin_" .. i)
             params:hide("octaveMax_" .. i)
          end   
          _menu.rebuild_params()
        end
      }
      params:add{
        type = "number",
        id = "octaveMin_" .. i,
        name = "Base Octave",
        min = 0,
        max = 6,
        default = 2,
        action = function(value)
          buffers[i].octaveMin = value
          buffers[i]:buildScale()
        end
      }
      params:add{
        type = "number",
        id = "octaveMax_" .. i,
        name = "Octave Range",
        min = 0,
        max = 6,
        default = 1,
        action = function(value)
          buffers[i].octaveRange = value
          buffers[i]:buildScale()
        end
      }

      params:hide("octaveMin_" .. i)
      params:hide("octaveMax_" .. i)
    end
end



function init()
  -- Set up scale param
  for i = 1, #musicutil.SCALES do
    table.insert(scaleNames, musicutil.SCALES[i].name) 
  end

  addParameters()
  params:set("scaleKey", 0)
  -- scaleKey = 0
  params:set("mode", 1)
  -- mode = 1

  -- Create buffers
  for i = 1, 4 do
    table.insert(buffers, createBuffer(i))
  end
  

  for i = 1, 4 do
    buffers[i]:buildScale()
  end

  selectedBuffer = buffers[1]

  -- Wait for a pulse on crow input
  crow.input[1].change = function()
    -- Call the quantize function on all buffers
    for _, buffer in ipairs(buffers) do
      -- print("Buffer ID:", buffer.bufferId, "Quantized:", buffer.quantizedActive, "S&H Input:", buffer.sampleAndHoldInput)
      -- buffer.quantizedActive = true
      -- buffer.sampleAndHoldInput = 1
      if buffer.sampleAndHoldInput == 1 then
        buffer:sampleAndHold()
      end
    end
  end
  crow.input[1].mode("change", 1.0, 0.1, "rising")

  -- Wait for a pulse on crow input 2
  crow.input[2].change = function()
    -- Call the quantize function on all buffers with quantized = true and a matching sampleAndHoldInput number
    for _, buffer in ipairs(buffers) do
      if buffer.sampleAndHoldInput == 2 then
        buffer:sampleAndHold()
      end
    end
  end
  crow.input[2].mode("change", 1.0, 0.1, "rising")
end


function enc(id, delta)
  -- Select active buffer
  if id == 1 then
    -- turns off recording on last buffer before moving to the next
    if selectedBuffer.recording then
      selectedBuffer:toggleRecording()
    end
    
    selectedBufferId = capValue(selectedBufferId + delta, 1, 4)
    selectedBuffer = buffers[selectedBufferId]
    redraw()
  end

  -- If the active buffer is in record mode track the knob
  if id == 2 and buffers[selectedBufferId].recording then
    -- LATER: It's probably trivial to make this a function on the buffer
    local scaledDelta = delta * 2 -- This allows for one quick turn to go top-to-bottom.
    rawValue = capValue(rawValue + scaledDelta, rawValueMin, rawValueMax)
  end

  -- Still free
  if id == 3 then

  end
end

function key(id, state)
  local selectedBuffer = buffers[selectedBufferId]
  -- Toggle record on active buffer
  if id == 2 and state == 1 then
    if not selectedBuffer.recording then
      selectedBuffer:recording_start()
    elseif selectedBuffer.recording then
      selectedBuffer:recording_stop()
    end
  -- Toggle playback based on current state
  elseif id == 3 and state == 1 then
    if not selectedBuffer.playing then
      selectedBuffer:playback_start()
    elseif selectedBuffer.playing then
      selectedBuffer:playback_stop()
    end
  end
  redraw()
end

function draw_metadata_container(selectedBuffer)
  screen.level(6)
  screen.move(0, 50)
  screen.line(128, 50)
  screen.move(1,60)
  screen.text('Buffer ' .. selectedBuffer.bufferId)
end

function draw_buffer_status(selectedBuffer)
  screen.level(15)
  screen.move(122, 60)
  if selectedBuffer.recording then
    screen.text('R')
  elseif selectedBuffer.playing then
    screen.text('P')
  end
end

function draw_sample_and_hold_status(selectedBuffer)
  screen.level(15)
  if selectedBuffer.sampleAndHoldInput ~= 0 then
    screen.move(100, 60)
    screen.text('C' .. selectedBuffer.sampleAndHoldInput)
  end
end

function draw_quantization_status(selectedBuffer)
  screen.level(15)
  if selectedBuffer.quantizedActive then
    screen.move(112, 60)
    screen.text('Q')
  end
end

function draw_center_line(selectedBuffer)
  if selectedBuffer.outputMin == -5 and selectedBuffer.outputMax == 5 then
    screen.level(1)
    for x = 0, 128, 4 do
      screen.move(x, 25)
      screen.line_rel(2, 0)
    end
    screen.stroke()
  end
end

function drawUi()
  screen.font_size(8)

  draw_metadata_container(selectedBuffer)
  draw_buffer_status(selectedBuffer)
  draw_sample_and_hold_status(selectedBuffer)
  draw_quantization_status(selectedBuffer)
  draw_center_line(selectedBuffer)
end

function draw_sh_pulse(bufferId)
  if bufferId == selectedBuffer.bufferId then
    screen.level(1)

    if selectedBuffer.sampleAndHoldInput == 1 then
      screen.rect(99, 54, 10, 8)
    elseif selectedBuffer.sampleAndHoldInput == 2 then
      screen.rect(99, 54, 11, 8)
    end

    screen.update()

    clock.run(function()
      clock.sleep(0.25)
      clear_sh_pulse()
    end)

    redraw()
  end
end

function clear_sh_pulse()
  redraw()
end

function drawRecordingScope()
  screen.level(8)
  local start = math.max(1, #selectedBuffer.recordingBuffer - 64)
  local current = #selectedBuffer.recordingBuffer
  for i = start, current do
    local x = 64 + (i - current) * 2
    local y = ((selectedBuffer.recordingBuffer[i] - selectedBuffer.outputMin) / (selectedBuffer.outputMax - selectedBuffer.outputMin)) * 50
    y = 50 - y -- flip the y-axis
    if i == start then
      screen.move(x, y)
    else
      screen.line(x, y)
    end
    -- Change line level based on distance from current position
    local distance = math.abs(i - current)
    local level = math.max(1, 5 - distance) -- Adjusted here
    screen.level(level)
    screen.stroke() -- Draw the line segment with the current level
    -- Highlight current position
    if i == current then
      screen.circle(x, y, 2) -- Highlight current position
      screen.fill()
      screen.move(x, y) -- Start a new path for the rest of the line
    else
      screen.move(x, y) -- Start a new path for the next line segment
    end
  end
end

function drawPlayingScope()
  local start = math.max(1, selectedBuffer.bufferPosition - 32)
  local stop = math.min(#selectedBuffer.recordingBuffer, selectedBuffer.bufferPosition + 32)
  for i = start, stop do
    local x = 64 + (i - selectedBuffer.bufferPosition) * 2
    local y = ((selectedBuffer.recordingBuffer[i] - selectedBuffer.outputMin) / (selectedBuffer.outputMax - selectedBuffer.outputMin)) * 50
    y = 50 - y -- flip the y-axis
    if i == start then
      screen.move(x, y)
    else
      screen.line(x, y)
    end
    -- Change line level based on distance from current position
    local distance = math.abs(i - selectedBuffer.bufferPosition)
    local level = math.max(1, 5 - distance) -- Adjusted here
    screen.level(level)
    screen.stroke() -- Draw the line segment with the current level
    -- Highlight current position
    if i == selectedBuffer.bufferPosition then
      screen.circle(x, y, 2) -- Highlight current position
      screen.fill()
      screen.move(x, y) -- Start a new path for the rest of the line
    else
      screen.move(x, y) -- Start a new path for the next line segment
    end
  end
end

function drawIdleScope()
  local stop = math.min(#selectedBuffer.recordingBuffer, 128)
  for i = 1, stop do
    local x = i * 2
    local y = ((selectedBuffer.recordingBuffer[i] - selectedBuffer.outputMin) / (selectedBuffer.outputMax - selectedBuffer.outputMin)) * 50
    y = 50 - y -- flip the y-axis
    if i == 1 then
      screen.move(x, y)
    else
      screen.level(1)
      screen.line(x, y)
    end
  end
  screen.stroke() -- Draw the line segment
end


function redraw()
  screen.clear()

  drawUi()
  if selectedBuffer.recording then
    drawRecordingScope()
  elseif selectedBuffer.playing then
    drawPlayingScope()
  else
    drawIdleScope()
  end

  screen.update()
end