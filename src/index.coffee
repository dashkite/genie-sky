import * as Logger from "@dashkite/dolores/logger"

import zip from "./zip"
import secrets from "./secrets"
import role from "./role"
import lambda from "./lambda"
import alb from "./alb"
import edge from "./edge"
import bridge from "./bridge"
import stepFunction from "./step-function"
import buckets from "./s3"
import tables from "./dynamodb"
import cloudfront from "./cloudfront"
import graphene from "./graphene"
import queues from "./queue"
import ses from "./ses"
import _module from "./module"
import schema from "./schema"

export default (genie) ->
  
  genie.define "sky:clean", -> Logger.clean()
  genie.before "clean", "sky:clean"
  
  if (options = genie.get "sky")?
    zip genie, options
    secrets genie, options
    role genie, options
    lambda genie, options
    alb genie, options
    edge genie, options
    bridge genie, options
    stepFunction genie, options
    buckets genie, options
    tables genie, options
    cloudfront genie, options
    graphene genie, options
    queues genie, options
    ses genie, options
    _module genie, options
    schema genie, options
