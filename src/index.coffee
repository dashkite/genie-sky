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
import schema from "./schema"
import { Mixins } from "./mixins"

export default (genie) ->
  
  genie.define "sky:clean", -> Logger.clean()
  genie.before "clean", "sky:clean"
  genie.define "sky:env", ->
    options = genie.get "sky"
    { mixins } = options
    options.env = mode: process.env.mode ? "development"
    if mixins?
      options.env.context = await Mixins.apply mixins, genie
  genie.before "pug", "sky:env"
  
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
    schema genie, options
