import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:alb:deploy", run "deploy", options 
  Genie.define "sky:alb:undeploy", run "undeploy", options

  Genie.on "deploy", "sky:alb:deploy"
  Genie.on "undeploy", "sky:alb:undeploy"