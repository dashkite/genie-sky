import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  if options.lambda?
    Genie.define "sky:edge:deploy", "sky:lambda:version-all",
      run "deploy", options    
  else
    Genie.define "sky:edge:deploy", run "deploy", options          
    
  Genie.define "sky:edge:undeploy", run "undeploy", options

  Genie.on "deploy", "sky:edge:deploy"
  Genie.on "undeploy", "sky:edge:undeploy"
