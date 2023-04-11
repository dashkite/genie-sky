import { getDRN, getDomain } from "./helpers"
import { Name } from "@dashkite/name"

import {
  getSecretARN
  getWildcardARN
} from "@dashkite/dolores/secrets"

import { 
  createRole
} from "@dashkite/dolores/roles"

import {
  getLambdaUnqualifiedARN
} from "@dashkite/dolores/lambda"

import {
  getStepFunctionARN
} from "@dashkite/dolores/step-function"

import {
  getBucketARN
} from "@dashkite/dolores/bucket"

import {
  getTableARN
} from "@dashkite/dolores/dynamodb"

import {
  getQueueARN
} from "@dashkite/dolores/queue"

import {
  log
} from "@dashkite/dolores/logger"

import {
  create as getTopic
} from "@dashkite/dolores/sns"

buildCloudWatchPolicy = (name, handler) ->
  region = handler.region ? "us-east-1"

  Effect: "Allow"
  Action: [
    "logs:CreateLogGroup"
    "logs:CreateLogStream"
    "logs:PutLogEvents"
  ]
  Resource: [ 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{name}:*" 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{region}.#{name}:*" 
  ]

buildSecretsPolicy = (secrets) ->
  Effect: "Allow"
  Action: [ "secretsmanager:GetSecretValue" ]
  Resource: await do ->
    for secret in secrets
      if secret.type == "wildcard"
        log "secrets", "build-policy", 
          "authorize secret access for wildcard scope: #{ secret.name }"
        await getWildcardARN secret.name
      else
        log "secrets", "build-policy", 
          "authorize secret access for: #{ secret.name }"
        await getSecretARN secret.name

mixinPolicyBuilders =

  managedPolicies: (mixin) ->
    [
      managedPolicies:
          - "arn:aws:iam::618441030511:policy/WayboxManagerRole"
    ]

  graphite: (mixin, base) ->
    
    region = mixin.region ? "us-east-1"

    [
      Effect: "Allow"
      Action: [ "dynamodb:*" ]
      Resource: do ->
        resources = []
        for table in mixin.tables
          _table = "#{base}-#{table}"
          resources.push "arn:aws:dynamodb:#{region}:*:table/#{_table}"
          resources.push "arn:aws:dynamodb:#{region}:*:table/#{_table}/*"
        resources
    ]

  s3: (mixin) ->

    [
      Effect: "Allow"
      Action: [ "s3:*" ]
      Resource: await do ->
        resources = []
        domain = await getDomain mixin.uri
        resources.push "arn:aws:s3:::#{domain}"
        resources.push "arn:aws:s3:::#{domain}/*"
        resources
    ]


  kms: (mixin, base) ->

    # TODO allow for use of keys
    # see also: https://github.com/pandastrike/sky-mixin-kms/blob/master/src/policy.coffee#L4-L26

    [

      Effect: "Allow"
      Action: [
        "kms:GenerateRandom"
      ]
      Resource: ["*"]

    ]

  lambda: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "lambda:InvokeFunction"
      ]
      Resource: [
        await getLambdaUnqualifiedARN await getDRN mixin.uri
      ]

    ]

  ses: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "ses:SendTemplatedEmail"
      ]
      Resource: [
        "arn:aws:ses:us-west-2:618441030511:identity/dashkite.com"
      ]

    ]

  cloudfront: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "cloudfront:ListDistributions"
        "cloudfront:CreateInvalidation"
      ]
      Resource: ["*"]

    ]

  "step-function": do (self = false, managed = null) ->
    managed = [
        Effect: "Allow"
        Action:[
          "events:PutTargets"
          "events:PutRule"
          "events:DescribeRule"
        ]
        Resource: [
          "arn:aws:events:us-east-1:618441030511:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"
        ]
      ,
        Effect: "Allow"
        Action:[
          "states:DescribeExecution"
          "states:StopExecution"
          "states:ListStateMachines"
        ]
        Resource: '*'
    ]

    (mixin) ->
      policies = [
        Effect: "Allow"
        Action: [ 
          "states:startExecution" 
        ]
        Resource: [ await getStepFunctionARN mixin.name ]      
      ]

      if self == false
        policies.push managed...
        self = true

      policies

  bucket: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "s3:GetObject"
        "s3:PutObject"
        "s3:DeleteObject"
      ]
      Resource: "#{ getBucketARN mixin.name }/*"

    ]

  table: (mixin) ->
    [

      Effect: "Allow"
      Action: [ "dynamodb:*" ]
      Resource: [
        getTableARN mixin.name
        "#{getTableARN mixin.name}/*"
      ] 

    ]

  queue: (mixin) ->
    [
      Effect: "Allow"
      Action: [
        "sqs:CreateQueue"
        "sqs:DeleteQueue"
        "sqs:GetQueueUrl"
        "sqs:DeleteMessage"
        "sqs:ReceiveMessage"
        "sqs:SendMessage"
      ]
      Resource: if mixin.name?
        await getQueueARN mixin.name
      else
        "arn:aws:sqs:*:*:*"

    ]

  sns: ( mixin ) ->
    [
      Effect: "Allow"
      Action: [
        "sns:CreateTopic"
        "sns:DeleteTopic"
        "sns:Publish"
        "sns:Subscribe"
      ]
      Resource: ( await getTopic mixin.name ).arn
    ]

builders = mixinPolicyBuilders
builders.sqs = builders.queue
  

buildMixinPolicy = (mixin, base) ->
  if ( builder = mixinPolicyBuilders[ mixin.type ])?
    builder mixin, base
  else
    throw new Error "Unknown mixin [ #{mixin} ] for [ #{base} ]"

export default (genie, options) ->
  { namespace, lambda, mixins, secrets, buckets, tables, queues } = options

  # TODO add delete / teardown
  # TODO add support for multiple lambdas
  
  genie.define "sky:roles:publish", ->

    for handler in ( lambda?.handlers ? [] )

      drn = await getDRN Name.getURI { type: "lambda", namespace, name: handler.name }

      # TODO possibly explore how to split out role building
      # TODO allow for different policies for different handlers
      policies = [ ( buildCloudWatchPolicy drn, handler ) ]

      if secrets? && secrets.length > 0
        policies.push await buildSecretsPolicy secrets

      if buckets? && buckets.length > 0
        for bucket in buckets
          _bucket = { bucket..., type: "bucket" }
          policies.push ( await buildMixinPolicy _bucket, drn )...

      if tables? && tables.length > 0
        for table in tables
          _table = { table..., type: "table" }
          policies.push ( await buildMixinPolicy _table, drn )...

      if queues? && queues.length > 0
        for queue in queues
          _queue = { queue..., type: "queue" }
          policies.push ( await buildMixinPolicy _queue, drn )...

      # if sqs? && sqs.length > 0
      #   for item in sqs
      #     policies.push builders.sqs item

      if mixins?
        for mixin in mixins
          if mixin.uri?
            description = Name.parse mixin.uri
            mixin = { description..., mixin... }
          if ( builder = builders[ mixin.type ] )?
            policies.push ( await builder mixin )...

      await createRole drn, policies, options[ "managed-policies" ]

  genie.define "sky:roles:delete", ->
    for handler in ( lambda?.handlers ? [] )
      drn = await getDRN  Name.getURI { type: "lambda", namespace, name: handler.name }
      deleteRole drn