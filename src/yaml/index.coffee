import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:yaml:build", run "build", options
  Genie.define "sky:yaml:watch", run "watch", options

  Genie.on "build", "sky:yaml:build"
  Genie.on "watch", "sky:yaml:watch"

