import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, { namespace, dynamodb }) ->

  { tables } = dynamodb ? {}
  options = { namespace, dynamodb, tables }

  Genie.on "deploy", "sky:dynamodb:deploy"
  Genie.on "undeploy", "sky:dynamodb:undeploy"
  Genie.define "sky:dynamodb:deploy", run "deploy", options
  Genie.define "sky:dynamodb:undeploy", run "undeploy", options
