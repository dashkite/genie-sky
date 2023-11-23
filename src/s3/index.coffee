import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Genie.define "sky:s3:deploy", run "deploy", options
  Genie.define "sky:s3:undeploy", run "undeploy", options
  Genie.define "sky:s3:publish", run "publish", options
  Genie.define "sky:s3:watch", run "watch", options

  Genie.on "deploy", "sky:s3:deploy"
  Genie.on "undeploy", "sky:s3:undeploy"
  Genie.on "publish", "sky:s3:publish"
  Genie.on "watch", "sky:s3:watch&"

