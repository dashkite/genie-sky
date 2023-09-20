import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:schema:validate", run "validate", options
  
  if options.schema.auto == true
    Genie.before "build", "sky:schema:validate"
