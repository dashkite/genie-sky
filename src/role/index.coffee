import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:roles:deploy", run "deploy", options
  Genie.define "sky:roles:undeploy", run "undeploy", options
