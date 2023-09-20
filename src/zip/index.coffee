import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )
  
export default ( Genie, options ) ->

  Genie.define "sky:zip", run "zip", options
  Genie.define "sky:zip:clean", run "clean", options
  Genie.on "clean", "sky:zip:clean"

