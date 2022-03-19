guard = (f) ->
  (args...) ->
    for i in [ 0..( f.length - 1 ) ]
      if !args[i]?
        throw new Error "sky:presets: this task requires all arguments to be
          specified."
    
    f args...

export { guard }