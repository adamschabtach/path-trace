-- Four looping, recordable bufers with independent quantization
-- NEXT: s&h/quantization coming in from crow inputs

-- Config
-- Hardcoded time enabling "high resolution" recording. All the clocks sleep on this
sleepTime = 0.05
-- The buffers where we store everything
buffers = {}

-- Gobal recording buffer config
-- Transformed by buffer[bufferId]:addToBuffer() and mapped locally. Maybe this moves to a buffer table one day too.
rawValue = 0
rawValueMin = -100
rawValueMax = 100

-- Selected using e1
selectedBufferId = 1

-- Creates buffer object with cv data buffer, recording logic, and playback control
function createBuffer(bufferId)
  return {
    bufferId = bufferId,
    recording = false,
    playing = false,
    bufferPosition = 1,
    recordingBuffer = {},
    recordingRef = null,
    outputMin = -5,
    outputMax = 5,
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
          -- Output voltage
          local currentValue = self.recordingBuffer[self.bufferPosition]
          crow.output[self.bufferId].volts = currentValue
          
          -- Update buffer position for playback
          -- Loop if at end
          self.bufferPosition = (self.bufferPosition % #self.recordingBuffer) + 1
        end
        redraw()
        clock.sleep(sleepTime)
      end
    end
  }
end


function init()
  -- Create buffers
  for i = 1, 4 do
    table.insert(buffers, createBuffer(i))
  end

  params:add_separator('Path Tracer')
  -- Add voltage range parameters in a group
  for i = 1, 4 do
    params:add_group("Buffer " .. i, 1)
    params:add{
      type = "option",
      id = "voltage_range_" .. i,
      name = "Voltage Range",
      options = {"-5/5", "0/10", "0/5"},
      action = function(value)
          -- update the voltage range for the current buffer
          buffers[i].outputMin, buffers[i].outputMax = getVoltageRange(value)
          print(buffers[i].outputMin)
      end
    }
  end

  selectedBuffer = buffers[1]
end

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
    print("encoder 3")
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