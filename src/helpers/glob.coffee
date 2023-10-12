import * as Glob from "fast-glob"

glob = ( options ) ->
  Glob.glob options.glob, {
    cwd: options.root
    options...
  }

export { glob }