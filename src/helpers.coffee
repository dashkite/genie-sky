import FS from "fs/promises"
import sort from "sort-package-json"

guard = (f) ->
  (args...) ->
    if f.length > 0
      for i in [ 0..( f.length - 1 ) ]
        if !args[i]?
          throw new Error "sky:presets: this task requires all arguments to be
            specified."
    
    f args...


getPackage = do (cache = null) -> ->
  cache ?= JSON.parse await FS.readFile "./package.json", "utf8"


export { guard, getPackage }