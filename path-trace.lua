-- Four looping, recordable bufers with independent quantization
-- NEXT: s&h/quantization coming in from crow inputs

-- Config
-- Hardcoded time enabling "high resolution" recording. All the clocks sleep on this
sleepTime = 0.05

-- Selected using e1
activeBufferId = 1

-- NEXT: The global recording with local-to-buffer transformation is weird. Revisit this.
activeEnc2 = 0

-- Buffer objects with cv data, recording logic, and playback control
function createBuffer(bufferId)
  return {
    bufferId = bufferId,
    recording = false,
    playing = false,
    bufferPosition = 1,
    recordingBuffer = {},
    recordingRef = null,
    toggleRecording = function(self)
      if not self.recording then
        self.recording = true
        self.recordingBuffer = {}
        self.recordingRef = clock.run(self.addToBuffer, self)
      else
        self.recording = false
        activeEnc2 = 0
        self.bufferPosition = 1
      end
      redraw()
    end,
    addToBuffer = function(self)
      while self.recording do
        -- Transform and save knob position 
        local enc2InCv = activeEnc2 / 20
        table.insert(self.recordingBuffer, enc2InCv)

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
          self.bufferPosition = (self.bufferPosition % #self.recordingBuffer) + 1

        end
        redraw()
        clock.sleep(sleepTime)
      end
    end
  }
end

buffers = {}
for i = 1, 4 do
  table.insert(buffers, createBuffer(i))
end

function capValue(value, min, max)
  return math.min(math.max(value, min), max)
end

function enc(id, delta)
  -- Select active buffer
  if id == 1 then
    if buffers[activeBufferId].recording then
      buffers[activeBufferId]:toggleRecording()
    end
    
    activeBufferId = capValue(activeBufferId + delta, 1, 4)
    redraw()
  end

  -- If the active buffer is in record mode track the knob
  if id == 2 and buffers[activeBufferId].recording then
    activeEnc2 = capValue(activeEnc2 + delta, -100, 100)
  end

  -- Eventually want e3 to pick quantization
end

function key(id, state)
  -- Toggle record on active buffer
  if id == 2 and state == 1 then
    -- TODO: Turning on recording should turn off playing
    buffers[activeBufferId]:toggleRecording()

  -- Toggle playback on active buffer
  elseif id == 3 and state == 1 then
    -- Change buffer[activeBufferId].playing to opposite of current state
    buffers[activeBufferId].playing = not buffers[activeBufferId].playing

    if buffers[activeBufferId].playing then
      clock.run(buffers[activeBufferId].playBuffer, buffers[activeBufferId])
    end
    redraw()
  end
end

function redraw()
  local activeBuffer = buffers[activeBufferId]
  screen.clear()

  -- Debug
  -- screen.move(10, 10)
  -- screen.text('Buffer Position ' .. activeBuffer.bufferPosition)

  -- if activeBuffer.recordingBuffer[activeBuffer.bufferPosition] then
  --   screen.move(10, 20)
  --   screen.text('Voltage ' .. activeBuffer.recordingBuffer[activeBuffer.bufferPosition])
  -- end

  -- UI Chrome
  screen.level(6)
  screen.move(0, 50)
  screen.line(128, 50)

  screen.font_size(8)
  screen.move(1,60)
  screen.text('Buffer ' .. activeBuffer.bufferId)
  
  if activeBuffer.recording then
    screen.move(100, 60)
    screen.text_right('REC')
  end
  
  if activeBuffer.playing then
    screen.move(124, 60)
    screen.text_right('PLAY')
  end
  screen.stroke()

  -- There are 50 vertical pixels for the scope so the center is at 25
  screen.level(1)
  for x = 0, 128, 4 do
    screen.move(x, 25)
    screen.line_rel(2, 0)
  end
  screen.stroke()

  -- Scope
  
  -- Scope in record mode
  -- Current position is centered horizontally with past value flowing to the left
  if activeBuffer.recording then
    screen.level(8)
    local start = math.max(1, #activeBuffer.recordingBuffer - 64)
    local current = #activeBuffer.recordingBuffer
    for i = start, current do
      local x = 64 + (i - current) * 2
      local y = ((activeBuffer.recordingBuffer[i] + 5) / 10) * 50
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
  
  -- Scope in play mode
  -- Current playhead is centered horizontally with past buffer to left and upcoming buffer to right
  if activeBuffer.playing then
    local start = math.max(1, activeBuffer.bufferPosition - 32)
    local stop = math.min(#activeBuffer.recordingBuffer, activeBuffer.bufferPosition + 32)
    for i = start, stop do
      local x = 64 + (i - activeBuffer.bufferPosition) * 2
      local y = ((activeBuffer.recordingBuffer[i] + 5) / 10) * 50
      y = 50 - y -- flip the y-axis
      if i == start then
        screen.move(x, y)
      else
        screen.line(x, y)
      end
      -- Change line level based on distance from current position
      local distance = math.abs(i - activeBuffer.bufferPosition)
      local level = math.max(1, 5 - distance) -- Adjusted here
      screen.level(level)
      screen.stroke() -- Draw the line segment with the current level
      -- Highlight current position
      if i == activeBuffer.bufferPosition then
        screen.circle(x, y, 2) -- Highlight current position
        screen.fill()
        screen.move(x, y) -- Start a new path for the rest of the line
      else
        screen.move(x, y) -- Start a new path for the next line segment
      end
    end
  end

  screen.update()
end