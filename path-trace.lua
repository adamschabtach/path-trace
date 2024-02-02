-- Four looping, recordable bufers with independent quantization

musicutil = require 'musicutil' -- Musicutil library for quantization support

-- Configuration Variables
sleepTime = 0.05 -- Time in between recording 50ms fairly arbitrary
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
    return (rawValue - rawMin) / (rawMax - rawMin) * (outMax - outMin) + outMin
end

-- Creates buffer object with cv data buffer, recording logic, and playback control
function createBuffer(bufferId)
  return {
    -- Metadata
    bufferId = bufferId,
    outputMin = -5,
    outputMax = 5,
    -- Playback
    recording = false,
    playing = false,
    recordingRef = nil,
    recordingBuffer = {},
    bufferPosition = 1,
    -- Quantization
    quantizedActive = false,
    sampleAndHoldInput = 0,
    scale = {},
    heldValue = 0,
    octaveMin = 2,
    octaveRange = 4,
    toggleRecording = function(self)
      if not self.recording then
        self.playing = false
        self.recording = true
        self.recordingBuffer = {}
        self.recordingRef = clock.run(self.addToBuffer, self)
      else
        self.recording = false
        -- After turning off, reset buffer 
        rawValue = 0
        self.bufferPosition = 1
      end
      redraw()
    end,
    addToBuffer = function(self)
      while self.recording do
        -- Transform and save knob position 
        local rawInCv = mapValue(rawValue, rawValueMin, rawValueMax, self.outputMin, self.outputMax)
        table.insert(self.recordingBuffer, rawInCv)

        -- Output the voltage
        crow.output[self.bufferId].volts = self.recordingBuffer[#self.recordingBuffer]

        redraw()
        clock.sleep(sleepTime)
      end
    end,
    playBuffer = function(self)
      while self.playing do
        if #self.recordingBuffer == 0 then
          self.playing = false
        else
          -- If sample and hold is active
          if not self.sampleAndHoldInput == 0 then
            crow.output[self.bufferId].volts = self.heldValue
          else
            crow.output[self.bufferId].volts = self.recordingBuffer[self.bufferPosition]
          end
          -- Update buffer position for playback
          -- Loop if at end
          self.bufferPosition = (self.bufferPosition % #self.recordingBuffer) + 1
        end
        redraw()
        clock.sleep(sleepTime)
      end
    end,
    sampleAndHold = function(self)
      -- Use the most recent value from the recordingBuffer
      local currentValue = self.recordingBuffer[self.bufferPosition]

      -- Map the currentValue within the output range to a scale index
      local scaleIndex = math.floor(mapValue(currentValue, self.outputMin, self.outputMax, 1, #self.scale + 1))
      scaleIndex = capValue(scaleIndex, 1, #self.scale) -- Ensure the index is within the scale's bounds

      local selectedNote = self.scale[scaleIndex]
      -- If quantized is active, use the selected note
      if self.quantizedActive then
        self.heldValue = selectedNote
      else
        -- If quantization is not active, directly use the currentValue
        self.heldValue = currentValue
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
      
    -- Add voltage range parameters in a group
    for i = 1, 4 do
      params:add_group("Buffer " .. i, 5)
      params:add{
        type = "option",
        id = "voltage_range_" .. i,
        name = "Voltage Range",
        options = {"-5/5", "0/10", "0/5"},
        action = function(value)
            -- update the voltage range for the current buffer
            buffers[i].outputMin, buffers[i].outputMax = getVoltageRange(value)
        end
      }
      params:add{
        type = "option",
        id = "sampleAndHoldInput_" .. i,
        name = "Sample And Hold Input",
        options = {"0", "1", "2"},
        default = 1, -- Default to 0, adjust according to your needs
        action = function(value)
          buffers[i].sampleAndHoldInput = tonumber(value)
        end
      }
      params:add{
        type = "option",
        id = "quantize_buffer_" .. i,
        name = "Quantize",
        options = {"Off", "On"},
        action = function(value)
          buffers[i].quantizedActive = (value == 2)
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
    end
end



function init()
  -- Set up scale param
  for i = 1, #musicutil.SCALES do
    table.insert(scaleNames, musicutil.SCALES[i].name) 
  end
  scaleKey = 0
  mode = 1

  -- Create buffers
  for i = 1, 4 do
    table.insert(buffers, createBuffer(i))
  end
  
  addParameters()

  for i = 1, 4 do
    buffers[i]:buildScale()
  end

  selectedBuffer = buffers[1]

  -- Wait for a pulse on crow input 1
  crow.input[1].change = function()
    -- Call the quantize function on all buffers
    for _, buffer in ipairs(buffers) do
        if buffer.quantizedActive and buffer.sampleAndHoldInput == 1 then
            buffer:sampleAndHold()
        end
    end
  end

  -- Wait for a pulse on crow input 2
  crow.input[2].change = function()
    -- Call the quantize function on all buffers with quantized = true and a matching sampleAndHoldInput number
    for _, buffer in ipairs(buffers) do
      if buffer.quantizedActive and buffer.sampleAndHoldInput == 2 then
        buffer:sampleAndHold()
      end
    end
  end
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
    rawValue = capValue(rawValue + delta, rawValueMin, rawValueMax)
  end

  -- Still free
  if id == 3 then
    buffers[1]:sampleAndHold()
  end
end

function key(id, state)
  -- Toggle record on active buffer
  if id == 2 and state == 1 then
    -- Turning recording on turns playing off
    buffers[selectedBufferId]:toggleRecording()
  -- Toggle play state and kicks off play routine
  -- LATER: Should this also be a method like above?
  elseif id == 3 and state == 1 then
    buffers[selectedBufferId].playing = not buffers[selectedBufferId].playing

    if buffers[selectedBufferId].playing then
      clock.run(buffers[selectedBufferId].playBuffer, buffers[selectedBufferId])
    end
  end
  redraw()
end

function drawUi()
  -- UI Chrome
  screen.level(6)
  screen.move(0, 50)
  screen.line(128, 50)

  screen.font_size(8)
  screen.move(1,60)
  screen.text('Buffer ' .. selectedBuffer.bufferId)
  
  if selectedBuffer.recording then
    screen.move(100, 60)
    screen.text_right('REC')
  end
  
  if selectedBuffer.playing then
    screen.move(124, 60)
    screen.text_right('PLAY')
  end
  screen.stroke()

  -- There are 50 vertical pixels for the scope so the center is at 25
  -- Only draw the dotted line if the range is -5/+5
  if selectedBuffer.outputMin == -5 and selectedBuffer.outputMax == 5 then
    screen.level(1)
    for x = 0, 128, 4 do
      screen.move(x, 25)
      screen.line_rel(2, 0)
    end
    screen.stroke()
  end
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
  -- Scope in record mode
  -- Current position is centered horizontally with past value flowing to the left
  if selectedBuffer.recording then
    drawRecordingScope()
  -- Scope in play mode
  -- Current playhead is centered horizontally with past buffer to left and upcoming buffer to right
  elseif selectedBuffer.playing then
    drawPlayingScope()
  else
    drawIdleScope()
  end

  screen.update()
end