function init()
    -- Configure crow input 1 to detect a trigger
    crow.input[1].change = function(s)
      if s > 0 then -- Check if the signal is a trigger (rising edge)
        print("hello")
      end
    end
    crow.input[1].mode("change", 1.0, 0.1, "rising") -- Set mode to 'change' with appropriate parameters for trigger detection
  end