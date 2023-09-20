import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->
  
  Genie.define "sky:ses:deploy", run "deploy", options
  Genie.define "sky:ses:undeploy", run "undeploy", options

  Genie.on "deploy", "sky:ses:deploy"
  Genie.on "undeploy", "sky:ses:undeploy"
