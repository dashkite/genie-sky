import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:s3:deploy", run "deploy", options
  Genie.define "sky:s3:undeploy", run "undeploy", options
  Genie.define "sky:s3:publish", run "publish", options

  Genie.on "deploy", "sky:s3:deploy"
  Genie.on "publish", "sky:s3:publish"

